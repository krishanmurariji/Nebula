import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../providers/library_provider.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_song_card.dart';

/// Which song row has its actions open (only one at a time). Holds the
/// row's private token; null when none is open.
final openSongRowProvider = StateProvider<int?>((ref) => null);

/// Accepts a horizontal drag only when it starts towards the right, so a
/// leftward swipe still reaches the page view behind the list.
class _RightSwipeRecognizer extends HorizontalDragGestureRecognizer {
  _RightSwipeRecognizer({super.debugOwner});

  @override
  bool hasSufficientGlobalDistanceToAccept(
          PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) =>
      globalDistanceMoved > computeHitSlop(pointerDeviceKind, gestureSettings);
}

enum _Stage { closed, open, menu, naming }

/// A song card that can be swiped to the right to reveal its actions:
///
/// * **like**: filled when the song is liked; tap to toggle;
/// * **add to playlist**: opens a radial menu of the playlists (up to
///   [kMaxPlaylists]) around the button. Tap one to put the song in it (a
///   song lives in one playlist; tapping the one it is in takes it out).
///   While the menu is open the middle button becomes "new playlist" (or
///   "close" when the limit is reached); "new playlist" turns the button
///   into a name field inside the card with a round check button;
/// * **delete**: removes the song from the history.
///
/// Swipe left, press back, or open another row to put the card back. A long
/// press also opens the actions.
class NoorSongRow extends ConsumerStatefulWidget {
  const NoorSongRow({
    super.key,
    required this.song,
    required this.onTap,
    this.onPlayPause,
    this.artist,
    this.badge,
    this.current = false,
    this.playing = false,
    this.loading = false,
  });

  final Song song;
  final VoidCallback onTap;
  final VoidCallback? onPlayPause;

  /// Shown instead of [Song.artist] (e.g. without " - Topic").
  final String? artist;
  final String? badge;
  final bool current;
  final bool playing;
  final bool loading;

  @override
  ConsumerState<NoorSongRow> createState() => _NoorSongRowState();
}

class _NoorSongRowState extends ConsumerState<NoorSongRow>
    with TickerProviderStateMixin {
  static int _nextToken = 1;
  final int _token = _nextToken++;

  late final StateController<int?> _openRow;

  @override
  void initState() {
    super.initState();
    _openRow = ref.read(openSongRowProvider.notifier);
  }

  /// 0 = card in place, 1 = card fully off to the right.
  late final AnimationController _slide = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 340));

  /// The radial menu (0 = folded into the button, 1 = spread out).
  late final AnimationController _menuCtrl = AnimationController(vsync: this);

  _Stage _stage = _Stage.closed;
  double _width = 360;

  final LayerLink _anchor = LayerLink();
  OverlayEntry? _menu;
  bool _menuUp = true;
  String? _pickedId; // bubble showing a thumbs-up
  bool _thumbsUp = false; // middle button showing a thumbs-up
  bool _busy = false; // an add / create is finishing

  final TextEditingController _name = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  String? _nameError;
  double _lastKeyboard = 0;

  @override
  void dispose() {
    _removeMenu();
    _clearOpenRowLater(scheduleMicrotask);
    _slide.dispose();
    _menuCtrl.dispose();
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // ── Open / close ──────────────────────────────────────────────────────────

  /// Marks "no row open" later (never during a build), unless another row
  /// has opened since, or the whole provider scope has gone away.
  void _clearOpenRowLater(void Function(void Function()) later) {
    final c = _openRow;
    final token = _token;
    later(() {
      try {
        if (c.state == token) c.state = null;
      } catch (_) {/* provider scope already disposed */}
    });
  }

  void _open() {
    if (_stage == _Stage.closed) {
      HapticFeedback.selectionClick();
      setState(() => _stage = _Stage.open);
    }
    _openRow.state = _token;
    _slide.animateTo(1, curve: Curves.easeOutCubic);
  }

  Future<void> _close() async {
    _removeMenu();
    _nameFocus.unfocus();
    if (!mounted) return;
    if (_stage == _Stage.closed && _slide.value == 0) return;
    await _slide.animateBack(0, curve: Curves.easeOutCubic);
    if (!mounted) return;
    setState(() {
      _stage = _Stage.closed;
      _thumbsUp = false;
      _pickedId = null;
      _busy = false;
      _nameError = null;
      _name.clear();
    });
    // After this frame, so a page's own back handler still sees that a row
    // was open when this back press is handled.
    _clearOpenRowLater(
        (f) => WidgetsBinding.instance.addPostFrameCallback((_) => f()));
  }

  /// Back button / gesture: undo one layer.
  void _back() {
    switch (_stage) {
      case _Stage.menu:
        _closeMenu();
      case _Stage.naming:
        _cancelNaming();
      case _Stage.open:
        _close();
      case _Stage.closed:
        break;
    }
  }

  // ── Drags ─────────────────────────────────────────────────────────────────

  void _dragUpdate(DragUpdateDetails d) {
    if (_busy || _stage == _Stage.menu || _stage == _Stage.naming) return;
    _slide.value = (_slide.value + d.primaryDelta! / _width).clamp(0.0, 1.0);
  }

  void _dragEnd(DragEndDetails d) {
    if (_busy || _stage == _Stage.menu || _stage == _Stage.naming) return;
    final v = d.primaryVelocity ?? 0;
    if (v > 500 || (v > -500 && _slide.value > 0.35)) {
      _open();
    } else {
      _close();
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _toggleLike() {
    HapticFeedback.mediumImpact();
    ref.read(likedProvider.notifier).toggle(widget.song);
  }

  Future<void> _deleteFromHistory() async {
    HapticFeedback.mediumImpact();
    await ref.read(historyProvider.notifier).remove(widget.song.videoId);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text('Removed from your history'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2)));
    _close();
  }

  // ── Radial menu ───────────────────────────────────────────────────────────

  void _openMenu() {
    if (_busy) return;
    HapticFeedback.selectionClick();
    // Spread upwards unless the button is too close to the top of the
    // screen; then downwards.
    final box = context.findRenderObject() as RenderBox?;
    final top = box?.localToGlobal(Offset.zero).dy ?? 400;
    final safeTop = MediaQuery.paddingOf(context).top;
    final n = ref.read(playlistProvider).length;
    _menuUp = top - safeTop > _radiusFor(n) + 70;
    _menuCtrl.duration = Duration(milliseconds: 300 + 60 * max(0, n - 1));
    setState(() => _stage = _Stage.menu);
    _menu = OverlayEntry(builder: _buildMenu);
    Overlay.of(context).insert(_menu!);
    _menuCtrl.forward(from: 0);
  }

  Future<void> _closeMenu() async {
    if (_menu == null) return;
    await _menuCtrl.reverse();
    _removeMenu();
    if (mounted && _stage == _Stage.menu) setState(() => _stage = _Stage.open);
  }

  void _removeMenu() {
    _menu?.remove();
    _menu = null;
  }

  Future<void> _pick(Playlist pl) async {
    if (_busy) return;
    _busy = true;
    HapticFeedback.mediumImpact();
    final notifier = ref.read(playlistProvider.notifier);
    if (pl.songs.any((s) => s.videoId == widget.song.videoId)) {
      await notifier.removeSong(pl.id, widget.song.videoId);
    } else {
      await notifier.addSong(pl.id, widget.song);
    }
    if (!mounted) return;
    _pickedId = pl.id;
    _menu?.markNeedsBuild();
    await Future<void>.delayed(const Duration(milliseconds: 380));
    if (!mounted) return;
    await _menuCtrl.reverse();
    _removeMenu();
    if (!mounted) return;
    setState(() {
      _stage = _Stage.open;
      _thumbsUp = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    if (mounted) _close();
  }

  Future<void> _startNaming() async {
    if (ref.read(playlistProvider.notifier).isFull) return _closeMenu();
    HapticFeedback.selectionClick();
    await _menuCtrl.reverse();
    _removeMenu();
    if (!mounted) return;
    setState(() {
      _stage = _Stage.naming;
      _nameError = null;
      _name.clear();
    });
    // Let the field grow before the keyboard comes up.
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (mounted && _stage == _Stage.naming) _nameFocus.requestFocus();
  }

  void _cancelNaming() {
    _nameFocus.unfocus();
    setState(() {
      _stage = _Stage.open;
      _nameError = null;
    });
  }

  Future<void> _confirmName() async {
    if (_busy) return;
    final name = _name.text.trim();
    final notifier = ref.read(playlistProvider.notifier);
    String? error;
    if (name.isEmpty) {
      error = 'Enter a name';
    } else if (notifier.nameTaken(name)) {
      error = 'Name already used';
    } else if (notifier.isFull) {
      error = 'Limit of $kMaxPlaylists reached';
    }
    if (error != null) {
      HapticFeedback.heavyImpact();
      setState(() => _nameError = error);
      return;
    }
    _busy = true;
    HapticFeedback.mediumImpact();
    try {
      final pl = await notifier.create(name);
      await notifier.addSong(pl.id, widget.song);
    } on PlaylistLimitException {
      _busy = false;
      if (mounted)
        setState(() => _nameError = 'Limit of $kMaxPlaylists reached');
      return;
    }
    if (!mounted) return;
    _nameFocus.unfocus();
    setState(() => _thumbsUp = true);
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    if (mounted) _close();
  }

  /// Keeps the card above the keyboard while the name field is in use.
  void _keepAboveKeyboard() {
    if (!mounted || _stage != _Stage.naming) return;
    final box = context.findRenderObject() as RenderBox?;
    final position = Scrollable.maybeOf(context)?.position;
    if (box == null || !box.attached || position == null) return;
    final mq = MediaQuery.of(context);
    final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
    final limit = mq.size.height - mq.viewInsets.bottom - 16;
    if (bottom <= limit) return;
    final target =
        min(position.pixels + bottom - limit, position.maxScrollExtent);
    position.animateTo(target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<int?>(openSongRowProvider, (_, open) {
      if (open != _token && _stage != _Stage.closed) _close();
    });
    final t = NoorTheme.of(context);
    final liked = ref.watch(isLikedProvider(widget.song.videoId));

    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (_stage == _Stage.naming && keyboard != _lastKeyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _keepAboveKeyboard());
    }
    _lastKeyboard = keyboard;

    return PopScope(
      canPop: _stage == _Stage.closed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: LayoutBuilder(builder: (context, box) {
        _width = box.maxWidth;
        return AnimatedBuilder(
          animation: _slide,
          builder: (context, card) => Stack(
            children: [
              if (_slide.value > 0)
                Positioned.fill(
                  child: Opacity(
                    opacity: Curves.easeIn
                        .transform((_slide.value * 1.6).clamp(0.0, 1.0)),
                    child: _actions(t, liked),
                  ),
                ),
              Transform.translate(
                offset: Offset(_slide.value * (_width + 24), 0),
                child: card,
              ),
            ],
          ),
          child: RawGestureDetector(
            gestures: {
              _RightSwipeRecognizer:
                  GestureRecognizerFactoryWithHandlers<_RightSwipeRecognizer>(
                () => _RightSwipeRecognizer(debugOwner: this),
                (r) => r
                  ..onUpdate = _dragUpdate
                  ..onEnd = _dragEnd,
              ),
            },
            child: NoorSongCard(
              thumbnailUrl: widget.song.thumbnailUrl,
              title: widget.song.title,
              artist: widget.artist ?? widget.song.artist,
              badge: widget.badge,
              liked: liked,
              current: widget.current,
              playing: widget.playing,
              loading: widget.loading,
              onTap: widget.onTap,
              onPlayPause: widget.onPlayPause,
              onToggleLike: _toggleLike,
              onLongPress: _open,
            ),
          ),
        );
      }),
    );
  }

  /// The row behind the card: like, add to playlist (centre), delete.
  Widget _actions(NoorTheme t, bool liked) {
    final inHistory =
        ref.watch(historyProvider).any((s) => s.videoId == widget.song.videoId);
    final naming = _stage == _Stage.naming;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _dragUpdate,
      onHorizontalDragEnd: _dragEnd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        child: Container(
          height: NoorSongCard.height,
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: BorderRadius.circular(kNoorCardRadius),
            border: Border.all(color: t.ac, width: 0.8),
          ),
          child: LayoutBuilder(builder: (context, inner) {
            return Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 9,
                  child: _fade(
                    !naming,
                    _CircleAction(
                      icon: liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      label: liked ? 'Unlike' : 'Like',
                      filled: liked,
                      onTap: _toggleLike,
                    ),
                  ),
                ),
                Positioned(
                  right: 9,
                  child: _fade(
                    !naming,
                    _CircleAction(
                      icon: Icons.delete_outline_rounded,
                      label: 'Remove from history',
                      enabled: inHistory,
                      onTap: _deleteFromHistory,
                    ),
                  ),
                ),
                CompositedTransformTarget(
                  link: _anchor,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    width: naming ? inner.maxWidth - 14 : 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: naming || _thumbsUp ? t.bg : t.ac,
                      borderRadius: BorderRadius.circular(23),
                      border: Border.all(color: t.ac, width: 0.8),
                    ),
                    child: naming ? _nameField(t) : _centreButton(t),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _fade(bool visible, Widget child) => AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(ignoring: !visible, child: child),
      );

  Widget _centreButton(NoorTheme t) => Semantics(
        container: true,
        button: true,
        label: 'Add to playlist',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _thumbsUp ? null : _openMenu,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Icon(
                _thumbsUp
                    ? Icons.thumb_up_alt_rounded
                    : Icons.playlist_add_rounded,
                key: ValueKey(_thumbsUp),
                color: _thumbsUp ? t.ac : t.bg,
                size: 22,
              ),
            ),
          ),
        ),
      );

  Widget _nameField(NoorTheme t) {
    final error = _nameError;
    return LayoutBuilder(
      // While the button is still growing into a field, show nothing.
      builder: (context, box) => box.maxWidth < 170
          ? const SizedBox.shrink()
          : ClipRRect(
              borderRadius: BorderRadius.circular(23),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      focusNode: _nameFocus,
                      maxLength: 30,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      textInputAction: TextInputAction.done,
                      textCapitalization: TextCapitalization.sentences,
                      textAlignVertical: TextAlignVertical.center,
                      onChanged: (_) {
                        if (_nameError != null)
                          setState(() => _nameError = null);
                      },
                      onSubmitted: (_) => _confirmName(),
                      cursorColor: t.ac,
                      style: TextStyle(
                          color: t.ac,
                          fontSize: 14,
                          height: 1.2,
                          fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        counterText: '',
                        border: InputBorder.none,
                        hintText: 'Enter name',
                        hintStyle:
                            TextStyle(color: t.mute, fontSize: 14, height: 1.2),
                      ),
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(error,
                          style: const TextStyle(
                              color: Color(0xFFC0392B),
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(width: 6),
                  Semantics(
                    container: true,
                    button: true,
                    label: 'Create playlist',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: _thumbsUp ? null : _confirmName,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _thumbsUp ? t.bg : t.ac,
                          border: Border.all(color: t.ac, width: 0.8),
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          transitionBuilder: (c, a) => ScaleTransition(
                              scale: a,
                              child: RotationTransition(
                                  turns:
                                      Tween(begin: -0.15, end: 0.0).animate(a),
                                  child: c)),
                          child: Icon(
                            _thumbsUp
                                ? Icons.thumb_up_alt_rounded
                                : Icons.check_rounded,
                            key: ValueKey(_thumbsUp),
                            size: 18,
                            color: _thumbsUp ? t.ac : t.bg,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
    );
  }

  // ── The radial menu overlay ───────────────────────────────────────────────

  static double _radiusFor(int n) => (n * 48 / pi).clamp(72.0, 130.0);

  Widget _buildMenu(BuildContext overlayContext) {
    return Consumer(builder: (context, ref, _) {
      final t = NoorTheme.of(this.context);
      final playlists = ref.watch(playlistProvider);
      final n = playlists.length;
      final r = _radiusFor(n);
      final canCreate = n < kMaxPlaylists;
      const bubble = 42.0;
      final box = (r + 80) * 2;
      // The overlay sits outside the page's Material, so give its text a
      // proper style (no fallback font, no debug underline).
      return Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // Tap anywhere else to fold the menu back.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _busy ? null : _closeMenu,
                child: AnimatedBuilder(
                  animation: _menuCtrl,
                  builder: (_, __) => ColoredBox(
                      color: t.bg.withOpacity(0.88 *
                          Curves.easeOut
                              .transform(_menuCtrl.value.clamp(0.0, 1.0)))),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              width: box,
              height: box,
              child: CompositedTransformFollower(
                link: _anchor,
                showWhenUnlinked: false,
                targetAnchor: Alignment.center,
                followerAnchor: Alignment.center,
                child: AnimatedBuilder(
                  animation: _menuCtrl,
                  builder: (context, _) {
                    final total = _menuCtrl.duration!.inMilliseconds.toDouble();
                    final c = Offset(box / 2, box / 2);
                    final children = <Widget>[];
                    final captions = <Widget>[];
                    for (var i = 0; i < n; i++) {
                      // Staggered like the CSS demo: each item 60 ms later,
                      // 300 ms long, swinging out from the button.
                      final start = 60 * i / total;
                      final end = (60 * i + 300) / total;
                      final e = Curves.ease.transform(
                          ((_menuCtrl.value - start) / (end - start))
                              .clamp(0.0, 1.0));
                      final target = n == 1
                          ? (_menuUp ? -pi / 2 : pi / 2)
                          : (_menuUp
                              ? pi + i * pi / (n - 1)
                              : pi - i * pi / (n - 1));
                      final a = target * e;
                      final dir = Offset(cos(a), sin(a));
                      final p = c + dir * (r * e);
                      final pl = playlists[i];
                      final inIt =
                          pl.songs.any((s) => s.videoId == widget.song.videoId);
                      final picked = _pickedId == pl.id;
                      var cap =
                          c + Offset(cos(target), sin(target)) * (r + 38) * e;
                      // Keep names on screen: a name that would run off the
                      // side sits above (or below) its bubble instead.
                      final halfScreen = MediaQuery.sizeOf(context).width / 2;
                      final maxDx = halfScreen - 52;
                      if ((cap.dx - c.dx).abs() > maxDx) {
                        cap = Offset(
                            c.dx + (cap.dx - c.dx).clamp(-maxDx, maxDx),
                            p.dy + (_menuUp ? -32 : 32) * e);
                      }
                      captions.add(Positioned(
                        left: cap.dx - 42,
                        top: cap.dy - 10,
                        width: 84,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: e,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: t.bg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(pl.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: t.ac,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ),
                        ),
                      ));
                      children
                        ..add(Positioned(
                          left: p.dx - bubble / 2,
                          top: p.dy - bubble / 2,
                          child: Opacity(
                            opacity: e,
                            child: Transform.rotate(
                              angle: pi / 4 * (1 - e),
                              child: Semantics(
                                container: true,
                                button: true,
                                label: inIt
                                    ? 'Remove from ${pl.name}'
                                    : 'Add to ${pl.name}',
                                excludeSemantics: true,
                                child: GestureDetector(
                                  onTap: () => _pick(pl),
                                  child: Container(
                                    width: bubble,
                                    height: bubble,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: inIt && !picked ? t.ac : t.bg,
                                      border:
                                          Border.all(color: t.ac, width: 0.9),
                                      boxShadow: [
                                        BoxShadow(
                                            color: t.ac.withOpacity(0.15),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3)),
                                      ],
                                    ),
                                    child: AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 220),
                                      transitionBuilder: (c, a) =>
                                          ScaleTransition(scale: a, child: c),
                                      child: picked
                                          ? Icon(Icons.thumb_up_alt_rounded,
                                              key: const ValueKey('up'),
                                              size: 18,
                                              color: t.ac)
                                          : Text(_initials(pl.name),
                                              key: const ValueKey('txt'),
                                              style: TextStyle(
                                                  color: inIt ? t.bg : t.ac,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ));
                    }
                    // The middle button: "new playlist" (or close at the limit),
                    // its icon turning as the menu opens.
                    final m = Curves.easeOut
                        .transform((_menuCtrl.value * 3).clamp(0.0, 1.0));
                    children.add(Positioned(
                      left: c.dx - 23,
                      top: c.dy - 23,
                      child: Semantics(
                        container: true,
                        button: true,
                        label: canCreate ? 'Make a new playlist' : 'Close',
                        excludeSemantics: true,
                        child: GestureDetector(
                          onTap: _busy
                              ? null
                              : (canCreate ? _startNaming : _closeMenu),
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: t.ac,
                              border: Border.all(color: t.ac, width: 0.8),
                            ),
                            child: Transform.rotate(
                              angle: pi / 2 * m,
                              child: Icon(
                                m < 0.5
                                    ? Icons.playlist_add_rounded
                                    : (canCreate
                                        ? Icons.add_rounded
                                        : Icons.close_rounded),
                                color: t.bg,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ));
                    children.add(Positioned(
                      left: c.dx - 50,
                      top: _menuUp ? c.dy + 28 : c.dy - 44,
                      width: 100,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: m,
                          child: Text(
                              canCreate
                                  ? 'New playlist'
                                  : 'Limit of $kMaxPlaylists',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: t.ac,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ));
                    return Stack(
                        clipBehavior: Clip.none,
                        children: [...children, ...captions]);
                  },
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return w.substring(0, min(2, w.length)).toUpperCase();
    }
    return (words.first[0] + words.elementAt(1)[0]).toUpperCase();
  }
}

/// A round action button in a thin ring; [filled] fills it with the accent.
class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1 : 0.35,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? t.ac : t.bg,
              border: Border.all(color: t.ac, width: 0.8),
            ),
            child: Icon(icon, size: 21, color: filled ? t.bg : t.ac),
          ),
        ),
      ),
    );
  }
}
