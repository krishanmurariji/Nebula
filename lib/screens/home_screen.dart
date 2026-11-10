import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../providers/theme_provider.dart';
import 'mini_player.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_album_tile.dart';
import '../theme/ripple_ring_clipper.dart';
import 'search_screen.dart';
import '../theme/noor_widgets.dart';

// ── Models ───────────────────────────────────────────────────────────────────

class _CategoryItem {
  final String id;
  final String title;
  final String subtitle;
  final List<String> imageUrls;
  final IconData icon;

  _CategoryItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrls,
    required this.icon,
  });
}

// ── Screen Definition ────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _selectedId = 'recent';
  int _currentIndex = 0;

  void _onCategoryTap(int index, String id) {
    if (_currentIndex == index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
      _selectedId = id;
    });
  }

  /// Opens the search page with the same ring wipe the list uses.
  void _openSearch() {
    HapticFeedback.selectionClick();
    Navigator.of(context)
        .push(NoorRippleRoute<void>(builder: (_) => const SearchScreen()));
  }

  void _toggleLike(Song song) {
    HapticFeedback.mediumImpact();
    ref.read(likedProvider.notifier).toggle(song);
  }

  void _playSong(Song song, List<Song> queue) {
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
    final playlists = ref.watch(playlistProvider);
    final history = ref.watch(historyProvider);
    final likedSongs = ref.watch(likedSongsProvider);
    final playerState = ref.watch(playerProvider);
    final libraryReady = ref.watch(libraryReadyProvider).valueOrNull ?? false;

    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final t = NoorTheme.byMode(isDark);
    final bg = t.bg;
    final textCol = t.ac;
    final mutedCol = t.mute;
    
    final topPad = MediaQuery.of(context).padding.top;
    final screenWidth = MediaQuery.of(context).size.width;

    final seen = <String>{};
    final distinctHistory = history.where((s) => seen.add(s.videoId)).toList();

    final List<_CategoryItem> categories = [];
    List<String> getUrls(List<Song> songs) => songs.take(4).map((e) => e.thumbnailUrl).toList();

    if (distinctHistory.isNotEmpty) {
      categories.add(_CategoryItem(id: 'recent', title: 'Recently Played', subtitle: '${distinctHistory.length} tracks', icon: Icons.history_rounded, imageUrls: getUrls(distinctHistory)));
    }
    if (likedSongs.isNotEmpty) {
      categories.add(_CategoryItem(id: 'liked', title: 'Liked Songs', subtitle: '${likedSongs.length} favorites', icon: Icons.favorite_rounded, imageUrls: getUrls(likedSongs)));
    }
    for (var p in playlists) {
      if (p.songs.isNotEmpty) {
        categories.add(_CategoryItem(id: p.id, title: p.name, subtitle: '${p.songs.length} tracks', icon: Icons.queue_music_rounded, imageUrls: getUrls(p.songs)));
      }
    }

    if (categories.isNotEmpty && !categories.any((c) => c.id == _selectedId)) {
      _selectedId = categories.first.id;
      _currentIndex = 0;
    }

    int currentVisibleCount = 1;
    if (_currentIndex > 0) currentVisibleCount++;
    if (_currentIndex < categories.length - 1) currentVisibleCount++;

    const double horizontalPadding = 24.0; 
    final double totalMargins = currentVisibleCount * 12.0; 
    final double totalAdjacentWidth = (currentVisibleCount - 1) * 48.0; 
    final double activeWidth = screenWidth - horizontalPadding - totalMargins - totalAdjacentWidth - 1.0; 

    List<Song> displaySongs = [];
    if (categories.isNotEmpty) {
      if (_selectedId == 'recent') displaySongs = distinctHistory;
      else if (_selectedId == 'liked') displaySongs = likedSongs;
      else displaySongs = playlists.firstWhere((p) => p.id == _selectedId, orElse: () => playlists.first).songs;
    }

    final String currentHeading = categories.isNotEmpty 
        ? categories.firstWhere((c) => c.id == _selectedId, orElse: () => categories.first).title
        : 'No Music Found';

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          const Positioned(top: 0, left: 0, right: 0, child: NoorBackdrop()),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: topPad + 10),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    Expanded(child: NoorSearchBarButton(onTap: _openSearch)),
                  ],
                ),
              ),

              if (categories.isEmpty)
                Expanded(
                  // Say "nothing here yet" only once the saved library has
                  // really been read; until then show nothing at all.
                  child: libraryReady
                      ? const NoorEmptyState(
                          message: 'Nothing here yet',
                          hint: 'Search for a song and it will appear here.',
                        )
                      : const SizedBox.shrink(),
                )
              else ...[
              SizedBox(
                height: 170, 
                child: GestureDetector(
                      onHorizontalDragEnd: (details) {
                        const threshold = 200.0;
                        if (details.primaryVelocity! < -threshold) { 
                          if (_currentIndex < categories.length - 1) {
                            _onCategoryTap(_currentIndex + 1, categories[_currentIndex + 1].id);
                          }
                        } else if (details.primaryVelocity! > threshold) {
                          if (_currentIndex > 0) {
                            _onCategoryTap(_currentIndex - 1, categories[_currentIndex - 1].id);
                          }
                        }
                      },
                      child: Container(
                        color: Colors.transparent, 
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: categories.length,
                          itemBuilder: (context, index) {
                            final item = categories[index];
                            final bool isActive = index == _currentIndex;
                            final bool isAdjacent = index == _currentIndex - 1 || index == _currentIndex + 1;
                            
                            double width;
                            double margin = 6.0;
                            
                            if (isActive) {
                              width = activeWidth;
                            } else if (isAdjacent) {
                              width = 48.0; 
                            } else {
                              width = 0.0; 
                              margin = 0.0; 
                            }

                            return GestureDetector(
                              onTap: () => _onCategoryTap(index, item.id),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 500),
                                curve: Curves.easeOutCubic,
                                width: width,
                                margin: EdgeInsets.symmetric(horizontal: margin, vertical: 10),
                                padding: EdgeInsets.all((isActive || isAdjacent) ? 2 : 0),
                                // Outer fine ring (the "second outline")
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(isActive ? 30 : 26),
                                  border: (isActive || isAdjacent)
                                      ? Border.all(color: t.faint, width: 1)
                                      : null,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 500),
                                  curve: Curves.easeOutCubic,
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    color: t.tint(0.3),
                                    borderRadius:
                                        BorderRadius.circular(isActive ? 28 : 24),
                                    border: (isActive || isAdjacent)
                                        ? Border.all(color: t.ac, width: 1)
                                        : null,
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: Opacity(
                                          opacity: isActive ? 1.0 : 0.55,
                                          child: _CollageCover(urls: item.imageUrls),
                                        ),
                                      ),
                                      Positioned.fill(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.bottomCenter,
                                              end: Alignment.topCenter,
                                              colors: [
                                                t.ac.withOpacity(isActive ? 0.92 : 0.7),
                                                t.ac.withOpacity(0.0),
                                              ],
                                              stops: const [0.0, 0.75],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned.fill(
                                        child: Center(
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            physics: const NeverScrollableScrollPhysics(),
                                            child: Container(
                                              constraints: const BoxConstraints(minWidth: 40),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Container(
                                                    width: 36,
                                                    height: 36,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: t.bg,
                                                      border: Border.all(color: t.ac, width: 1),
                                                    ),
                                                    child: Icon(item.icon, color: t.ac, size: 18),
                                                  ),
                                                  ClipRect(
                                                    child: AnimatedAlign(
                                                      duration: const Duration(milliseconds: 400),
                                                      curve: Curves.easeOutCubic,
                                                      alignment: Alignment.centerLeft,
                                                      widthFactor: isActive ? 1.0 : 0.0,
                                                      child: AnimatedOpacity(
                                                        duration: const Duration(milliseconds: 300),
                                                        opacity: isActive ? 1.0 : 0.0,
                                                        child: Padding(
                                                          padding: const EdgeInsets.only(left: 12.0, right: 8.0),
                                                          child: Column(
                                                            mainAxisSize: MainAxisSize.min,
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Text(item.title,
                                                                maxLines: 1,
                                                                softWrap: false,
                                                                overflow: TextOverflow.fade,
                                                                style: TextStyle(color: t.bg, fontWeight: FontWeight.w700, fontSize: 16)
                                                              ),
                                                              Text(item.subtitle,
                                                                maxLines: 1,
                                                                softWrap: false,
                                                                overflow: TextOverflow.fade,
                                                                style: TextStyle(color: t.bg.withOpacity(0.8), fontSize: 12)
                                                              ),
                                                            ],
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
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
              ),

              if (categories.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(currentHeading,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: noorSerif(textCol, size: 22, height: 1.0)),
                            ),
                            const SizedBox(width: 10),
                            const NoorDivider(width: 36),
                          ],
                        ),
                      ),
                      Text('${displaySongs.length} tracks', style: TextStyle(color: mutedCol, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),

              // ── Lower Section: Vertical Ripple Reveal List ────────────────
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 1100), 
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      alignment: Alignment.topCenter,
                      children: <Widget>[
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    );
                  },
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    final isIncoming = child.key == ValueKey(_selectedId);

                    if (isIncoming) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) {
                          return ClipPath(
                            clipper: RippleRingClipper(animation.value),
                            child: child,
                          );
                        },
                      );
                    } else {
                      // We don't fade the old list, it sits perfectly still while the rings wipe over it!
                      return child;
                    }
                  },
                  child: displaySongs.isEmpty
                      ? Container( 
                          key: const ValueKey('empty'), 
                          color: bg, // ── FIX: Solid Background for clean wiping ──
                          alignment: Alignment.center,
                          child: const NoorEmptyState(message: 'No songs here yet', hint: 'Play something and it will show up.'),
                        )
                      : Container(
                          key: ValueKey(_selectedId), 
                          color: bg, // ── FIX: Solid Background ensures the old list is completely hidden ──
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(0, 0, 0, 120), 
                            physics: const BouncingScrollPhysics(),
                            itemCount: displaySongs.length,
                            itemBuilder: (context, index) {
                              final song = displaySongs[index];
                              
                              final targetSongId = playerState.pendingSong?.videoId ?? playerState.song?.videoId;
                              final isTargetSong = song.videoId == targetSongId;
                              final isPlayingState = playerState.status == NebulaPlayerStatus.playing;
                              
                              final isLoading = isTargetSong && 
                                 (playerState.status == NebulaPlayerStatus.loading || 
                                 (playerState.pendingSong != null && playerState.status != NebulaPlayerStatus.playing && playerState.status != NebulaPlayerStatus.paused));

                              return NoorAlbumTile(
                                thumbnailUrl: song.thumbnailUrl,
                                title: song.title,
                                channel: song.artist,
                                liked: likedSongs.any((l) => l.videoId == song.videoId),
                                selected: isTargetSong,
                                loading: isLoading,
                                playing: isTargetSong && isPlayingState,
                                onPlay: () => _playSong(song, displaySongs),
                                onToggleLike: () => _toggleLike(song),
                              );
                            },
                          ),
                        ),
                ),
              ),
              ],
            ],
          ),

          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COLLAGE BACKGROUND WIDGET
// ═══════════════════════════════════════════════════════════════════════════════
class _CollageCover extends StatelessWidget {
  final List<String> urls;
  const _CollageCover({required this.urls});

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return Container(color: NoorTheme.of(context).tint(0.35));

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 5) return const SizedBox.shrink();

        final tl = NoorTheme.of(context);
        Widget img(String url) => url.isEmpty
          ? Container(color: tl.tint(0.35))
          : ClipRect(
          child: Transform.scale(
            scale: 1.35, 
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorWidget: (_, __, ___) => Container(color: tl.tint(0.35), child: Icon(Icons.music_note, color: tl.bg)),
            ),
          ),
        );

        if (urls.length == 1) return img(urls[0]);
        
        if (urls.length == 2) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: img(urls[0])), const SizedBox(width: 2), Expanded(child: img(urls[1]))],
          );
        }
        
        if (urls.length == 3) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: img(urls[0])),
              const SizedBox(width: 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [Expanded(child: img(urls[1])), const SizedBox(height: 2), Expanded(child: img(urls[2]))],
                ),
              )
            ],
          );
        }
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(child: img(urls[0])), const SizedBox(width: 2), Expanded(child: img(urls[1]))],
              ),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(child: img(urls[2])), const SizedBox(width: 2), Expanded(child: img(urls[3]))],
              ),
            ),
          ],
        );
      }
    );
  }
}
