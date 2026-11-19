import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../providers/last_played_provider.dart';
import '../providers/local_music_provider.dart';
import '../providers/theme_provider.dart';
import 'mini_player.dart';
import 'search_screen.dart';
import '../providers/search_provider.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_artwork.dart';
import '../theme/noor_song_card.dart';
import '../theme/ripple_ring_clipper.dart';
import '../theme/noor_widgets.dart';
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

/// The Home slider: My Favorites, My History and My Music are always there
/// (even when empty); every playlist follows.
List<HomeCategory> homeCategories({
  required List<Song> liked,
  required List<Song> history,
  required List<Song> onDevice,
  required List<Playlist> playlists,
}) {
  final seen = <String>{};
  final distinctHistory = history.where((s) => seen.add(s.videoId)).toList();
  return [
    HomeCategory('fav', 'My Favorites', liked),
    HomeCategory('hist', 'My History', distinctHistory),
    HomeCategory('music', 'My Music', onDevice),
    for (final p in playlists) HomeCategory(p.id, p.name, p.songs),
  ];
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _selectedId;

  /// Picks which song's artwork fills each slider card; new every launch.
  final int _artSeed = Random().nextInt(1 << 30);

  bool _searching = false;
  final _query = TextEditingController();
  final _queryFocus = FocusNode();

  @override
  void dispose() {
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
    if ((d.primaryVelocity ?? 0) > 300) _openSearch();
  }

  /// Pulling the song list down past its top opens search.
  bool _onListScroll(ScrollNotification n) {
    if (n is ScrollUpdateNotification &&
        n.dragDetails != null &&
        n.metrics.pixels < -80 &&
        !_pullFired &&
        !_searching) {
      _pullFired = true;
      _openSearch();
    } else if (n is ScrollEndNotification) {
      _pullFired = false;
    }
    return false;
  }

  /// Long press on a playlist card: offer to delete the playlist.
  Future<void> _confirmDeletePlaylist(HomeCategory c) async {
    if (!ref.read(playlistProvider).any((p) => p.id == c.id)) return;
    HapticFeedback.mediumImpact();
    final t = NoorTheme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.bg,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: t.ac, width: 0.8)),
        title: Text('Delete "${c.title}"?',
            style: TextStyle(color: t.ac, fontWeight: FontWeight.w700)),
        content: Text(
            'The playlist goes away. Its songs stay in your favorites and history.',
            style: TextStyle(color: t.mute)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Keep', style: TextStyle(color: t.mute))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete',
                  style: TextStyle(color: t.ac, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(playlistProvider.notifier).delete(c.id);
      if (mounted && _selectedId == c.id) setState(() => _selectedId = null);
    }
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
        playlists: playlists);

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
                        const NoorWordmark(height: 30),
                        const SizedBox(width: 12),
                        Expanded(child: _searchField(t)),
                        const SizedBox(width: 8),
                        NoorSearchButton(
                            open: _searching,
                            onTap: _searching ? _closeSearch : _openSearch),
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
                                  GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onVerticalDragEnd: _onTopVerticalSwipe,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          height: 168,
                                          child: GestureDetector(
                                            onHorizontalDragEnd: (d) {
                                              final v = d.primaryVelocity ?? 0;
                                              if (v < -200) {
                                                if (index < cats.length - 1) {
                                                  _select(cats[index + 1].id);
                                                }
                                              } else if (v > 200) {
                                                if (index > 0) {
                                                  _select(cats[index - 1].id);
                                                } else {
                                                  _openSearch(); // before the first card
                                                }
                                              }
                                            },
                                            child: ListView.builder(
                                              scrollDirection: Axis.horizontal,
                                              physics:
                                                  const NeverScrollableScrollPhysics(),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12),
                                              itemCount: cats.length,
                                              itemBuilder: (context, i) {
                                                final active = i == index;
                                                final adjacent =
                                                    (i - index).abs() == 1;
                                                return GestureDetector(
                                                  onTap: () =>
                                                      _select(cats[i].id),
                                                  onLongPress: () =>
                                                      _confirmDeletePlaylist(
                                                          cats[i]),
                                                  child: AnimatedContainer(
                                                    duration: const Duration(
                                                        milliseconds: 500),
                                                    curve: Curves.easeOutCubic,
                                                    width: active
                                                        ? activeWidth
                                                        : (adjacent ? 48 : 0),
                                                    margin: EdgeInsets.symmetric(
                                                        horizontal:
                                                            (active || adjacent)
                                                                ? 6
                                                                : 0,
                                                        vertical: 8),
                                                    child: (active || adjacent)
                                                        ? _CategoryCard(
                                                            icon: _iconFor(
                                                                cats[i].id),
                                                            artUrl: _artFor(
                                                                cats[i]),
                                                            active: active)
                                                        : const SizedBox
                                                            .shrink(),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                        NoorLinedLabel(current.title),
                                        const SizedBox(height: 8),
                                      ],
                                    ),
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
