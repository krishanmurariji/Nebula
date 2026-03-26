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

// Helper class to easily map our top categories
class _CategoryItem {
  final String id;
  final String title;
  final String subtitle;
  final String? imageUrl;

  _CategoryItem({required this.id, required this.title, required this.subtitle, this.imageUrl});
}

class HomeScreen extends ConsumerStatefulWidget {
  final void Function(int) onNavigate;
  const HomeScreen({super.key, required this.onNavigate});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late PageController _pageController;
  final double _viewportFraction = 0.115;

  late PageController _topPageController;
  final double _topViewportFraction = 0.50; 

  String _selectedId = 'recent';
  bool _showPlaylists = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: _viewportFraction);
    _pageController.addListener(_onScroll);
    _topPageController = PageController(viewportFraction: _topViewportFraction);
  }

  @override
  void dispose() {
    _pageController.removeListener(_onScroll);
    _pageController.dispose();
    _topPageController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_pageController.position.haveDimensions) return;
    final page = _pageController.page ?? 0;
    
    if (page > 0.6 && _showPlaylists) {
      setState(() => _showPlaylists = false);
    } else if (page <= 0.6 && !_showPlaylists) {
      setState(() => _showPlaylists = true);
    }
  }

  void _handleTap(Song song, int index, bool isCenter, List<Song> queue) {
    if (isCenter) {
      HapticFeedback.lightImpact();
      final playerNotifier = ref.read(playerProvider.notifier);
      final ps = ref.read(playerProvider);
      
      if (ps.song?.videoId == song.videoId) {
        playerNotifier.togglePlay();
      } else {
        playerNotifier.playSong(song, queue: queue);
      }
    } else {
      HapticFeedback.selectionClick();
      _pageController.animateToPage(
        index, 
        duration: const Duration(milliseconds: 400), 
        curve: Curves.easeOutBack
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistProvider);
    final history = ref.watch(historyProvider);
    final likedSongs = ref.watch(likedSongsProvider);
    final playerState = ref.watch(playerProvider);

    final seen = <String>{};
    final distinctHistory = history.where((s) => seen.add(s.videoId)).toList();

    if (_selectedId != 'recent' && _selectedId != 'liked' && !playlists.any((p) => p.id == _selectedId)) {
      _selectedId = 'recent';
      if (_topPageController.hasClients) _topPageController.jumpToPage(0);
    }

    final List<Song> displaySongs;
    if (_selectedId == 'recent') {
      displaySongs = distinctHistory;
    } else if (_selectedId == 'liked') {
      displaySongs = likedSongs;
    } else {
      displaySongs = playlists.firstWhere((p) => p.id == _selectedId, orElse: () => playlists.first).songs;
    }

    final List<_CategoryItem> categories = [
      _CategoryItem(id: 'recent', title: 'History', subtitle: '${distinctHistory.length} songs', imageUrl: distinctHistory.firstOrNull?.thumbnailUrl),
      _CategoryItem(id: 'liked', title: 'Liked', subtitle: '${likedSongs.length} songs', imageUrl: likedSongs.firstOrNull?.thumbnailUrl),
      ...playlists.map((p) => _CategoryItem(id: p.id, title: p.name, subtitle: '${p.songs.length} songs', imageUrl: p.songs.firstOrNull?.thumbnailUrl)),
    ];

    final String currentHeading = categories.firstWhere((c) => c.id == _selectedId, orElse: () => categories.first).title;

    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    
    // UPDATED COLORS to match the Search & Player Screens exactly
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F4F8); 
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final mutedCol = isDark ? Colors.white54 : const Color(0xFF8A9BB0);
    final cleanPillBg = isDark ? const Color(0xFF161B22) : Colors.white;
    
    final topPad = MediaQuery.of(context).padding.top;
    final screenSize = MediaQuery.of(context).size;
    
    const double filterSectionHeight = 200.0; 
    const accentCol = Color(0xFF4993FC);

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          // ── 0. Big Background App Logo Watermark ─────────────────────────────
          Positioned.fill(
            child: Center(
              child: Opacity(
                opacity: isDark ? 0.03 : 0.05, 
                child: Image.asset(
                  'assets/images/app_logo_final.png',
                  width: screenSize.width * 0.85, 
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),
            ),
          ),

          // ── 1. Curved Vertical List (Songs) ──────────────────────────────────
          Positioned.fill(
            child: displaySongs.isEmpty
                ? Center(child: Text('Empty list', style: TextStyle(color: mutedCol)))
                : AnimatedBuilder(
                    animation: _pageController,
                    builder: (context, child) {
                      return PageView.builder(
                        controller: _pageController,
                        scrollDirection: Axis.vertical,
                        physics: const BouncingScrollPhysics(),
                        itemCount: displaySongs.length,
                        itemBuilder: (context, index) {
                          double page = _pageController.position.haveDimensions ? _pageController.page! : 0.0;
                          double delta = index - page;

                          double curveDx = (delta * delta) * 25.0; 
                          double scale = (1.0 - (delta.abs() * 0.05)).clamp(0.75, 1.0);
                          double opacity = (1.0 - (delta.abs() * 0.25)).clamp(0.1, 1.0);
                          double activeOpacity = (1.0 - (delta.abs() * 2.5)).clamp(0.0, 1.0);
                          bool isCenter = delta.abs() < 0.4;

                          final song = displaySongs[index];
                          final isCurrentSong = song.videoId == playerState.song?.videoId;
                          final isPlaying = playerState.status == NebulaPlayerStatus.playing;
                          
                          IconData actionIcon = Icons.play_arrow_rounded;
                          if (isCurrentSong) {
                            actionIcon = isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;
                          }

                          return GestureDetector(
                            onTap: () => _handleTap(song, index, isCenter, displaySongs),
                            behavior: HitTestBehavior.opaque,
                            child: Transform.translate(
                              offset: Offset(curveDx, 0),
                              child: Transform.scale(
                                scale: scale,
                                child: Opacity(
                                  opacity: opacity,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 25, vertical: 0),
                                    child: Stack(
                                      alignment: Alignment.centerLeft,
                                      children: [
                                        Opacity(
                                          opacity: activeOpacity,
                                          child: Container(
                                            height: 76,
                                            decoration: BoxDecoration(
                                              color: cleanPillBg,
                                              borderRadius: BorderRadius.circular(40),
                                              boxShadow: [
                                                BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.06), blurRadius: 20, offset: const Offset(0, 8))
                                              ],
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                          child: Row(
                                            children: [
                                              _buildListArt(song.thumbnailUrl),
                                              const SizedBox(width: 15),
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(color: isCurrentSong ? accentCol : textCol, fontWeight: FontWeight.bold, fontSize: 16)),
                                                    Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(color: mutedCol, fontSize: 12)),
                                                  ],
                                                ),
                                              ),
                                              if (isCenter)
                                                AnimatedContainer(
                                                  duration: const Duration(milliseconds: 300),
                                                  width: 44, height: 44,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: accentCol,
                                                    boxShadow: [BoxShadow(color: accentCol.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
                                                  ),
                                                  child: Icon(actionIcon, color: Colors.white, size: 24),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),

          // ── 2. UI Overlay: Header & Dynamic Top Carousel ─────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: topPad + 10, color: bg),
                Container(
                  color: bg,
                  padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                  child: Row(
                    children: [
                      Text('Explore', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: textCol, letterSpacing: -0.5)),
                      const Spacer(),
                      _NeuBtn(
                        icon: Icons.search_rounded,
                        color: const Color(0xFF4993FC), 
                        bg: bg,
                        isDark: isDark,
                        size: 52, 
                        onTap: () => widget.onNavigate(1),
                      ),
                    ],
                  ),
                ),
                
                ClipRect(
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    heightFactor: _showPlaylists ? 1.0 : 0.0,
                    child: Container(
                      height: filterSectionHeight,
                      color: bg,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── RECORD SLEEVE CAROUSEL ──
                          Expanded(
                            child: PageView.builder(
                              controller: _topPageController,
                              physics: const BouncingScrollPhysics(),
                              onPageChanged: (index) {
                                final selected = categories[index];
                                setState(() => _selectedId = selected.id);
                                if (_pageController.hasClients) _pageController.jumpToPage(0);
                                HapticFeedback.selectionClick();
                              },
                              itemCount: categories.length,
                              itemBuilder: (context, index) {
                                return AnimatedBuilder(
                                  animation: _topPageController,
                                  builder: (context, child) {
                                    double page = _topPageController.position.haveDimensions ? _topPageController.page! : 0.0;
                                    double delta = (index - page).clamp(-1.0, 1.0);
                                    
                                    double scale = 1.0 - (delta.abs() * 0.18); 
                                    
                                    return Transform.scale(
                                      scale: scale,
                                      child: GestureDetector(
                                        onTap: () {
                                          _topPageController.animateToPage(index, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
                                        },
                                        child: Center(
                                          child: _buildSleeveCard(categories[index], isDark, textCol, mutedCol, bg),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          
                          // ── DYNAMIC HEADING ──
                          Padding(
                            padding: const EdgeInsets.fromLTRB(25, 0, 20, 15),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: Text(
                                currentHeading,
                                key: ValueKey<String>(currentHeading),
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textCol, letterSpacing: -0.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Mini Player ──────────────────────────────────────────────────
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
        ],
      ),
    );
  }

  // ── Helper Widgets ───────────────────────────────────────────────────────

  Widget _buildListArt(String url) {
    return Container(
      width: 55, height: 55,
      decoration: BoxDecoration(
        shape: BoxShape.circle, 
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: ClipOval(
        child: Transform.scale(
          scale: 1.35, 
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(color: Colors.grey[800], child: const Icon(Icons.music_note, color: Colors.white)),
          ),
        ),
      ),
    );
  }

  Widget _buildSleeveCard(_CategoryItem item, bool isDark, Color textCol, Color mutedCol, Color appBg) {
    final bool isSel = _selectedId == item.id;
    
    const double sleeveSize = 125.0; 
    const double diskSize = 115.0;   
    const double totalWidth = 180.0; 

    return SizedBox(
      width: totalWidth,
      height: sleeveSize,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // 1. Vinyl Record (On Bottom Layer)
          Positioned(
            right: 0,
            child: Container(
              width: diskSize,
              height: diskSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? Colors.black87 : Colors.grey.shade300,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.4 : 0.15),
                    blurRadius: 10,
                    offset: const Offset(5, 5),
                  )
                ],
              ),
              child: ClipOval(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                          ? Transform.scale(
                              scale: 1.35, 
                              child: CachedNetworkImage(
                                imageUrl: item.imageUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _buildPlaceholder(),
                              ),
                            )
                          : _buildPlaceholder(), 
                    ),
                    // Center CD/Vinyl Hole
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: appBg, 
                        border: Border.all(
                          color: isDark ? Colors.black54 : Colors.grey.shade400, 
                          width: 1.5
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. The Transparent Glassmorphism Sleeve Cover (On Top Layer)
          Positioned(
            left: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: sleeveSize,
                  height: sleeveSize,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSel 
                        ? (isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.08))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSel ? const Color(0xFF4993FC) : (isDark ? Colors.white24 : Colors.black26),
                      width: isSel ? 2 : 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // TEXT: Top Left Align
                      Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textCol,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  height: 1.1,
                                  letterSpacing: -0.3,
                                  shadows: [Shadow(color: appBg.withOpacity(0.8), blurRadius: 4)]
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.subtitle,
                                style: TextStyle(
                                  color: textCol.withOpacity(0.7), 
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  shadows: [Shadow(color: appBg.withOpacity(0.8), blurRadius: 4)]
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // APP LOGO: Bottom Left Align (On the cover)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        child: Container(
                          width: 36, 
                          height: 36,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/images/app_logo_final.png',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.music_note, size: 20, color: Colors.white24),
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
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF161B22),
      width: double.infinity,
      height: double.infinity,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Opacity(
          opacity: 0.6,
          child: Image.asset(
            'assets/images/app_logo_final.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.library_music_rounded, color: Colors.white54, size: 30)),
          ),
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: isDark ? Colors.black54 : Colors.grey[300]!,
                    blurRadius: 10,
                    offset: const Offset(5, 5)),
                BoxShadow(
                    color: isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.white,
                    blurRadius: 10,
                    offset: const Offset(-5, -5)),
              ]),
          child: Icon(icon, color: color, size: size * 0.5),
        ),
      );
}