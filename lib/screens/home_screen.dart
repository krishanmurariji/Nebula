import 'dart:math';
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

  void _startArranging(List<HomeCategory> cats) {
    HapticFeedback.mediumImpact();
    setState(() {
      _arranging = true;
      _arrangeOrder = [for (final c in cats) c.id];
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

  void _dragEnded() {
    setState(() => _draggingId = null);
    ref.read(homeOrderProvider.notifier).set(_arrangeOrder);
  }

  // ── The bin at the top of the screen ──────────────────────────────────

  /// Drop animation: the lid opens, the card falls in, the lid closes.
  late final AnimationController _binDrop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 950));
  HomeCategory? _falling; // the playlist card dropping into the bin
  Offset _fallFrom = Offset.zero; // where it was let go (global)

  /// Where the bin sits (global), for the falling card to aim at.
  Offset _binCentre(BuildContext context) => Offset(
      MediaQuery.sizeOf(context).width / 2,
      MediaQuery.paddingOf(context).top + 34);

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
      if (_selectedId == c.id) _selectedId = null;
    });
    _binDrop.value = 0;
    ref.read(homeOrderProvider.notifier).set(left);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text('"${c.title}" deleted. Its songs stay in your history.'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      action: removed == null
          ? null
          : SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                await ref.read(playlistProvider.notifier).restore(removed, at);
                if (!mounted) return;
                setState(() => _arrangeOrder = orderBefore);
                ref.read(homeOrderProvider.notifier).set(orderBefore);
              },
            ),
    ));
  }

  /// The delete area across the top of the screen, shown while a playlist
  /// is held: faint at first, red when the card is over it.
  Widget _binZone(NoorTheme t, Map<String, HomeCategory> byId) {
    final show =
        (_draggingId != null && !kFixedHomeCards.contains(_draggingId)) ||
            _falling != null;
    const red = Color(0xFFD64545);
    final top = MediaQuery.paddingOf(context).top;
    return IgnorePointer(
      ignoring: !show,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        offset: show ? Offset.zero : const Offset(0, -1),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
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
                duration: const Duration(milliseconds: 180),
                height: top + 92,
                padding: EdgeInsets.only(top: top + 8),
                decoration: BoxDecoration(
                  color: Color.lerp(t.bg, red, hot ? 0.16 : 0.05),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(28)),
                  border: Border(
                      bottom: BorderSide(
                          color: red.withOpacity(hot ? 0.75 : 0.25), width: 1)),
                ),
                child: Column(children: [
                  AnimatedBuilder(
                    animation: _binDrop,
                    builder: (_, __) {
                      // Lid: ajar while hovering; wide open, then shut,
                      // while a card drops in.
                      final v = _binDrop.value;
                      final drop = _falling == null
                          ? 0.0
                          : v < 0.25
                              ? v / 0.25
                              : v < 0.68
                                  ? 1.0
                                  : (1 - (v - 0.68) / 0.24).clamp(0.0, 1.0);
                      final lid = _falling != null ? drop : (hot ? 0.45 : 0.0);
                      return SizedBox(
                        width: 44,
                        height: 50,
                        child: CustomPaint(
                            painter: _BinPainter(
                                lid: lid,
                                color: red.withOpacity(hot ? 1 : 0.5))),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                      hot
                          ? 'Let go to delete'
                          : 'Drag here to delete the playlist',
                      style: TextStyle(
                          color: red.withOpacity(hot ? 1 : 0.6),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ]),
              );
            },
          ),
        ),
      ),
    );
  }

  /// The card falling into the bin (drawn above everything).
  Widget _fallingCard() {
    final c = _falling;
    if (c == null) return const SizedBox.shrink();
    final to = _binCentre(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _binDrop,
        builder: (_, __) {
          // Falls between 15% and 70% of the animation.
          final f = Curves.easeInCubic
              .transform(((_binDrop.value - 0.15) / 0.55).clamp(0.0, 1.0));
          if (f >= 1) return const SizedBox.shrink();
          final pos = Offset.lerp(_fallFrom, to + const Offset(0, 6), f)!;
          final scale = 1 - 0.8 * f;
          return Stack(children: [
            Positioned(
              left: pos.dx - 24,
              top: pos.dy - 76,
              child: Opacity(
                opacity: (1 - f * 0.6).clamp(0.0, 1.0),
                child: Transform.rotate(
                  angle: 0.5 * f,
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.bottomCenter,
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
          onDragStarted: () {
            if (!_arranging) _startArranging(cats);
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
          child: GestureDetector(
            onTap: _arranging ? null : () => _select(c.id),
            child: box,
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
                      mainAxisAlignment: _arranging
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.start,
                      children: [for (final c in shown) card(c)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _arranging
                ? Padding(
                    key: const ValueKey('arranging'),
                    padding: const EdgeInsets.fromLTRB(20, 0, 14, 0),
                    child: SizedBox(
                      height: 30,
                      child: Row(children: [
                        Expanded(
                          child: Text('Hold a card and drag it to a new place',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: t.mute, fontSize: 12.5)),
                        ),
                        TextButton(
                          onPressed: _stopArranging,
                          style: TextButton.styleFrom(
                            foregroundColor: t.ac,
                            minimumSize: const Size(0, 30),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: t.ac, width: 0.8)),
                          ),
                          child: const Text('Done',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ),
                  )
                : SizedBox(
                    key: const ValueKey('title'),
                    height: 30,
                    child: Center(child: NoorLinedLabel(current.title))),
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
                                  if (_arranging)
                                    PopScope(
                                      canPop: false,
                                      onPopInvokedWithResult: (didPop, _) {
                                        if (!didPop) _stopArranging();
                                      },
                                      child: _slider(
                                          cats, index, activeWidth, current, t),
                                    )
                                  else
                                    _slider(
                                        cats, index, activeWidth, current, t),

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

/// A bin seen from the front: a tapered body with ribs and a lid hinged on
/// its right end. [lid] = 0 shut, 1 swung fully open.
class _BinPainter extends CustomPainter {
  _BinPainter({required this.lid, required this.color});
  final double lid;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Body.
    final top = h * 0.36, bottom = h * 0.96;
    final body = Path()
      ..moveTo(w * 0.18, top)
      ..lineTo(w * 0.26, bottom)
      ..lineTo(w * 0.74, bottom)
      ..lineTo(w * 0.82, top);
    canvas.drawPath(body, line);
    for (final x in [0.4, 0.5, 0.6]) {
      canvas.drawLine(Offset(w * x, top + h * 0.12),
          Offset(w * (0.5 + (x - 0.5) * 0.9), bottom - h * 0.1), line);
    }
    // Lid, turning about its right end.
    final hinge = Offset(w * 0.88, h * 0.28);
    canvas.save();
    canvas.translate(hinge.dx, hinge.dy);
    canvas.rotate(-1.05 * lid);
    canvas.translate(-hinge.dx, -hinge.dy);
    canvas.drawLine(Offset(w * 0.1, h * 0.28), hinge, line);
    final handle = Path()
      ..moveTo(w * 0.38, h * 0.28)
      ..lineTo(w * 0.42, h * 0.16)
      ..lineTo(w * 0.58, h * 0.16)
      ..lineTo(w * 0.62, h * 0.28);
    canvas.drawPath(handle, line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BinPainter old) => old.lid != lid || old.color != color;
}
