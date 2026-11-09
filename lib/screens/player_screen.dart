import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart'; 
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_widgets.dart';
import '../theme/noor_disc.dart';
import '../services/song_details.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/audio_handler.dart';
import 'upnext_screen.dart';

// ── Panel visibility state ────────────────────────────────────────────────────
enum _PanelState { none, list, naming }

class _SlideUpRoute extends PageRouteBuilder {
  _SlideUpRoute()
      : super(
          opaque: false,
          barrierDismissible: false,
          pageBuilder: (_, __, ___) => const UpNextScreen(),
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 320),
          transitionsBuilder: (_, anim, __, child) {
            final curved = CurvedAnimation(
                parent: anim,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic);
            return SlideTransition(
              position: Tween<Offset>(
                      begin: const Offset(0, 1), end: Offset.zero)
                  .animate(curved),
              child: child,
            );
          },
        );
}

void _openUpNext(BuildContext context) =>
    Navigator.of(context).push(_SlideUpRoute());

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with TickerProviderStateMixin {
  late AnimationController _rotationCtrl;
  late AnimationController _heartCtrl;
  late AnimationController _playPauseCtrl;

  late Animation<double> _heartScale;
  late Animation<double> _heartOpacity;
  late Animation<double> _playPauseScale;
  late Animation<double> _playPauseOpacity;

  bool _isBrokenHeart = false;
  bool _showingPlayIcon = false;

  int _playModeIndex = 0;
  final ValueNotifier<double> _volume = ValueNotifier<double>(0.5);
  Timer? _volTimer;
  double? _pendingVol;
  DateTime _lastVol = DateTime.fromMillisecondsSinceEpoch(0);

  // ── Playlist Panel Animations ───────────────────────────────────────────────
  _PanelState _panelState = _PanelState.none;
  late AnimationController _listPanelCtrl;
  late AnimationController _namePanelCtrl;
  late Animation<Offset> _listSlide;
  late Animation<Offset> _nameSlide;
  late Animation<double> _listFade;
  late Animation<double> _nameFade;
  late Animation<double> _scrimOpacity;

  final TextEditingController _nameCtrl = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _rotationCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 15));
    _heartCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _heartScale = Tween<double>(begin: 0.5, end: 1.3).animate(
        CurvedAnimation(parent: _heartCtrl, curve: Curves.elasticOut));
    _heartOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _heartCtrl, curve: Curves.easeOut));
    _playPauseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _playPauseScale = Tween<double>(begin: 0.5, end: 1.3).animate(
        CurvedAnimation(parent: _playPauseCtrl, curve: Curves.easeOutBack));
    _playPauseOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _playPauseCtrl, curve: Curves.easeOut));

    // Panel Controllers
    _listPanelCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _namePanelCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 340));

    _listSlide = Tween<Offset>(begin: const Offset(1.0, 0), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _listPanelCtrl,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic));

    _nameSlide = Tween<Offset>(begin: const Offset(-1.0, 0), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _namePanelCtrl,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic));

    _listFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _listPanelCtrl, curve: Curves.easeOut));
    _nameFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _namePanelCtrl, curve: Curves.easeOut));

    _scrimOpacity = Tween<double>(begin: 0.0, end: 0.55).animate(
        CurvedAnimation(parent: _listPanelCtrl, curve: Curves.easeOut));

    FlutterVolumeController.updateShowSystemUI(false); 

    FlutterVolumeController.addListener((volume) {
      if (mounted) {
        _volume.value = volume;
        ref.read(playerProvider.notifier).setVolume(volume);
      }
    });

    FlutterVolumeController.getVolume().then((volume) {
      if (mounted && volume != null) _volume.value = volume;
    });
  }

  @override
  void dispose() {
    _volTimer?.cancel();
    _volume.dispose();
    FlutterVolumeController.removeListener();
    _rotationCtrl.dispose();
    _heartCtrl.dispose();
    _playPauseCtrl.dispose();
    _listPanelCtrl.dispose();
    _namePanelCtrl.dispose();
    _nameCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // ── Panel Control Methods ──────────────────────────────────────────────────
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
    HapticFeedback.selectionClick();
    _nameCtrl.clear();
    await _listPanelCtrl.reverse();
    if (!mounted) return;
    setState(() => _panelState = _PanelState.naming);
    _namePanelCtrl.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 200),
        () => _nameFocus.requestFocus());
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

  // ── Standard Player Methods ────────────────────────────────────────────────

  void _handleTap(Song song, bool isPlaying) {
    setState(() => _showingPlayIcon = !isPlaying);
    ref.read(playerProvider.notifier).togglePlay();
    _playPauseCtrl.forward(from: 0.0).then((_) {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 400),
            () => _playPauseCtrl.reverse());
      }
    });
  }

  void _handleDoubleTap(Song song, bool isCurrentlyLiked) {
    setState(() => _isBrokenHeart = isCurrentlyLiked);
    ref.read(likedProvider.notifier).toggle(song);
    _heartCtrl.forward(from: 0.0).then((_) {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 600),
            () => _heartCtrl.reverse());
      }
    });
  }

  void _cyclePlayMode() {
    final next = (_playModeIndex + 1) % 4;
    setState(() => _playModeIndex = next);

    const modes = [
      PlayMode.sequential,
      PlayMode.repeatAll,
      PlayMode.repeatOne,
      PlayMode.shuffle,
    ];
    ref.read(audioHandlerProvider).setPlayMode(modes[next]);
  }

  /// Called by the volume ring on every touch move. The ring repaints at once;
  /// the (slower) system call is limited to about 25 per second.
  void _setVolume(double v) {
    v = v.clamp(0.0, 1.0);
    _volume.value = v;
    _pendingVol = v;
    final since = DateTime.now().difference(_lastVol);
    if (since >= const Duration(milliseconds: 40)) {
      _flushVolume();
    } else {
      _volTimer ??= Timer(const Duration(milliseconds: 40), _flushVolume);
    }
  }

  void _flushVolume() {
    _volTimer?.cancel();
    _volTimer = null;
    final v = _pendingVol;
    if (v == null) return;
    _pendingVol = null;
    _lastVol = DateTime.now();
    try {
      FlutterVolumeController.setVolume(v);
    } catch (_) {/* the in-app volume below still changes */}
    ref.read(playerProvider.notifier).setVolume(v);
  }

  @override
  Widget build(BuildContext context) {
    final ps = ref.watch(playerProvider);
    final song = ps.song;
    final liked =
        song != null ? ref.watch(isLikedProvider(song.videoId)) : false;
    final playlists = ref.watch(playlistProvider);
    final details = song == null
        ? const AsyncValue<SongDetails?>.data(null)
        : ref.watch(songDetailsProvider(song.videoId));

    final playing = ps.status == NebulaPlayerStatus.playing;
    
    // UPDATED LOADING LOGIC: include pending state
    final loading = ps.status == NebulaPlayerStatus.loading ||
        (ps.pendingSong != null &&
            ps.status != NebulaPlayerStatus.playing &&
            ps.status != NebulaPlayerStatus.paused);
            
    final progress =
        ref.watch(playbackProgressProvider).valueOrNull ?? PlaybackProgress.zero;
    final prog = progress.fraction;

    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final t = NoorTheme.byMode(isDark);
    final bg = t.bg;
    final cardBg = t.bg;
    final textCol = t.ac;
    final mutedCol = t.mute;
    final accentCol = t.ac;

    final h = MediaQuery.of(context).size.height;
    final topPad = MediaQuery.of(context).padding.top;

    if (playing && !loading) {
      if (!_rotationCtrl.isAnimating) _rotationCtrl.repeat();
    } else {
      if (_rotationCtrl.isAnimating) _rotationCtrl.stop();
    }

    final bool isNeedleOnRecord = playing && !loading;
    final double diskSize = h * 0.315; 
    final double volumeRingSize = diskSize + 56.0;
    final double needleWidth = 110.0;
    final double needleHeight = h * 0.26 + 28;

    return PopScope(
      canPop: _panelState == _PanelState.none,
      onPopInvoked: (didPop) {
        if (!didPop) {
          _closeAll();
        }
      },
      child: Scaffold(
        backgroundColor: bg,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // ── Main Player UI ──────────────────────────────────────────────────
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -400) {
                  _openUpNext(context);
                } else if (v > 400 && _panelState == _PanelState.none) {
                  Navigator.pop(context);
                }
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    flex: 10,
                    child: Container(
                      padding: const EdgeInsets.only(top: 96),
                      child: LayoutBuilder(builder: (context, box) {
                        // The ring needs 112 px more than the record; shrink the
                        // record on short screens instead of letting it overflow.
                        final disc = max(120.0, min(diskSize, box.maxHeight - 112));
                        final ring = disc + 112;
                        return Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            _VolumeRing(
                              size: ring,
                              volume: _volume,
                              isDark: isDark,
                              onChanged: _setVolume,
                            ),

                            GestureDetector(
                              onTap: song != null && !loading
                                  ? () => _handleTap(song, playing)
                                  : null,
                              onDoubleTap: song != null && !loading
                                  ? () => _handleDoubleTap(song, liked)
                                  : null,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  RotationTransition(
                                    turns: _rotationCtrl,
                                    child: _buildVinylRecord(
                                        disc, bg, song, isDark),
                                  ),
                                  if (loading)
                                    Container(
                                      width: disc,
                                      height: disc,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: NoorTheme.byMode(isDark).ac.withOpacity(0.45),
                                      ),
                                      child: Center(
                                        child: SizedBox(
                                          width: 44,
                                          height: 44,
                                          child: CircularProgressIndicator(
                                            color: NoorTheme.byMode(isDark).bg,
                                            strokeWidth: 3,
                                          ),
                                        ),
                                      ),
                                    ),
                                  _buildOverlayAnimations(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                      }),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSongInfo(song, details, textCol, mutedCol),
                        const SizedBox(height: 14),
                        _Waveform(
                          progress: prog,
                          isDark: isDark,
                          playing: playing && !loading,
                          onSeek: (pct) {
                            final total = progress.duration.inSeconds;
                            if (total > 0) {
                              ref.read(playerProvider.notifier).seek(Duration(
                                  seconds: (pct * total).round()));
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 28),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_fmt(progress.position),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: mutedCol,
                                      fontWeight: FontWeight.w700)),
                              Text(_fmt(progress.duration),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: mutedCol,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildTransportRow(
                            textCol, bg, isDark, song, mutedCol),
                        const SizedBox(height: 16),
                        _buildUpNextDragHandle(mutedCol),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              top: topPad + 10,
              left: 20,
              child: Tooltip(
                message: 'Add to playlist',
                child: _NeuBtn(
                  icon: Icons.playlist_add_rounded,
                  color: accentCol,
                  bg: bg,
                  isDark: isDark,
                  size: 52,
                  onTap: () {
                    if (song != null) _openList();
                  },
                ),
              ),
            ),
            Positioned(
              top: topPad - 14,
              right: 20,
              child: AnimatedRotation(
                turns: isNeedleOnRecord ? 0.0 : 0.18,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutBack,
                alignment: FractionalOffset(
                    (needleWidth - 28.0) / needleWidth,
                    _kPivotY / needleHeight),
                child:
                    _buildNeedleRight(isDark, needleWidth, needleHeight),
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
                    color: NoorTheme.byMode(isDark).ac.withOpacity(
                        _panelState == _PanelState.naming
                            ? (_nameFade.value * 0.55)
                            : _scrimOpacity.value),
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
                      isDark: isDark,
                      bg: bg,
                      cardBg: cardBg,
                      textCol: textCol,
                      mutedCol: mutedCol,
                      accentCol: accentCol,
                      playlists: playlists,
                      song: song,
                      onClose: _closeList,
                      onAdd: _openNaming,
                      onTapPlaylist: (pl) async {
                        if (song != null) {
                          HapticFeedback.selectionClick();
                          await ref.read(playlistProvider.notifier).addSong(pl.id, song);
                          _closeList();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Added to ${pl.name} ✓'),
                                behavior: SnackBarBehavior.floating));
                          }
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
                      isDark: isDark,
                      bg: bg,
                      cardBg: cardBg,
                      textCol: textCol,
                      mutedCol: mutedCol,
                      accentCol: accentCol,
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

  Widget _buildOverlayAnimations() => Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
              animation: _heartCtrl,
              builder: (context, child) => Opacity(
                  opacity: _heartOpacity.value,
                  child: Transform.scale(
                      scale: _heartScale.value,
                      child: Icon(
                          _isBrokenHeart
                              ? Icons.heart_broken_rounded
                              : Icons.favorite_rounded,
                          color: Colors.white,
                          size: 80,
                          shadows: const [
                            Shadow(
                                color: Colors.black45, blurRadius: 20)
                          ])))),
          AnimatedBuilder(
              animation: _playPauseCtrl,
              builder: (context, child) => Opacity(
                  opacity: _playPauseOpacity.value,
                  child: Transform.scale(
                      scale: _playPauseScale.value,
                      child: Icon(
                          _showingPlayIcon
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          color: Colors.white,
                          size: 80,
                          shadows: const [
                            Shadow(
                                color: Colors.black45, blurRadius: 20)
                          ])))),
        ],
      );

  Widget _buildSongInfo(Song? song, AsyncValue<SongDetails?> details,
      Color textCol, Color mutedCol) {
    final d = details.valueOrNull;
    final meta = d?.metaLine ?? '';
    final channel = (d?.channel.isNotEmpty ?? false)
        ? d!.channel
        : (song?.artist ?? '');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(children: [
        Text(song?.title ?? 'No song selected',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: noorSerif(textCol, size: 28, height: 1.05)),
        const SizedBox(height: 6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: song == null ? null : () => _openInfo(song),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(channel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textCol)),
              ),
              if (song != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.info_outline_rounded, size: 16, color: mutedCol),
              ],
            ],
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 16,
          child: Text(meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: mutedCol)),
        ),
      ]),
    );
  }

  void _openInfo(Song song) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SongInfoSheet(song: song),
    );
  }

  Widget _buildTransportRow(Color textCol, Color bg, bool isDark,
      Song? song, Color mutedCol) {
    final accentCol = NoorTheme.byMode(isDark).ac;
    final IconData modeIcon;
    final String modeLabel;

    switch (_playModeIndex) {
      case 0:
        modeIcon = Icons.arrow_forward_rounded;
        modeLabel = 'Play in order';
        break;
      case 1:
        modeIcon = Icons.repeat_rounded;
        modeLabel = 'Repeat all';
        break;
      case 2:
        modeIcon = Icons.repeat_one_rounded;
        modeLabel = 'Repeat one';
        break;
      default:
        modeIcon = Icons.shuffle_rounded;
        modeLabel = 'Shuffle';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Tooltip(
            message: 'Previous',
            child: _NeuBtn(
              icon: Icons.skip_previous_rounded,
              color: accentCol,
              bg: bg,
              isDark: isDark,
              size: 56,
              onTap: () => ref.read(playerProvider.notifier).skipPrevious(),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: modeLabel,
                child: NoorRoundButton(
                  size: 64,
                  filled: _playModeIndex != 0,
                  onTap: _cyclePlayMode,
                  semanticLabel: modeLabel,
                  child: Icon(modeIcon),
                ),
              ),
              const SizedBox(height: 4),
              Text(modeLabel,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: mutedCol)),
            ],
          ),
          Tooltip(
            message: 'Next',
            child: _NeuBtn(
              icon: Icons.skip_next_rounded,
              color: accentCol,
              bg: bg,
              isDark: isDark,
              size: 56,
              onTap: () => ref.read(playerProvider.notifier).skipNext(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpNextDragHandle(Color mutedCol) => GestureDetector(
      onTap: () => _openUpNext(context),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.keyboard_arrow_up_rounded,
            color: mutedCol.withOpacity(0.5), size: 20),
        const SizedBox(height: 2),
        Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: mutedCol.withOpacity(0.35),
                borderRadius: BorderRadius.circular(2)))
      ]));

  Widget _buildVinylRecord(
      double size, Color bg, Song? song, bool isDark) {
    final t = NoorTheme.byMode(isDark);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: t.faint, width: 1),
      ),
      child: NoorDisc(url: song?.thumbnailUrl ?? '', size: size),
    );
  }

  /// A tonearm: round pivot base, counterweight, a straight tube that bends
  /// into the headshell, a cartridge and the stylus. It swings about the pivot
  /// (see the AnimatedRotation around it).
  Widget _buildNeedleRight(bool isDark, double width, double height) {
    final t = NoorTheme.byMode(isDark);
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _TonearmPainter(t.ac, t.bg)),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ADD TO PLAYLIST PANEL — slides in from right
// ═══════════════════════════════════════════════════════════════════════════════
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
                  final hasIt = song != null && ref.read(playlistProvider.notifier).contains(pl.id, song!.videoId);
                  return GestureDetector(
                    onTap: hasIt ? null : () => onTapPlaylist(pl),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: NoorTheme.byMode(isDark).soft, width: 1),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accentCol.withOpacity(0.12),
                              border: Border.all(color: NoorTheme.byMode(isDark).soft, width: 1),
                            ),
                            child: Icon(Icons.queue_music_rounded, color: accentCol, size: 22),
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
                                    style: TextStyle(color: mutedCol, fontSize: 12)),
                              ],
                            ),
                          ),
                          if (hasIt)
                            Icon(Icons.check_circle_rounded, color: accentCol, size: 28),
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
      padding: EdgeInsets.only(top: topPad + 16, bottom: 32, left: 20, right: 20),
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
              border: Border.all(color: NoorTheme.byMode(isDark).soft, width: 1),
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: TextStyle(color: textCol, fontWeight: FontWeight.w700, fontSize: 16),
              cursorColor: accentCol,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onConfirm(),
              decoration: InputDecoration(
                hintText: 'Playlist name…',
                hintStyle: TextStyle(color: mutedCol.withOpacity(0.5), fontSize: 15),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                suffixIcon: Icon(Icons.edit_rounded, color: accentCol.withOpacity(0.5), size: 18),
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
                border: Border.all(color: NoorTheme.byMode(isDark).soft, width: 1),
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
const double _kVolStart = pi * 0.75;
const double _kVolSweep = pi * 1.5;

/// Maps a touch at [p] on a ring centred at [c] to a volume 0..1.
/// The arc runs clockwise from bottom-left over the top to bottom-right.
/// A touch in the open gap at the bottom snaps to the nearer end.
@visibleForTesting
double volumeFromRingPoint(Offset p, Offset c) {
  var a = atan2(p.dy - c.dy, p.dx - c.dx);
  if (a < 0) a += 2 * pi;
  var rel = a - _kVolStart;
  if (rel < 0) rel += 2 * pi;
  if (rel <= _kVolSweep) return rel / _kVolSweep;
  final gap = rel - _kVolSweep; // 0 .. pi/2
  return gap < pi * 0.25 ? 1.0 : 0.0;
}

/// The volume ring around the record. Touch anywhere in its square (outside
/// the record, which sits on top) and drag; the arc follows your finger.
class _VolumeRing extends StatefulWidget {
  const _VolumeRing({
    required this.size,
    required this.volume,
    required this.isDark,
    required this.onChanged,
  });

  final double size;
  final ValueNotifier<double> volume;
  final bool isDark;
  final ValueChanged<double> onChanged;

  @override
  State<_VolumeRing> createState() => _VolumeRingState();
}

class _VolumeRingState extends State<_VolumeRing> {
  bool _dragging = false;

  void _touch(Offset local) {
    widget.onChanged(volumeFromRingPoint(
        local, Offset(widget.size / 2, widget.size / 2)));
  }

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.byMode(widget.isDark);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) {
        HapticFeedback.selectionClick();
        _touch(d.localPosition);
      },
      onPanStart: (d) {
        setState(() => _dragging = true);
        _touch(d.localPosition);
      },
      onPanUpdate: (d) => _touch(d.localPosition),
      onPanEnd: (_) => setState(() => _dragging = false),
      onPanCancel: () => setState(() => _dragging = false),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: ValueListenableBuilder<double>(
          valueListenable: widget.volume,
          builder: (context, v, _) => Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _VolumeArcPainter(volume: v, isDark: widget.isDark),
              ),
              // The percentage floats at the bottom gap while you adjust.
              Positioned(
                bottom: 2,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _dragging ? 1 : 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: t.ac,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${(v * 100).round()}%',
                        style: TextStyle(
                            color: t.onAc,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VolumeArcPainter extends CustomPainter {
  final double volume;
  final bool isDark;

  _VolumeArcPainter({required this.volume, required this.isDark});

  void _drawMaterialIcon(Canvas canvas, Offset offset, IconData icon,
      Color color, double size) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          color: color,
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      offset.translate(-textPainter.width / 2, -textPainter.height / 2),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = NoorTheme.byMode(isDark);
    final center = Offset(size.width / 2, size.height / 2);
    // The arc sits 30 px inside the box so the thumb and icons stay touchable.
    final radius = size.width / 2 - 30;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
        rect,
        _kVolStart,
        _kVolSweep,
        false,
        Paint()
          ..color = t.ac.withOpacity(0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7.0
          ..strokeCap = StrokeCap.round);

    if (volume > 0.0) {
      canvas.drawArc(
          rect,
          _kVolStart,
          _kVolSweep * volume,
          false,
          Paint()
            ..color = t.ac
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7.0
            ..strokeCap = StrokeCap.round);
    }

    // Thumb (also at 0, so you can see where the arc starts).
    final thumbAngle = _kVolStart + _kVolSweep * volume;
    final thumb = Offset(center.dx + radius * cos(thumbAngle),
        center.dy + radius * sin(thumbAngle));
    canvas.drawCircle(thumb, 11, Paint()..color = t.bg);
    canvas.drawCircle(
        thumb,
        11,
        Paint()
          ..color = t.ac
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6);
    canvas.drawCircle(thumb, 5, Paint()..color = t.ac);

    final iconRadius = radius + 22;
    _drawMaterialIcon(
        canvas,
        Offset(center.dx + iconRadius * cos(_kVolStart),
            center.dy + iconRadius * sin(_kVolStart)),
        Icons.volume_mute_rounded,
        t.ac,
        20.0);
    _drawMaterialIcon(
        canvas,
        Offset(center.dx + iconRadius * cos(_kVolStart + _kVolSweep),
            center.dy + iconRadius * sin(_kVolStart + _kVolSweep)),
        Icons.volume_up_rounded,
        t.ac,
        20.0);
  }

  @override
  bool shouldRepaint(covariant _VolumeArcPainter old) =>
      old.volume != volume || old.isDark != isDark;
}

/// The song timeline: bars that are uneven above AND below the centre line.
/// While the song plays the bars gently grow and shrink; tap or drag to seek.
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
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (context, box) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _seek(d.localPosition.dx, box.maxWidth),
          onHorizontalDragUpdate: (d) => _seek(d.localPosition.dx, box.maxWidth),
          child: SizedBox(
            height: 64,
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

  static const int barCount = 38;
  // Fixed, uneven heights (0.25 .. 1.0) so the shape is the same every time.
  static final List<double> _base = List<double>.generate(barCount, (i) {
    final env = (1.0 - ((i / (barCount - 1)) - 0.5).abs() * 1.3).clamp(0.3, 1.0);
    return (0.25 + 0.75 * Random(i * 7 + 3).nextDouble()) * env;
  });

  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / barCount;
    final barW = max(2.5, slot * 0.55);
    final midY = size.height / 2;
    final maxHalf = size.height / 2 - 2;
    final cur = (progress * barCount).clamp(0.0, barCount.toDouble());
    for (var i = 0; i < barCount; i++) {
      // Each bar breathes at its own offset so it looks like a living wave.
      final breathe =
          playing ? 0.78 + 0.22 * sin(2 * pi * (phase + i * 0.083)) : 1.0;
      final isActive = i + 0.5 <= cur;
      final nearHead = (i + 0.5 - cur).abs() < 1.2;
      final half = (_base[i] * breathe * (nearHead && playing ? 1.12 : 1.0))
              .clamp(0.12, 1.0) *
          maxHalf;
      final x = slot * i + slot / 2;
      final r = RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(x, midY), width: barW, height: max(5.0, half * 2)),
          Radius.circular(barW / 2));
      canvas.drawRRect(r, Paint()..color = isActive ? active : idle);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress ||
      old.phase != phase ||
      old.playing != playing ||
      old.active != active;
}

/// Distance of the tonearm pivot from the top of its box.
const double _kPivotY = 58;

class _TonearmPainter extends CustomPainter {
  _TonearmPainter(this.ac, this.bg);
  final Color ac;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width - 28, _kPivotY);
    final tip = Offset(24, size.height - 14);
    // The tube runs straight from the pivot to the "elbow"; the headshell
    // continues at a slight angle to the stylus tip.
    final elbow = Offset(tip.dx + 30, tip.dy - 46);
    final dark = Color.lerp(ac, Colors.black, 0.45)!;
    final light = Color.lerp(ac, bg, 0.6)!;

    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Counterweight behind the pivot (on the opposite side of the arm).
    final dir = (elbow - pivot) / (elbow - pivot).distance;
    final back = pivot - dir * 30;
    canvas.drawLine(pivot, back, stroke(dark, 9));
    final cw = RRect.fromRectAndRadius(
        Rect.fromCenter(center: back - dir * 8, width: 18, height: 22),
        const Radius.circular(5));
    canvas.save();
    canvas.translate(cw.center.dx, cw.center.dy);
    canvas.rotate(atan2(dir.dy, dir.dx) + pi / 2);
    canvas.translate(-cw.center.dx, -cw.center.dy);
    canvas.drawRRect(cw, Paint()..color = dark);
    for (final dy in [-5.0, 0.0, 5.0]) {
      canvas.drawLine(Offset(cw.left + 2, cw.center.dy + dy),
          Offset(cw.right - 2, cw.center.dy + dy), stroke(light.withOpacity(0.5), 1));
    }
    canvas.restore();

    // Arm tube: a body, a lit edge and a thin shadow line.
    canvas.drawLine(pivot, elbow, stroke(ac, 6));
    canvas.drawLine(pivot + const Offset(-1.6, 0), elbow + const Offset(-1.6, 0),
        stroke(light.withOpacity(0.55), 1.3));
    canvas.drawLine(pivot + const Offset(2, 0), elbow + const Offset(2, 0),
        stroke(dark.withOpacity(0.5), 1));

    // Headshell: slightly angled rounded plate with a finger lift.
    final hs = (tip - elbow);
    final hl = hs.distance;
    final hd = hs / hl;
    final ang = atan2(hd.dy, hd.dx);
    canvas.save();
    canvas.translate(elbow.dx, elbow.dy);
    canvas.rotate(ang - pi / 2);
    final plate = RRect.fromRectAndRadius(
        Rect.fromLTWH(-8, -4, 16, hl - 6), const Radius.circular(4));
    canvas.drawRRect(plate, Paint()..color = ac);
    canvas.drawRRect(plate, stroke(dark, 1));
    // finger lift (a small hook on the side)
    final hook = Path()
      ..moveTo(8, hl * 0.22)
      ..quadraticBezierTo(17, hl * 0.2, 15, hl * 0.42);
    canvas.drawPath(hook, stroke(ac, 2.2));
    // cartridge under the plate
    final cart = RRect.fromRectAndRadius(
        Rect.fromLTWH(-6, hl - 12, 12, 13), const Radius.circular(2));
    canvas.drawRRect(cart, Paint()..color = dark);
    // stylus
    canvas.drawLine(Offset(0, hl), Offset(0, hl + 5), stroke(bg, 1.6));
    canvas.restore();

    // Pivot base: outer ring, inner ring and the bearing cap.
    canvas.drawCircle(pivot, 26, Paint()..color = bg);
    canvas.drawCircle(pivot, 26, stroke(ac, 1.4));
    canvas.drawCircle(pivot, 19, stroke(ac.withOpacity(0.45), 1));
    canvas.drawCircle(pivot, 11, Paint()..color = ac);
    canvas.drawCircle(pivot, 11, stroke(dark, 1));
    canvas.drawCircle(pivot, 4, Paint()..color = bg);
  }

  @override
  bool shouldRepaint(_TonearmPainter old) => old.ac != ac || old.bg != bg;
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
  const _SongInfoSheet({required this.song});
  final Song song;

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
      constraints: BoxConstraints(maxHeight: h * 0.78),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: t.soft, width: 1),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: t.soft, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Text(song.title, style: noorSerif(t.ac, size: 28, height: 1.05)),
            const SizedBox(height: 12),
            if (details.isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                    child: CircularProgressIndicator(
                        color: t.ac, strokeWidth: 2)),
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
              row('Published', d.published == null ? null : SongDetails.monthYear(d.published!)),
              row('Views', d.views == null ? null : SongDetails.compactCount(d.views!)),
              row('Likes', d.likes == null ? null : SongDetails.compactCount(d.likes!)),
              row('Length', (d.duration == null || d.duration == Duration.zero) ? null : SongDetails.clock(d.duration!)),
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
            Center(
              child: GestureDetector(
                onTap: () => launchUrl(
                    Uri.parse('https://www.youtube.com/watch?v=${song.videoId}'),
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
            ),
        ],
      ),
    );
  }
}
