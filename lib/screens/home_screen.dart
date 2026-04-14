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

// ── Custom Clipper: Flawless Concentric Ring Reveal (CodePen Replica) ──

class _RippleRingClipper extends CustomClipper<Path> {
  final double fraction;
  _RippleRingClipper(this.fraction);

  @override
  Path getClip(Size size) {
    if (fraction <= 0.0) return Path();
    if (fraction >= 1.0) return Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final center = Offset(size.width / 2, 0); // Top-center
    final double maxRadius = sqrt(size.width * size.width + size.height * size.height);
    
    // Exactly mimics the CodePen spacing and sizing
    const double ringSpacing = 80.0; 
    final int numRings = (maxRadius / ringSpacing).ceil() + 1;
    const double maxStroke = 85.0; // Slightly larger than spacing to ensure they merge

    List<List<double>> intervals = [];

    // 1. Mathematically calculate all expanding rings
    for (int i = 0; i < numRings; i++) {
      // Stagger the delay just like the CSS transition-delay
      final double delayFraction = i * (0.4 / numRings); 
      double progress = ((fraction - delayFraction) / 0.6).clamp(0.0, 1.0);
      progress = Curves.easeInOutCubic.transform(progress);

      if (progress > 0.0) {
        final double baseRadius = (i * ringSpacing) + 20.0;
        final double currentStroke = progress * maxStroke;

        final double outer = baseRadius + (currentStroke / 2);
        double inner = baseRadius - (currentStroke / 2);
        if (inner < 0) inner = 0.0;

        intervals.add([inner, outer]);
      }
    }

    // 2. Merge overlapping rings to prevent Impeller from crashing/skipping frames
    List<List<double>> merged = [];
    for (var interval in intervals) {
      if (merged.isEmpty) {
        merged.add(interval);
      } else {
        var last = merged.last;
        if (interval[0] <= last[1]) {
          last[1] = max(last[1], interval[1]); // Rings touch and merge!
        } else {
          merged.add(interval);
        }
      }
    }

    // 3. Draw the perfectly optimized path
    Path finalPath = Path()..fillType = PathFillType.evenOdd;
    for (var interval in merged) {
      finalPath.addOval(Rect.fromCircle(center: center, radius: interval[1])); // Outer edge
      if (interval[0] > 0) {
        finalPath.addOval(Rect.fromCircle(center: center, radius: interval[0])); // Inner edge creates the hole
      }
    }

    return finalPath;
  }

  @override
  bool shouldReclip(_RippleRingClipper old) => old.fraction != fraction;
}

// ── Screen Definition ────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  final void Function(int) onNavigate;
  const HomeScreen({super.key, required this.onNavigate});

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

    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F4F8); 
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final mutedCol = isDark ? Colors.white54 : const Color(0xFF8A9BB0);
    const accentCol = Color(0xFF4993FC);
    
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

    const double horizontalPadding = 40.0; 
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
          Positioned.fill(
            child: Center(
              child: Opacity(
                opacity: isDark ? 0.02 : 0.04, 
                child: Image.asset('assets/images/app_logo_final.png', width: screenWidth * 0.8, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: topPad + 10),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                child: Row(
                  children: [
                    Text('Nebula', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: textCol, letterSpacing: -0.5)),
                    const Spacer(),
                    _NeuBtn(icon: Icons.search_rounded, color: accentCol, bg: bg, isDark: isDark, size: 52, onTap: () => widget.onNavigate(1)),
                  ],
                ),
              ),

              SizedBox(
                height: 170, 
                child: categories.isEmpty 
                  ? Center(child: Text('Your library is empty', style: TextStyle(color: mutedCol)))
                  : GestureDetector(
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
                          padding: const EdgeInsets.symmetric(horizontal: 20),
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
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(isActive ? 32 : 24),
                                  color: isDark ? const Color(0xFF161B22) : Colors.grey.shade300,
                                  boxShadow: [
                                    if (isActive) BoxShadow(
                                      color: Colors.black.withOpacity(isDark ? 0.4 : 0.15),
                                      blurRadius: 15,
                                      offset: const Offset(0, 8)
                                    )
                                  ],
                                ),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: Opacity(
                                        opacity: isActive ? 1.0 : 0.4,
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
                                              Colors.black.withOpacity(isActive ? 0.8 : 0.6),
                                              Colors.transparent
                                            ],
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
                                            constraints: const BoxConstraints(minWidth: 48), 
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(item.icon, color: Colors.white, size: 24),
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
                                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)
                                                            ),
                                                            Text(item.subtitle, 
                                                              maxLines: 1, 
                                                              softWrap: false,
                                                              overflow: TextOverflow.fade,
                                                              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)
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
                            );
                          },
                        ),
                      ),
                    ),
              ),

              if (categories.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(25, 10, 20, 10),
                  child: Row(
                    children: [
                      Text(currentHeading, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textCol, letterSpacing: -0.5)),
                      const Spacer(),
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
                            clipper: _RippleRingClipper(animation.value),
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
                          child: Text('No songs found', style: TextStyle(color: mutedCol)),
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

                              return _CapsuleSongTile(
                                song: song,
                                isPlaying: isTargetSong, 
                                isLoading: isLoading,    
                                isActuallyPlayingAudio: isTargetSong && isPlayingState,
                                isDark: isDark,
                                onTap: () => _playSong(song, displaySongs),
                              );
                            },
                          ),
                        ),
                ),
              ),
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
    if (urls.isEmpty) return Container(color: Colors.grey[800]);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 5) return const SizedBox.shrink();

        Widget img(String url) => ClipRect(
          child: Transform.scale(
            scale: 1.35, 
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorWidget: (_, __, ___) => Container(color: Colors.grey[900], child: const Icon(Icons.music_note, color: Colors.white54)),
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

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM CAPSULE TILE
// ═══════════════════════════════════════════════════════════════════════════════
class _CapsuleSongTile extends StatelessWidget {
  final Song song;
  final bool isPlaying;
  final bool isLoading;
  final bool isActuallyPlayingAudio;
  final bool isDark;
  final VoidCallback onTap;

  const _CapsuleSongTile({
    required this.song,
    required this.isPlaying,
    required this.isLoading,
    required this.isActuallyPlayingAudio,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final mutedCol = isDark ? Colors.white54 : const Color(0xFF8A9BB0);
    const accentCol = Color(0xFF4993FC);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: isPlaying ? accentCol.withOpacity(0.08) : cardBg,
          borderRadius: BorderRadius.circular(36),
          border: isPlaying ? Border.all(color: accentCol.withOpacity(0.3), width: 1.5) : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 6),
            
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 3))]
              ),
              child: ClipOval(
                child: Transform.scale(
                  scale: 1.35, 
                  child: CachedNetworkImage(
                    imageUrl: song.thumbnailUrl,
                    fit: BoxFit.cover,
                    width: double.infinity, height: double.infinity,
                    errorWidget: (_, __, ___) => Container(color: Colors.grey[800], child: const Icon(Icons.music_note, color: Colors.white54, size: 18)),
                  ),
                ),
              ),
            ),
            
            const SizedBox(width: 14),
            
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: isPlaying ? accentCol : textCol)),
                  const SizedBox(height: 3),
                  Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: mutedCol, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.only(right: 18.0),
              child: isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: accentCol, strokeWidth: 2.5))
                  : isPlaying
                      ? Icon(isActuallyPlayingAudio ? Icons.pause_rounded : Icons.play_arrow_rounded, color: accentCol, size: 24)
                      : Icon(Icons.play_arrow_rounded, color: mutedCol.withOpacity(0.3), size: 24),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared UI ──────────────────────────────────────────────────────────────────
class _NeuBtn extends StatelessWidget {
  final IconData icon;
  final Color color, bg;
  final bool isDark;
  final VoidCallback onTap;
  final double size;
  
  const _NeuBtn({
    required this.icon, required this.color, required this.bg, required this.isDark, required this.onTap, required this.size,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: isDark ? Colors.black54 : Colors.grey[300]!, blurRadius: 10, offset: const Offset(5, 5)),
                BoxShadow(color: isDark ? Colors.white.withOpacity(0.05) : Colors.white, blurRadius: 10, offset: const Offset(-5, -5)),
              ]),
          child: Icon(icon, color: color, size: size * 0.5),
        ),
      );
}