import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/queue_rules.dart';
import '../services/audio_handler.dart';
import '../services/song_details.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_play_pause.dart';
import '../theme/noor_search_button.dart';
import '../theme/noor_song_card.dart';
import '../theme/noor_turntable.dart';
import '../theme/noor_widgets.dart';
import 'home_screen.dart';
import 'main_shell.dart';
import 'upnext_screen.dart';

// ── Panel visibility state ────────────────────────────────────────────────────
enum _PanelState { none, list, naming }

/// Up next rises from the bottom.
class _SlideUpRoute extends PageRouteBuilder {
  _SlideUpRoute()
      : super(
          opaque: false,
          barrierDismissible: false,
          pageBuilder: (_, __, ___) => const UpNextScreen(),
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 320),
          transitionsBuilder: (_, anim, __, child) => SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(CurvedAnimation(
                    parent: anim,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic)),
            child: child,
          ),
        );
}

/// The player: "Noor" and Search on top, the turntable (the record's label
/// is the song's artwork), the title, the bar progress line, then shuffle,
/// previous, play/pause, next and repeat-one.
///
/// Gestures:
/// * swipe left / right on the turntable: next / previous song. The arm
///   lifts, the record slides out (to the left for next, to the right for
///   previous), the new one slides in from the other side, and the arm comes
///   back down once the song has loaded;
/// * tap the turntable: play / pause; double tap: like / unlike;
/// * swipe down: the song's details drop from the top;
/// * swipe up: Up next rises from the bottom.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with TickerProviderStateMixin {
  // Record swap: phase out (old record leaves), then phase in.
  late final AnimationController _slide = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 360));
  bool _swapping = false;
  bool _inPhase = false;
  int _outDir = -1; // -1: leaves to the left (next), 1: to the right
  String? _artOverride;

  late final AnimationController _heartCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  bool _heartBecomingLiked = true;

  bool _shuffle = false;
  bool _repeatOne = false;

  // ── Add-to-playlist panels ────────────────────────────────────────────────
  _PanelState _panelState = _PanelState.none;
  late final AnimationController _listPanelCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 380));
  late final AnimationController _namePanelCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 340));
  late final Animation<Offset> _listSlide =
      Tween<Offset>(begin: const Offset(1.0, 0), end: Offset.zero).animate(
          CurvedAnimation(
              parent: _listPanelCtrl,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic));
  late final Animation<Offset> _nameSlide =
      Tween<Offset>(begin: const Offset(-1.0, 0), end: Offset.zero).animate(
          CurvedAnimation(
              parent: _namePanelCtrl,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic));
  late final Animation<double> _listFade =
      CurvedAnimation(parent: _listPanelCtrl, curve: Curves.easeOut);
  late final Animation<double> _nameFade =
      CurvedAnimation(parent: _namePanelCtrl, curve: Curves.easeOut);
  final TextEditingController _nameCtrl = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    try {
      final mode = ref.read(audioHandlerProvider).playMode;
      _shuffle = mode == PlayMode.shuffle;
      _repeatOne = mode == PlayMode.repeatOne;
    } catch (_) {/* no handler in tests */}
  }

  @override
  void dispose() {
    _slide.dispose();
    _heartCtrl.dispose();
    _listPanelCtrl.dispose();
    _namePanelCtrl.dispose();
    _nameCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // ── Song changes ──────────────────────────────────────────────────────────

  List<Song> _contextOf(Song s) => contextListFor(s,
      playlists: ref.read(playlistProvider),
      liked: ref.read(likedSongsProvider),
      history: ref.read(historyProvider));

  Song _target(Song current, int step) {
    if (_shuffle && step > 0) {
      final pool = _contextOf(current)
          .where((s) => s.videoId != current.videoId)
          .toList();
      if (pool.isNotEmpty) return pool[Random().nextInt(pool.length)];
    }
    return neighbourOf(current, step,
        playlists: ref.read(playlistProvider),
        liked: ref.read(likedSongsProvider),
        history: ref.read(historyProvider));
  }

  Future<void> _change(int step) async {
    final current = ref.read(playerProvider).displaySong;
    if (current == null || _swapping) return;
    HapticFeedback.selectionClick();
    final target = _target(current, step);
    setState(() {
      _swapping = true;
      _inPhase = false;
      _outDir = step > 0 ? -1 : 1;
      _artOverride = current.thumbnailUrl;
    });
    _slide.value = 0;
    await Future<void>.delayed(const Duration(milliseconds: 320)); // arm lifts
    if (!mounted) return;
    await _slide.forward(from: 0); // old record leaves
    if (!mounted) return;
    ref
        .read(playerProvider.notifier)
        .playSong(target, queue: _contextOf(target));
    setState(() {
      _inPhase = true;
      _artOverride = null;
    });
    await _slide.forward(from: 0); // new record arrives
    if (mounted) setState(() => _swapping = false);
  }

  void _togglePlay(NebulaPlayerState ps) {
    HapticFeedback.lightImpact();
    final n = ref.read(playerProvider.notifier);
    if (ps.status == NebulaPlayerStatus.error) {
      n.retryCurrentSong();
    } else {
      n.togglePlay();
    }
  }

  void _toggleLike(Song song, bool liked) {
    HapticFeedback.mediumImpact();
    _heartBecomingLiked = !liked;
    ref.read(likedProvider.notifier).toggle(song);
    _heartCtrl.forward(from: 0);
  }

  void _applyMode() {
    final mode = _repeatOne
        ? PlayMode.repeatOne
        : _shuffle
            ? PlayMode.shuffle
            : PlayMode.repeatAll;
    try {
      ref.read(audioHandlerProvider).setPlayMode(mode);
    } catch (_) {/* no handler in tests */}
  }

  void _goSearch() {
    HapticFeedback.selectionClick();
    ref.read(shellTabProvider.notifier).state = kHomePage;
    ref.read(homeSearchRequestProvider.notifier).state++;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _openUpNext() => Navigator.of(context).push(_SlideUpRoute());

  /// The song details drop down from the top.
  void _openInfo(Song song) {
    HapticFeedback.selectionClick();
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close details',
      barrierColor: NoorTheme.of(context).ac.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 340),
      pageBuilder: (_, __, ___) => Align(
        alignment: Alignment.topCenter,
        child: Material(
            color: Colors.transparent,
            child: _SongInfoSheet(song: song, onAddToPlaylist: _openList)),
      ),
      transitionBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
  }

  // ── Add-to-playlist panel control ─────────────────────────────────────────
  void _openList() {
    HapticFeedback.mediumImpact();
    setState(() => _panelState = _PanelState.list);
    _listPanelCtrl.forward();
  }

  Future<void> _closeList() async {
    HapticFeedback.lightImpact();
    await _listPanelCtrl.reverse();
    if (mounted) setState(() => _panelState = _PanelState.none);
  }

  void _openNaming() async {
    if (ref.read(playlistProvider.notifier).isFull) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('You can have up to $kMaxPlaylists playlists.'),
          behavior: SnackBarBehavior.floating));
      return;
    }
    HapticFeedback.selectionClick();
    _nameCtrl.clear();
    await _listPanelCtrl.reverse();
    if (!mounted) return;
    setState(() => _panelState = _PanelState.naming);
    _namePanelCtrl.forward(from: 0);
    Future.delayed(
        const Duration(milliseconds: 200), () => _nameFocus.requestFocus());
  }

  Future<void> _cancelNaming() async {
    HapticFeedback.lightImpact();
    _nameFocus.unfocus();
    await _namePanelCtrl.reverse();
    if (!mounted) return;
    setState(() => _panelState = _PanelState.list);
    _listPanelCtrl.forward(from: 0);
  }

  Future<void> _confirmNaming(Song song) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    if (ref.read(playlistProvider.notifier).nameTaken(name)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('A playlist with this name already exists.'),
          behavior: SnackBarBehavior.floating));
      return;
    }
    HapticFeedback.mediumImpact();
    _nameFocus.unfocus();
    final pl = await ref.read(playlistProvider.notifier).create(name);
    await ref.read(playlistProvider.notifier).addSong(pl.id, song);
    await _namePanelCtrl.reverse();
    if (!mounted) return;
    setState(() => _panelState = _PanelState.none);
    _nameCtrl.clear();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Created and added to ${pl.name} ✓'),
        behavior: SnackBarBehavior.floating));
  }

  Future<void> _closeAll() async {
    _nameFocus.unfocus();
    if (_panelState == _PanelState.naming) {
      await _namePanelCtrl.reverse();
    } else if (_panelState == _PanelState.list) {
      await _listPanelCtrl.reverse();
    }
    if (mounted) setState(() => _panelState = _PanelState.none);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ps = ref.watch(playerProvider);
    final song = ps.displaySong;
    final t = NoorTheme.of(context);
    final liked = song != null && ref.watch(isLikedProvider(song.videoId));
    final playlists = ref.watch(playlistProvider);
    final playing = ps.status == NebulaPlayerStatus.playing;
    final loading = ps.status == NebulaPlayerStatus.loading ||
        (ps.pendingSong != null &&
            ps.status != NebulaPlayerStatus.playing &&
            ps.status != NebulaPlayerStatus.paused);
    final isError = ps.status == NebulaPlayerStatus.error;
    final progress = ref.watch(playbackProgressProvider).valueOrNull ??
        PlaybackProgress.zero;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    final status = loading || _swapping
        ? 'Loading…'
        : isError
            ? (ps.cooldownSeconds > 0
                ? 'Retry in ${ps.cooldownSeconds}s…'
                : (ps.error ?? 'Could not play this song. Tap play to retry.'))
            : (song?.artist ?? '');

    return PopScope(
      canPop: _panelState == _PanelState.none,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeAll();
      },
      child: Scaffold(
        backgroundColor: t.bg,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -350) {
                  _openUpNext();
                } else if (v > 350 && song != null) {
                  _openInfo(song);
                }
              },
              child: Column(
                children: [
                  SizedBox(height: topPad + 14),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 14, 0),
                    child: SizedBox(
                      height: 44,
                      child: Row(children: [
                        const NoorWordmark(height: 30),
                        const Spacer(),
                        NoorSearchButton(open: false, onTap: _goSearch),
                      ]),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(builder: (context, box) {
                      final size = min(box.maxWidth - 48, box.maxHeight - 24)
                          .clamp(160.0, 420.0);
                      return Center(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: song == null ? null : () => _togglePlay(ps),
                          onDoubleTap: song == null
                              ? null
                              : () => _toggleLike(song, liked),
                          onHorizontalDragEnd: (d) {
                            final v = d.primaryVelocity ?? 0;
                            if (v < -250) _change(1);
                            if (v > 250) _change(-1);
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: _slide,
                                builder: (context, _) {
                                  final v = Curves.easeInOutCubic
                                      .transform(_slide.value);
                                  final shift = !_swapping
                                      ? 0.0
                                      : _inPhase
                                          ? -_outDir * (1 - v) * 1.25
                                          : _outDir * v * 1.25;
                                  return NoorTurntable(
                                    size: size,
                                    artUrl: _artOverride ??
                                        song?.thumbnailUrl ??
                                        '',
                                    spinning: playing && !loading && !_swapping,
                                    armDown: playing && !loading && !_swapping,
                                    discShift: shift,
                                  );
                                },
                              ),
                              _heartBurst(),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                  // Title and artist (or the loading / error line).
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(children: [
                      Text(song?.title ?? 'No song playing',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: noorSongTitleStyle(t.ac, size: 26)),
                      const SizedBox(height: 4),
                      Text(status,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: noorArtistStyle(t.mute, size: 13)),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  _Waveform(
                    progress: progress.fraction,
                    isDark: t.isDark,
                    playing: playing && !loading,
                    onSeek: (pct) {
                      final total = progress.duration.inSeconds;
                      if (total > 0) {
                        ref
                            .read(playerProvider.notifier)
                            .seek(Duration(seconds: (pct * total).round()));
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 26),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmt(progress.position),
                            style: TextStyle(
                                fontSize: 11,
                                color: t.mute,
                                fontWeight: FontWeight.w700)),
                        Text(_fmt(progress.duration),
                            style: TextStyle(
                                fontSize: 11,
                                color: t.mute,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _RingButton(
                          icon: Icons.shuffle_rounded,
                          label: 'Shuffle',
                          on: _shuffle,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _shuffle = !_shuffle);
                            _applyMode();
                          },
                        ),
                        _RingButton(
                          icon: Icons.skip_previous_rounded,
                          label: 'Previous',
                          onTap: () => _change(-1),
                        ),
                        NoorPlayPauseButton(
                          size: 64,
                          playing: playing,
                          loading: loading || _swapping,
                          onTap: song == null ? null : () => _togglePlay(ps),
                        ),
                        _RingButton(
                          icon: Icons.skip_next_rounded,
                          label: 'Next',
                          onTap: () => _change(1),
                        ),
                        _RingButton(
                          icon: Icons.repeat_one_rounded,
                          label: 'Repeat this song',
                          on: _repeatOne,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _repeatOne = !_repeatOne);
                            _applyMode();
                          },
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: bottomPad + 28),
                ],
              ),
            ),

            // ── Scrim ────────────────────────────────────────────────────────
            if (_panelState != _PanelState.none)
              AnimatedBuilder(
                animation: _panelState == _PanelState.naming
                    ? _namePanelCtrl
                    : _listPanelCtrl,
                builder: (_, __) => GestureDetector(
                  onTap: _closeAll,
                  child: Container(
                    color: t.ac.withOpacity(0.55 *
                        (_panelState == _PanelState.naming
                            ? _nameFade.value
                            : _listFade.value)),
                  ),
                ),
              ),

            // ── List Panel (slides from right) ───────────────────────────────
            if (_panelState == _PanelState.list || _listPanelCtrl.isAnimating)
              SlideTransition(
                position: _listSlide,
                child: FadeTransition(
                  opacity: _listFade,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _AddToPlaylistPanel(
                      isDark: t.isDark,
                      bg: t.bg,
                      cardBg: t.bg,
                      textCol: t.ac,
                      mutedCol: t.mute,
                      accentCol: t.ac,
                      playlists: playlists,
                      song: song,
                      onClose: _closeList,
                      onAdd: _openNaming,
                      onTapPlaylist: (pl) async {
                        if (song == null) return;
                        HapticFeedback.selectionClick();
                        await ref
                            .read(playlistProvider.notifier)
                            .addSong(pl.id, song);
                        _closeList();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Added to ${pl.name} ✓'),
                              behavior: SnackBarBehavior.floating));
                        }
                      },
                    ),
                  ),
                ),
              ),

            // ── Name Panel (slides from left) ────────────────────────────────
            if (_panelState == _PanelState.naming || _namePanelCtrl.isAnimating)
              SlideTransition(
                position: _nameSlide,
                child: FadeTransition(
                  opacity: _nameFade,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _NamingPanel(
                      isDark: t.isDark,
                      bg: t.bg,
                      cardBg: t.bg,
                      textCol: t.ac,
                      mutedCol: t.mute,
                      accentCol: t.ac,
                      controller: _nameCtrl,
                      focusNode: _nameFocus,
                      onCancel: _cancelNaming,
                      onConfirm: () {
                        if (song != null) _confirmNaming(song);
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Heart shown over the turntable on double tap: an empty heart turns red
  /// when liking, a red heart turns empty when unliking.
  Widget _heartBurst() => IgnorePointer(
        child: AnimatedBuilder(
          animation: _heartCtrl,
          builder: (context, _) {
            final v = _heartCtrl.value;
            if (v == 0 || v == 1) return const SizedBox.shrink();
            final mix =
                Curves.easeInOut.transform(((v - 0.25) / 0.3).clamp(0.0, 1.0));
            final fill = _heartBecomingLiked ? mix : 1 - mix;
            final scale = 0.4 +
                0.8 * Curves.easeOutBack.transform((v / 0.3).clamp(0.0, 1.0));
            final opacity =
                v < 0.7 ? 1.0 : (1 - (v - 0.7) / 0.3).clamp(0.0, 1.0);
            return Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: Icon(Icons.favorite_rounded,
                    size: 84,
                    color:
                        Color.lerp(Colors.white, const Color(0xFFE5393F), fill),
                    shadows: const [
                      Shadow(color: Colors.black38, blurRadius: 18)
                    ]),
              ),
            );
          },
        ),
      );

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// A round control in a thin ring; [on] fills it (for shuffle / repeat).
class _RingButton extends StatelessWidget {
  const _RingButton(
      {required this.icon, required this.label, required this.onTap, this.on});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// null: a plain button; true / false: a toggle.
  final bool? on;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    final filled = on ?? false;
    return Semantics(
      button: true,
      label: label,
      toggled: on,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? t.ac : t.bg,
            border: Border.all(color: t.ac, width: 0.8),
          ),
          child: Icon(icon, size: 22, color: filled ? t.bg : t.ac),
        ),
      ),
    );
  }
}

class _AddToPlaylistPanel extends ConsumerWidget {
  final bool isDark;
  final Color bg, cardBg, textCol, mutedCol, accentCol;
  final List<Playlist> playlists;
  final Song? song;
  final VoidCallback onClose, onAdd;
  final void Function(Playlist) onTapPlaylist;

  const _AddToPlaylistPanel({
    required this.isDark,
    required this.bg,
    required this.cardBg,
    required this.textCol,
    required this.mutedCol,
    required this.accentCol,
    required this.playlists,
    required this.song,
    required this.onClose,
    required this.onAdd,
    required this.onTapPlaylist,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = MediaQuery.of(context).size.width * 0.82;
    final h = MediaQuery.of(context).size.height;
    final topPad = MediaQuery.of(context).padding.top;

    return Container(
      width: w,
      height: h,
      padding: EdgeInsets.only(top: topPad + 16, bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          bottomLeft: Radius.circular(28),
        ),
        border: Border.all(color: NoorTheme.byMode(isDark).soft, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
            child: Row(
              children: [
                _NeuBtn(
                  icon: Icons.close_rounded,
                  color: mutedCol,
                  bg: NoorTheme.byMode(isDark).bg,
                  isDark: isDark,
                  size: 44,
                  onTap: onClose,
                ),
                const SizedBox(width: 14),
                Text(
                  'Add to Playlist',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: textCol,
                    letterSpacing: -0.4,
                  ),
                ),
                const Spacer(),
                _NeuBtn(
                  icon: Icons.add_rounded,
                  color: accentCol,
                  bg: NoorTheme.byMode(isDark).bg,
                  isDark: isDark,
                  size: 44,
                  onTap: onAdd,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _NeuDivider(isDark: isDark),
          ),
          const SizedBox(height: 8),
          if (playlists.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NeuIconBox(
                      icon: Icons.queue_music_rounded,
                      isDark: isDark,
                      bg: NoorTheme.byMode(isDark).bg,
                      color: accentCol,
                      size: 72,
                    ),
                    const SizedBox(height: 16),
                    Text('No playlists yet',
                        style: TextStyle(
                            color: mutedCol,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('Tap + to create one',
                        style: TextStyle(
                            color: mutedCol.withOpacity(0.6), fontSize: 12)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                physics: const BouncingScrollPhysics(),
                itemCount: playlists.length,
                itemBuilder: (_, i) {
                  final pl = playlists[i];
                  final hasIt = song != null &&
                      ref
                          .read(playlistProvider.notifier)
                          .contains(pl.id, song!.videoId);
                  return GestureDetector(
                    onTap: hasIt ? null : () => onTapPlaylist(pl),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: NoorTheme.byMode(isDark).soft, width: 1),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accentCol.withOpacity(0.12),
                              border: Border.all(
                                  color: NoorTheme.byMode(isDark).soft,
                                  width: 1),
                            ),
                            child: Icon(Icons.queue_music_rounded,
                                color: accentCol, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(pl.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: textCol,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15)),
                                Text('${pl.songs.length} songs',
                                    style: TextStyle(
                                        color: mutedCol, fontSize: 12)),
                              ],
                            ),
                          ),
                          if (hasIt)
                            Icon(Icons.check_circle_rounded,
                                color: accentCol, size: 28),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NAMING PANEL — slides in from left
// ═══════════════════════════════════════════════════════════════════════════════
class _NamingPanel extends StatelessWidget {
  final bool isDark;
  final Color bg, cardBg, textCol, mutedCol, accentCol;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCancel, onConfirm;

  const _NamingPanel({
    required this.isDark,
    required this.bg,
    required this.cardBg,
    required this.textCol,
    required this.mutedCol,
    required this.accentCol,
    required this.controller,
    required this.focusNode,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width * 0.82;
    final h = MediaQuery.of(context).size.height;
    final topPad = MediaQuery.of(context).padding.top;

    return Container(
      width: w,
      height: h,
      padding:
          EdgeInsets.only(top: topPad + 16, bottom: 32, left: 20, right: 20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        border: Border.all(color: NoorTheme.byMode(isDark).soft, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _NeuBtn(
                icon: Icons.arrow_back_rounded,
                color: mutedCol,
                bg: NoorTheme.byMode(isDark).bg,
                isDark: isDark,
                size: 44,
                onTap: onCancel,
              ),
              const SizedBox(width: 14),
              Text(
                'New Playlist',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: textCol,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Center(
            child: _NeuIconBox(
              icon: Icons.album_rounded,
              isDark: isDark,
              bg: NoorTheme.byMode(isDark).bg,
              color: accentCol,
              size: 88,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Give it a name',
            style: TextStyle(
              color: mutedCol,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: NoorTheme.byMode(isDark).bg,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: NoorTheme.byMode(isDark).soft, width: 1),
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: TextStyle(
                  color: textCol, fontWeight: FontWeight.w700, fontSize: 16),
              cursorColor: accentCol,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onConfirm(),
              decoration: InputDecoration(
                hintText: 'Playlist name…',
                hintStyle:
                    TextStyle(color: mutedCol.withOpacity(0.5), fontSize: 15),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                suffixIcon: Icon(Icons.edit_rounded,
                    color: accentCol.withOpacity(0.5), size: 18),
              ),
            ),
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: onConfirm,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: accentCol,
                borderRadius: BorderRadius.circular(18),
                border:
                    Border.all(color: NoorTheme.byMode(isDark).soft, width: 1),
              ),
              child: const Center(
                child: Text(
                  'Create & Add Song',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onCancel,
            child: Center(
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: mutedCol,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared Neumorphic Components ─────────────────────────────────────────────

/// Where the volume arc starts (bottom-left) and how far it sweeps.
/// The progress line: thick short bars of uneven height, each reaching a
/// different distance above and below the middle. Played bars are solid;
/// tap or drag to seek.
class _Waveform extends StatefulWidget {
  final double progress;
  final bool isDark;
  final bool playing;
  final ValueChanged<double> onSeek;
  const _Waveform(
      {required this.progress,
      required this.isDark,
      required this.playing,
      required this.onSeek});

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _anim.repeat();
  }

  @override
  void didUpdateWidget(covariant _Waveform old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_anim.isAnimating) {
      _anim.repeat();
    } else if (!widget.playing && _anim.isAnimating) {
      _anim.stop();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _seek(double dx, double width) =>
      widget.onSeek((dx / width).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.byMode(widget.isDark);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: LayoutBuilder(
        builder: (context, box) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _seek(d.localPosition.dx, box.maxWidth),
          onHorizontalDragUpdate: (d) =>
              _seek(d.localPosition.dx, box.maxWidth),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) => CustomPaint(
                painter: _WavePainter(
                  progress: widget.progress,
                  phase: _anim.value,
                  playing: widget.playing,
                  active: t.ac,
                  idle: t.ac.withOpacity(0.22),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.progress,
    required this.phase,
    required this.playing,
    required this.active,
    required this.idle,
  });

  final double progress;
  final double phase;
  final bool playing;
  final Color active;
  final Color idle;

  static const int barCount = 34;
  // Fixed random reach above and below the middle (0.2 .. 1.0), so the
  // shape is the same every time but uneven on both sides.
  static final List<double> _up = List<double>.generate(
      barCount, (i) => 0.2 + 0.8 * Random(i * 7 + 3).nextDouble());
  static final List<double> _down = List<double>.generate(
      barCount, (i) => 0.2 + 0.8 * Random(i * 13 + 11).nextDouble());

  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / barCount;
    final barW = max(4.0, slot * 0.6);
    final midY = size.height / 2;
    final maxHalf = size.height / 2 - 1;
    final cur = (progress * barCount).clamp(0.0, barCount.toDouble());
    for (var i = 0; i < barCount; i++) {
      final breathe =
          playing ? 0.82 + 0.18 * sin(2 * pi * (phase + i * 0.083)) : 1.0;
      final up = max(3.0, _up[i] * breathe * maxHalf);
      final down = max(3.0, _down[i] * breathe * maxHalf);
      final x = slot * i + slot / 2;
      final r = RRect.fromRectAndRadius(
          Rect.fromLTRB(x - barW / 2, midY - up, x + barW / 2, midY + down),
          Radius.circular(barW / 2));
      canvas.drawRRect(r, Paint()..color = i + 0.5 <= cur ? active : idle);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress ||
      old.phase != phase ||
      old.playing != playing ||
      old.active != active;
}

class _NeuBtn extends StatelessWidget {
  final IconData icon;
  final Color color, bg;
  final bool isDark;
  final VoidCallback onTap;
  final double size;
  const _NeuBtn({
    required this.icon,
    required this.color,
    required this.bg,
    required this.isDark,
    required this.onTap,
    required this.size,
  });
  @override
  Widget build(BuildContext context) => NoorRoundButton(
        size: size,
        onTap: onTap,
        child: Icon(icon, color: color),
      );
}

class _NeuIconBox extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final Color bg, color;
  final double size;

  const _NeuIconBox({
    required this.icon,
    required this.isDark,
    required this.bg,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) => NoorRoundButton(
        size: size,
        child: Icon(icon, color: color),
      );
}

class _NeuDivider extends StatelessWidget {
  final bool isDark;
  const _NeuDivider({required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            Colors.transparent,
            NoorTheme.byMode(isDark).ac.withOpacity(0.18),
            Colors.transparent,
          ]),
        ),
      );
}

/// "About this song": everything YouTube tells us, in a bottom sheet.
class _SongInfoSheet extends ConsumerWidget {
  const _SongInfoSheet({required this.song, this.onAddToPlaylist});
  final Song song;

  /// Closes the sheet and opens the add-to-playlist panel.
  final VoidCallback? onAddToPlaylist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = NoorTheme.of(context);
    final details = ref.watch(songDetailsProvider(song.videoId));
    final d = details.valueOrNull;
    final h = MediaQuery.of(context).size.height;

    Widget row(String label, String? value) {
      if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 96,
                child: Text(label,
                    style: TextStyle(
                        color: t.mute,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3))),
            Expanded(
                child: Text(value,
                    style: TextStyle(
                        color: t.ac,
                        fontSize: 14,
                        fontWeight: FontWeight.w600))),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: h * 0.80),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        border: Border.all(color: t.soft, width: 1),
      ),
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 16, 20, 8),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          Text(song.title, style: noorSerif(t.ac, size: 28, height: 1.05)),
          const SizedBox(height: 12),
          if (details.isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child:
                      CircularProgressIndicator(color: t.ac, strokeWidth: 2)),
            )
          else if (d == null) ...[
            row('Channel', song.artist),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  'More details could not be loaded right now (no connection or YouTube is busy).',
                  style: TextStyle(color: t.mute, fontSize: 13)),
            ),
          ] else ...[
            row('Channel', d.channel),
            row(
                'Published',
                d.published == null
                    ? null
                    : SongDetails.monthYear(d.published!)),
            row('Views',
                d.views == null ? null : SongDetails.compactCount(d.views!)),
            row('Likes',
                d.likes == null ? null : SongDetails.compactCount(d.likes!)),
            row(
                'Length',
                (d.duration == null || d.duration == Duration.zero)
                    ? null
                    : SongDetails.clock(d.duration!)),
            if (d.hasMusicTags) ...[
              const SizedBox(height: 6),
              Divider(color: t.faint, height: 1),
              const SizedBox(height: 6),
              row('Song', d.songName),
              row('Artist', d.artistName),
              row('Album', d.albumName),
            ],
            if (d.keywords.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in d.keywords.take(10))
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: t.soft, width: 1),
                      ),
                      child: Text(k,
                          style: TextStyle(color: t.mute, fontSize: 12)),
                    ),
                ],
              ),
            ],
            if (d.description.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('ABOUT',
                  style: TextStyle(
                      color: t.mute,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2)),
              const SizedBox(height: 6),
              SelectableText(d.description.trim(),
                  maxLines: 14,
                  style: TextStyle(color: t.ac, fontSize: 13, height: 1.4)),
            ],
          ],
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              GestureDetector(
                onTap: () => launchUrl(
                    Uri.parse(
                        'https://www.youtube.com/watch?v=${song.videoId}'),
                    mode: LaunchMode.externalApplication),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: t.ac, width: 1),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.open_in_new_rounded, size: 16, color: t.ac),
                    const SizedBox(width: 8),
                    Text('Open on YouTube',
                        style: TextStyle(
                            color: t.ac,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ]),
                ),
              ),
              if (onAddToPlaylist != null)
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    onAddToPlaylist!();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: t.ac, width: 1),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.playlist_add_rounded, size: 16, color: t.ac),
                      const SizedBox(width: 8),
                      Text('Add to playlist',
                          style: TextStyle(
                              color: t.ac,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ]),
                  ),
                ),
            ],
          ),
          // Grab handle at the bottom edge: tap or swipe up to close.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < -150) Navigator.of(context).pop();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                        color: t.soft, borderRadius: BorderRadius.circular(2))),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
