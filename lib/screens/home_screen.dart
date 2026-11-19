import 'dart:math';
import 'dart:math' as math;
import '../providers/gesture_settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../providers/last_played_provider.dart';
import '../providers/local_music_provider.dart';
import '../providers/home_order_provider.dart';
import '../providers/theme_provider.dart';
import 'mini_player.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import '../widgets/search_filter_menu.dart';
import '../providers/search_provider.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_artwork.dart';
import '../theme/noor_song_card.dart';
import '../theme/ripple_ring_clipper.dart';
import '../widgets/song_row.dart';
import '../widgets/noor_toast.dart';
import '../widgets/offline_pill.dart';
import '../theme/noor_watermark.dart';
import '../theme/noor_search_button.dart';

/// Bumped by other pages (e.g. the player's Search button) to open search
/// on Home.
final homeSearchRequestProvider = StateProvider<int>((ref) => 0);

/// One card of the Home slider.
class HomeCategory {
  const HomeCategory(this.id, this.title, this.songs);
  final String id;
  final String title;
  final List<Song> songs;
}

/// The Home slider: My History, My Favorites and My Music are always there
/// (even when empty); every playlist follows. [order] is the user's own
/// arrangement (hold a card and drag), if any.
List<HomeCategory> homeCategories({
  required List<Song> liked,
  required List<Song> history,
  required List<Song> onDevice,
  required List<Playlist> playlists,
  List<String> order = const [],
}) {
  final seen = <String>{};
  final distinctHistory = history.where((s) => seen.add(s.videoId)).toList();
  return applyHomeOrder<HomeCategory>([
    HomeCategory('hist', 'My History', distinctHistory),
    HomeCategory('fav', 'My Favorites', liked),
    HomeCategory('music', 'My Music', onDevice),
    for (final p in playlists) HomeCategory(p.id, p.name, p.songs),
  ], (c) => c.id, order);
}

/// The three cards that are always there (the rest are playlists).
const kFixedHomeCards = {'hist', 'fav', 'music'};

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  String? _selectedId;

  /// Picks which song's artwork fills each slider card; new every launch.
  final int _artSeed = Random().nextInt(1 << 30);

  bool _searching = false;
  final _query = TextEditingController();
  final _queryFocus = FocusNode();

  @override
  void dispose() {
    _binDrop.dispose();
    _vortex.dispose();
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  void _openSearch() {
    HapticFeedback.selectionClick();
    setState(() => _searching = true);
    Future.delayed(const Duration(milliseconds: 280), () {
      if (mounted && _searching) _queryFocus.requestFocus();
    });
  }

  void _openSettings() {
    HapticFeedback.selectionClick();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _closeSearch() {
    HapticFeedback.selectionClick();
    _queryFocus.unfocus();
    _query.clear();
    ref.read(searchProvider.notifier).clear();
    setState(() => _searching = false);
  }

  void _runSearch() {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    ref.read(searchProvider.notifier).search(q);
    _queryFocus.unfocus();
  }

  String _artFor(HomeCategory c) {
    if (c.songs.isEmpty) return '';
    final withArt = c.songs.where((s) => s.thumbnailUrl.isNotEmpty).toList();
    if (withArt.isEmpty) return '';
    return withArt[(_artSeed + c.id.hashCode).abs() % withArt.length]
        .thumbnailUrl;
  }

  void _select(String id) {
    if (_selectedId == id) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedId = id);
    // Access to the phone's music may have been given meanwhile.
    if (id == 'music') ref.read(localMusicProvider.notifier).checkAgain();
  }

  bool _pullFired = false;

  /// My Music can also list the phone's own music once access is given.
  bool get _needsPhoneAccess {
    final a = ref.watch(localMusicProvider).access;
    return a != LocalAccess.granted && a != LocalAccess.unsupported;
  }

  /// Swipe down on the (non-scrolling) top of Home opens search. (The
  /// player opens from the bottom card: tap it or swipe it up.)
  void _onTopVerticalSwipe(DragEndDetails d) {
    if (!_swipeSearchOn) return;
    if ((d.primaryVelocity ?? 0) > 300) _openSearch();
  }

  /// "Swipe down on Home opens search" (Settings → Gestures).
  bool get _swipeSearchOn =>
      ref.read(gestureOnProvider(NoorGesture.homeSwipeDownSearch));

  /// Pulling the song list down past its top opens search.
  bool _onListScroll(ScrollNotification n) {
    if (n is ScrollUpdateNotification &&
        n.dragDetails != null &&
        n.metrics.pixels < -80 &&
        _swipeSearchOn &&
        !_pullFired &&
        !_searching) {
      _pullFired = true;
      _openSearch();
    } else if (n is ScrollEndNotification) {
      _pullFired = false;
    }
    return false;
  }

  // ── Arranging the slider ───────────────────────────────────────────────

  /// True while the cards are laid out side by side to be dragged.
  bool _arranging = false;

  /// The order being arranged (ids), saved when a drag ends.
  List<String> _arrangeOrder = const [];

  /// The card being dragged, if any.
  String? _draggingId;

  /// Where the finger last touched a slider card (global x), and where the
  /// held card's place in the row was when arranging began: the row is
  /// laid out so that place stays under the finger.
  double _pointerX = 0;
  double _anchorX = 0;
  int _heldIndex = 0;

  void _startArranging(List<HomeCategory> cats, String heldId) {
    HapticFeedback.mediumImpact();
    setState(() {
      _arranging = true;
      _arrangeOrder = [for (final c in cats) c.id];
      _anchorX = _pointerX;
      _heldIndex = _arrangeOrder.indexOf(heldId).clamp(0, cats.length);
    });
  }

  void _stopArranging() {
    setState(() {
      _arranging = false;
      _draggingId = null;
    });
  }

  /// Moves [id] to where [target] is, as the dragged card passes over it.
  void _moveCard(String id, String target) {
    final from = _arrangeOrder.indexOf(id);
    final to = _arrangeOrder.indexOf(target);
    if (from < 0 || to < 0 || from == to) return;
    HapticFeedback.selectionClick();
    setState(() {
      _arrangeOrder = [..._arrangeOrder]
        ..removeAt(from)
        ..insert(to, id);
    });
  }

  /// Letting go ends arranging (no Done button): the order is kept.
  void _dragEnded() {
    ref.read(homeOrderProvider.notifier).set(_arrangeOrder);
    if (_falling != null) {
      setState(() => _draggingId = null); // the wormhole finishes first
      return;
    }
    _stopArranging();
  }

  // ── The bin at the top of the screen ──────────────────────────────────

  /// Drop animation: the card spirals into the wormhole and vanishes.
  late final AnimationController _binDrop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  /// The wormhole's slow turn while it is open.
  late final AnimationController _vortex = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400));
  HomeCategory? _falling; // the playlist card dropping into the bin
  Offset _fallFrom = Offset.zero; // where it was let go (global)

  /// Where the bin sits (global), for the falling card to aim at.
  Offset _binCentre(BuildContext context) => Offset(
      MediaQuery.sizeOf(context).width / 2,
      MediaQuery.paddingOf(context).top + 36);

  Future<void> _dropOnBin(HomeCategory c, Offset from) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _draggingId = null;
      _falling = c;
      _fallFrom = from;
    });
    await _binDrop.forward(from: 0);
    if (!mounted) return;
    final playlists = ref.read(playlistProvider);
    final at = playlists.indexWhere((p) => p.id == c.id);
    final removed = at < 0 ? null : playlists[at];
    final orderBefore = _arrangeOrder;
    await ref.read(playlistProvider.notifier).delete(c.id);
    final left = _arrangeOrder.where((id) => id != c.id).toList();
    if (!mounted) return;
    setState(() {
      _falling = null;
      _arrangeOrder = left;
      _arranging = false;
      if (_selectedId == c.id) _selectedId = null;
    });
    _binDrop.value = 0;
    ref.read(homeOrderProvider.notifier).set(left);
    NoorToast.show(
      context,
      '"${c.title}" deleted',
      action: removed == null ? null : 'Undo',
      onAction: removed == null
          ? null
          : () async {
              await ref.read(playlistProvider.notifier).restore(removed, at);
              if (!mounted) return;
              setState(() => _arrangeOrder = orderBefore);
              ref.read(homeOrderProvider.notifier).set(orderBefore);
            },
    );
  }

  /// The delete area across the top of the screen, shown while a playlist
  /// is held: a faint wormhole whose glow fades out at its edges; it turns
  /// red and spins faster when the card is over it.
  Widget _binZone(NoorTheme t, Map<String, HomeCategory> byId) {
    final show =
        (_draggingId != null && !kFixedHomeCards.contains(_draggingId)) ||
            _falling != null;
    if (show && !_vortex.isAnimating) _vortex.repeat();
    if (!show && _vortex.isAnimating) _vortex.stop();
    const red = Color(0xFFD64545);
    final top = MediaQuery.paddingOf(context).top;
    return IgnorePointer(
      ignoring: !show,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 240),
        opacity: show ? 1 : 0,
        child: DragTarget<String>(
          onWillAcceptWithDetails: (d) => !kFixedHomeCards.contains(d.data),
          onAcceptWithDetails: (d) {
            final c = byId[d.data];
            if (c != null) _dropOnBin(c, d.offset + const Offset(25, 80));
          },
          builder: (context, hovering, _) {
            final hot = hovering.isNotEmpty || _falling != null;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: top + 110,
              padding: EdgeInsets.only(top: top + 4),
              // No hard edge: the glow fades out towards the sides and
              // the bottom.
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 1.25,
                  colors: [
                    red.withOpacity(hot ? 0.30 : 0.10),
                    red.withOpacity(hot ? 0.12 : 0.04),
                    red.withOpacity(0),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
              child: Column(children: [
                AnimatedBuilder(
                  animation: Listenable.merge([_vortex, _binDrop]),
                  builder: (_, __) {
                    // Swallowing a card: the hole flares, then settles.
                    final v = _binDrop.value;
                    final gulp = _falling == null
                        ? 0.0
                        : (v < 0.7 ? v / 0.7 : (1 - (v - 0.7) / 0.3))
                            .clamp(0.0, 1.0);
                    return SizedBox(
                      width: 64,
                      height: 64,
                      child: CustomPaint(
                        painter: _WormholePainter(
                          turn: _vortex.value * (hot ? 2 : 1),
                          strength: hot ? 1 : 0.45,
                          gulp: gulp,
                          color: red,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 2),
                Text(
                    hot
                        ? 'Let go to delete'
                        : 'Drag here to delete the playlist',
                    style: TextStyle(
                        color: red.withOpacity(hot ? 1 : 0.55),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ]),
            );
          },
        ),
      ),
    );
  }

  /// The card being swallowed: it spirals into the wormhole, turning,
  /// shrinking and fading until it is gone.
  Widget _fallingCard() {
    final c = _falling;
    if (c == null) return const SizedBox.shrink();
    final to = _binCentre(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _binDrop,
        builder: (_, __) {
          final f = Curves.easeInCubic
              .transform((_binDrop.value / 0.8).clamp(0.0, 1.0));
          if (f >= 1) return const SizedBox.shrink();
          // A curved path: it swings round the hole as it falls in.
          final straight = Offset.lerp(_fallFrom, to, f)!;
          final swirl =
              Offset(math.cos(f * 2 * math.pi), math.sin(f * 2 * math.pi)) *
                  (40 * (1 - f) * f * 4);
          final pos = straight + swirl;
          return Stack(children: [
            Positioned(
              left: pos.dx - 24,
              top: pos.dy - 76,
              child: Opacity(
                opacity: (1 - f * f).clamp(0.0, 1.0),
                child: Transform.rotate(
                  angle: f * 3 * 2 * math.pi,
                  child: Transform.scale(
                    scale: (1 - f).clamp(0.02, 1.0),
                    child: SizedBox(
                      width: 48,
                      height: 152,
                      child: _CategoryCard(
                          icon: _iconFor(c.id),
                          artUrl: _artFor(c),
                          active: false),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  // ── The slider ──────────────────────────────────────────────────────────

  /// One row of cards for both modes, so a hold flows straight into a
  /// drag. Normally: the open card wide, its neighbours as narrow strips.
  /// Arranging: every card a narrow strip, centred, in the order being
  /// arranged.
  Widget _slider(List<HomeCategory> cats, int index, double activeWidth,
      HomeCategory current, NoorTheme t) {
    final byId = {for (final c in cats) c.id: c};
    final shown = !_arranging
        ? cats
        : [
            for (final id in _arrangeOrder)
              if (byId.containsKey(id)) byId[id]!,
            for (final c in cats)
              if (!_arrangeOrder.contains(c.id)) c,
          ];
    final indexOf = {for (var i = 0; i < cats.length; i++) cats[i].id: i};

    Widget card(HomeCategory c) {
      final i = indexOf[c.id]!;
      final active = !_arranging && i == index;
      final adjacent = !_arranging && (i - index).abs() == 1;
      final visible = _arranging || active || adjacent;
      final box = AnimatedContainer(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        width: _arranging ? 48 : (active ? activeWidth : (adjacent ? 48 : 0)),
        margin: EdgeInsets.symmetric(horizontal: visible ? 6 : 0, vertical: 8),
        child: visible
            ? AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _draggingId == c.id ? 0.25 : 1,
                child: _CategoryCard(
                    icon: _iconFor(c.id), artUrl: _artFor(c), active: active),
              )
            : const SizedBox.shrink(),
      );
      return DragTarget<String>(
        key: ValueKey('slide_${c.id}'),
        onWillAcceptWithDetails: (d) {
          if (!_arranging || d.data == c.id) return false;
          _moveCard(d.data, c.id);
          return true;
        },
        builder: (context, _, __) => LongPressDraggable<String>(
          data: c.id,
          maxSimultaneousDrags: visible ? 1 : 0,
          delay: const Duration(milliseconds: 380),
          hapticFeedbackOnStart: true,
          // The lifted card sits centred under the finger.
          dragAnchorStrategy: (_, __, ___) => const Offset(25.4, 80.6),
          onDragStarted: () {
            if (!_arranging) _startArranging(cats, c.id);
            setState(() => _draggingId = c.id);
          },
          onDragEnd: (_) => _dragEnded(),
          onDraggableCanceled: (_, __) => _dragEnded(),
          feedback: Material(
            type: MaterialType.transparency,
            child: Transform.scale(
              scale: 1.06,
              child: SizedBox(
                width: 48,
                height: 152,
                child: _CategoryCard(
                    icon: _iconFor(c.id), artUrl: _artFor(c), active: false),
              ),
            ),
          ),
          child: Listener(
            onPointerDown: (e) => _pointerX = e.position.dx,
            child: GestureDetector(
              onTap: _arranging ? null : () => _select(c.id),
              child: box,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragEnd: _arranging ? null : _onTopVerticalSwipe,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 168,
            child: GestureDetector(
              onHorizontalDragEnd: _arranging
                  ? null
                  : (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v < -200) {
                        if (index < cats.length - 1)
                          _select(cats[index + 1].id);
                      } else if (v > 200) {
                        if (index > 0) {
                          _select(cats[index - 1].id);
                        } else if (_swipeSearchOn) {
                          _openSearch(); // before the first card
                        }
                      }
                    },
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: _arranging
                      ? const BouncingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: box.maxWidth - 24),
                    child: Row(
                      children: [
                        // Arranging: the narrow cards gather round the held
                        // one, whose place stays under the finger.
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOutCubic,
                          width: !_arranging
                              ? 0
                              : (_anchorX - 12 - _heldIndex * 60 - 30).clamp(
                                  0.0,
                                  math.max(0.0,
                                      box.maxWidth - 24 - shown.length * 60.0)),
                        ),
                        for (final c in shown) card(c),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: SizedBox(
              key: ValueKey(_arranging),
              height: 30,
              child: Center(
                child: _arranging
                    ? Text('Drag to a new place, let go to finish',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.mute, fontSize: 12.5))
                    : NoorLinedLabel(current.title),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _play(Song song, List<Song> queue) {
    HapticFeedback.lightImpact();
    final ps = ref.read(playerProvider);
    if (ps.song?.videoId == song.videoId) {
      ref.read(playerProvider.notifier).togglePlay();
    } else {
      ref.read(playerProvider.notifier).playSong(song, queue: queue);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(homeSearchRequestProvider, (_, __) {
      if (!_searching) _openSearch();
    });
    final playlists = ref.watch(playlistProvider);
    final history = ref.watch(historyProvider);
    final liked = ref.watch(likedSongsProvider);
    final onDevice = ref.watch(myMusicProvider);
    final ps = ref.watch(playerProvider);
    final libraryReady = ref.watch(libraryReadyProvider).valueOrNull ?? false;
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final t = NoorTheme.byMode(isDark);
    final topPad = MediaQuery.of(context).padding.top;
    final screenWidth = MediaQuery.of(context).size.width;

    final cats = homeCategories(
        liked: liked,
        history: history,
        onDevice: onDevice,
        playlists: playlists,
        order: ref.watch(homeOrderProvider));

    // Start on the first card that has songs; keep the user's own choice.
    var index = cats.indexWhere((c) => c.id == _selectedId);
    if (index < 0) {
      index = max(0, cats.indexWhere((c) => c.songs.isNotEmpty));
      if (libraryReady) _selectedId = cats[index].id;
    }
    final current = cats[index];
    final askPhone = current.id == 'music' && _needsPhoneAccess;

    final visible = 1 + (index > 0 ? 1 : 0) + (index < cats.length - 1 ? 1 : 0);
    final activeWidth =
        screenWidth - 24 - visible * 12.0 - (visible - 1) * 48.0 - 1;

    return PopScope(
      // Back (button or gesture) closes search first.
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        // A song row with its actions open handles back itself.
        if (!didPop && _searching && ref.read(openSongRowProvider) == null) {
          // Suggestions over earlier results: back shows the results first.
          if (_queryFocus.hasFocus &&
              ref.read(searchProvider).status != SearchStatus.idle) {
            _queryFocus.unfocus();
          } else {
            _closeSearch();
          }
        }
      },
      child: Scaffold(
        backgroundColor: t.bg,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: topPad + 14),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 14, 0),
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        const NoorLogo(),
                        const SizedBox(width: 10),
                        Expanded(child: _searchField(t)),
                        const SizedBox(width: 8),
                        NoorSearchButton(
                            open: _searching,
                            onTap: _searching ? _closeSearch : _openSearch),
                        const SizedBox(width: 8),
                        // Home: Settings. While searching: the result filters.
                        Builder(
                            builder: (b) => NoorSettingsButton(
                                label:
                                    _searching ? 'Search filters' : 'Settings',
                                onTap: () => _searching
                                    ? (() {
                                        _queryFocus.unfocus();
                                        showSearchFilters(context, anchor: b);
                                      })()
                                    : _openSettings())),
                      ],
                    ),
                  ),
                ),
                const NoorOfflinePill(),
                const SizedBox(height: 8),
                // Swipe down / pull down: Home sinks away and search drops in
                // from the top; closing search plays it in reverse.
                Expanded(
                  child: ClipRect(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 480),
                      reverseDuration: const Duration(milliseconds: 300),
                      // One after the other: the leaving page is gone in the
                      // first half of its time, the new one starts after it.
                      switchInCurve:
                          const Interval(0.3, 1, curve: Curves.easeOutCubic),
                      switchOutCurve:
                          const Interval(0.45, 1, curve: Curves.easeIn),
                      layoutBuilder: (cur, prev) => Stack(
                        alignment: Alignment.topCenter,
                        children: [...prev, if (cur != null) cur],
                      ),
                      transitionBuilder: (child, animation) {
                        final search = child.key == const ValueKey('search');
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                                    begin: search
                                        ? const Offset(0, -0.06)
                                        : const Offset(0, 0.12),
                                    end: Offset.zero)
                                .animate(animation),
                            child: search
                                ? child
                                : ScaleTransition(
                                    scale: Tween<double>(begin: 0.96, end: 1)
                                        .animate(animation),
                                    alignment: Alignment.topCenter,
                                    child: child),
                          ),
                        );
                      },
                      child: _searching
                          ? KeyedSubtree(
                              key: const ValueKey('search'),
                              child: SearchPanel(
                                  onRetry: _runSearch,
                                  query: _query,
                                  queryFocus: _queryFocus,
                                  onPick: (q) {
                                    _query.text = q;
                                    _runSearch();
                                  }))
                          : KeyedSubtree(
                              key: const ValueKey('home'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ── Slider ────────────────────────────────────────────────
                                  // The top of Home does not scroll, so it takes the swipe
                                  // down that opens search.
                                  // One wrapper in both modes, so starting to
                                  // arrange never rebuilds the card being held.
                                  PopScope(
                                    canPop: !_arranging,
                                    onPopInvokedWithResult: (didPop, _) {
                                      if (!didPop && _arranging) {
                                        _stopArranging();
                                      }
                                    },
                                    child: _slider(
                                        cats, index, activeWidth, current, t),
                                  ),

                                  // ── Songs (ring-wipe reveal when the card changes) ─────────
                                  Expanded(
                                    child: AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 1100),
                                      layoutBuilder: (cur, prev) => Stack(
                                        alignment: Alignment.topCenter,
                                        children: [
                                          ...prev,
                                          if (cur != null) cur
                                        ],
                                      ),
                                      transitionBuilder: (child, animation) {
                                        if (child.key != ValueKey(current.id))
                                          return child;
                                        return AnimatedBuilder(
                                          animation: animation,
                                          builder: (context, _) => ClipPath(
                                            clipper: RippleRingClipper(
                                                animation.value),
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: Container(
                                        key: ValueKey(current.id),
                                        color: t.bg,
                                        child: !libraryReady
                                            ? const SizedBox.expand()
                                            : current.songs.isEmpty
                                                ? GestureDetector(
                                                    behavior: HitTestBehavior
                                                        .translucent,
                                                    onVerticalDragEnd:
                                                        _onTopVerticalSwipe,
                                                    child: current.id ==
                                                                'music' &&
                                                            _needsPhoneAccess
                                                        ? const _PhoneAccess()
                                                        : const _EmptyList(),
                                                  )
                                                : NotificationListener<
                                                    ScrollNotification>(
                                                    onNotification:
                                                        _onListScroll,
                                                    child: ListView.builder(
                                                      // Room for the keyboard, so a card being
                                                      // named can scroll above it.
                                                      padding: EdgeInsets.fromLTRB(
                                                          0,
                                                          4,
                                                          0,
                                                          120 +
                                                              MediaQuery.viewInsetsOf(
                                                                      context)
                                                                  .bottom),
                                                      // Always pullable, even when the list is short.
                                                      physics:
                                                          const AlwaysScrollableScrollPhysics(
                                                              parent:
                                                                  BouncingScrollPhysics()),
                                                      itemCount: current
                                                              .songs.length +
                                                          (askPhone ? 1 : 0),
                                                      itemBuilder:
                                                          (context, i) {
                                                        if (askPhone) {
                                                          if (i == 0) {
                                                            return const _PhoneAccessPill();
                                                          }
                                                          i -= 1;
                                                        }
                                                        final song =
                                                            current.songs[i];
                                                        final targetId = ps
                                                                .pendingSong
                                                                ?.videoId ??
                                                            ps.song?.videoId;
                                                        final isCurrent =
                                                            song.videoId ==
                                                                targetId;
                                                        final loading = isCurrent &&
                                                            (ps.status ==
                                                                    NebulaPlayerStatus
                                                                        .loading ||
                                                                (ps.pendingSong !=
                                                                        null &&
                                                                    ps.status !=
                                                                        NebulaPlayerStatus
                                                                            .playing &&
                                                                    ps.status !=
                                                                        NebulaPlayerStatus
                                                                            .paused));
                                                        return NoorSongRow(
                                                          key: ValueKey(
                                                              '${current.id}_${song.videoId}'),
                                                          song: song,
                                                          current: isCurrent,
                                                          playing: isCurrent &&
                                                              ps.status ==
                                                                  NebulaPlayerStatus
                                                                      .playing,
                                                          loading: loading,
                                                          onTap: () => _play(
                                                              song,
                                                              current.songs),
                                                          onPlayPause: () =>
                                                              _play(
                                                                  song,
                                                                  current
                                                                      .songs),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
            // A soft fade under the bottom card, so it reads as floating
            // above the list.
            if (ps.displaySong != null || ref.watch(lastPlayedProvider) != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 150,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          t.bg.withOpacity(0),
                          t.bg.withOpacity(0.92),
                          t.bg
                        ],
                        stops: const [0, 0.55, 1],
                      ),
                    ),
                  ),
                ),
              ),
            const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
            // While a playlist is held: the delete area across the top.
            Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: _binZone(t, {for (final c in cats) c.id: c})),
            Positioned.fill(child: _fallingCard()),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String id) => switch (id) {
        'fav' => Icons.favorite_rounded,
        'hist' => Icons.history_rounded,
        'music' => Icons.download_done_rounded,
        _ => Icons.queue_music_rounded,
      };

  /// The search input grows out from the search icon to fill the space
  /// between "Noor" and the icon.
  Widget _searchField(NoorTheme t) => LayoutBuilder(
        builder: (context, box) => Align(
          alignment: Alignment.centerRight,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            width: _searching ? box.maxWidth : 0,
            height: 40,
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: BorderRadius.circular(20),
              border: _searching ? Border.all(color: t.ac, width: 0.8) : null,
            ),
            alignment: Alignment.centerLeft,
            child: _searching
                ? TextField(
                    controller: _query,
                    focusNode: _queryFocus,
                    onSubmitted: (_) => _runSearch(),
                    textInputAction: TextInputAction.search,
                    textAlignVertical: TextAlignVertical.center,
                    cursorColor: t.ac,
                    style: TextStyle(
                        color: t.ac,
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      hintText: 'Songs, artists…',
                      hintStyle:
                          TextStyle(color: t.mute, fontSize: 14, height: 1.2),
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  )
                : null,
          ),
        ),
      );
}

/// A slider card: one song's artwork filling a rounded card with a thin
/// accent border, and the card's icon in a small ring in the middle.
/// (The name is shown under the slider, between two thin lines.)
class _CategoryCard extends StatelessWidget {
  const _CategoryCard(
      {required this.icon, required this.artUrl, required this.active});
  final IconData icon;
  final String artUrl;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    final hasArt = artUrl.isNotEmpty;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(kNoorCardRadius),
        border: Border.all(color: t.ac, width: 1),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasArt) NoorArtwork(url: artUrl),
          if (hasArt)
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              color: Colors.black.withOpacity(active ? 0.10 : 0.30),
            ),
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              width: active ? 48 : 34,
              height: active ? 48 : 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.bg.withOpacity(hasArt ? 0.92 : 1),
                border: Border.all(color: t.ac, width: 0.8),
              ),
              child: Icon(icon, color: t.ac, size: active ? 22 : 16),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown in the list area when the open card has no songs: a "no song"
/// icon and one line of text over the faded Noor girl.
class _EmptyList extends StatelessWidget {
  const _EmptyList();

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        const NoorGirlWatermark(),
        Padding(
          padding: const EdgeInsets.only(bottom: 90),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.music_off_rounded, size: 40, color: t.ac),
                const SizedBox(height: 12),
                Text('No song available',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: t.ac,
                        fontSize: 17,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// My Music with nothing in it yet and no access to the phone's music: the
/// faded girl, a short line, and the button that asks for access.
class _PhoneAccess extends ConsumerWidget {
  const _PhoneAccess();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = NoorTheme.of(context);
    final blocked = ref.watch(localMusicProvider).access == LocalAccess.blocked;
    return Stack(
      fit: StackFit.expand,
      children: [
        const NoorGirlWatermark(),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 90),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.library_music_outlined, size: 40, color: t.ac),
                const SizedBox(height: 12),
                Text('Play the music on this phone',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: t.ac,
                        fontSize: 17,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                    blocked
                        ? 'Access was turned off. Allow "Music and audio" for Noor in settings.'
                        : 'Noor needs your permission to see your music files.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.mute, fontSize: 13)),
                const SizedBox(height: 18),
                const _PhoneAccessPill(big: true),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The thin-bordered button that asks for access to the phone's music (or
/// opens the app's settings once Android no longer shows the question).
class _PhoneAccessPill extends ConsumerWidget {
  const _PhoneAccessPill({this.big = false});
  final bool big;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = NoorTheme.of(context);
    final blocked = ref.watch(localMusicProvider).access == LocalAccess.blocked;
    final label = blocked
        ? 'Open settings'
        : (big ? 'Allow access' : 'Show music from this phone');
    return Padding(
      padding: big ? EdgeInsets.zero : const EdgeInsets.fromLTRB(14, 2, 14, 8),
      child: Center(
        child: Semantics(
          container: true,
          button: true,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              ref.read(localMusicProvider.notifier).requestAccess();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kNoorCardRadius),
                border: Border.all(color: t.ac, width: 0.8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.library_music_outlined, size: 16, color: t.ac),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                        color: t.ac,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A wormhole: spiral arms turning round a dark centre, in [color].
/// [strength] 0..1 is how vivid it is; [gulp] flares it while swallowing.
class _WormholePainter extends CustomPainter {
  _WormholePainter({
    required this.turn,
    required this.strength,
    required this.gulp,
    required this.color,
  });

  final double turn;
  final double strength;
  final double gulp;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 * (1 + 0.18 * gulp);
    // A soft glow under the arms.
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withOpacity(0.55 * strength),
            color.withOpacity(0.18 * strength),
            color.withOpacity(0),
          ], stops: const [
            0,
            0.55,
            1
          ]).createShader(Rect.fromCircle(center: c, radius: r)));
    // Spiral arms, each curling into the centre.
    final arm = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const arms = 4;
    for (var a = 0; a < arms; a++) {
      final path = Path();
      for (var i = 0; i <= 40; i++) {
        final k = i / 40; // 0 outside .. 1 centre
        final ang = turn * 2 * math.pi + a * 2 * math.pi / arms + k * 2.6;
        final rr = r * 0.95 * (1 - k);
        final p = c + Offset(math.cos(ang), math.sin(ang)) * rr;
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      arm
        ..strokeWidth = 1.6
        ..color = color.withOpacity((0.35 + 0.5 * strength).clamp(0.0, 1.0));
      canvas.drawPath(path, arm);
    }
    // The dark eye.
    canvas.drawCircle(
        c,
        r * (0.16 + 0.08 * gulp),
        Paint()
          ..color = const Color(0xFF2B1A12).withOpacity(0.85 * strength + 0.1));
  }

  @override
  bool shouldRepaint(_WormholePainter old) =>
      old.turn != turn ||
      old.strength != strength ||
      old.gulp != gulp ||
      old.color != color;
}
