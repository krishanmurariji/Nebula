import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../providers/theme_provider.dart';

class UpNextScreen extends ConsumerWidget {
  const UpNextScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ps = ref.watch(playerProvider);
    final queue = ps.queue;
    final likedSongs = ref.watch(likedProvider); 
    
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final h = MediaQuery.of(context).size.height;

    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF5F8FF);
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final mutedCol = isDark ? Colors.white54 : const Color(0xFF8A9BB0);
    const accentCol = Color(0xFF4993FC);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(context);
          },
          child: Container(
            height: h * 0.65,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 24, offset: Offset(0, -8))
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  // ── Top Drag Handle ──
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 5, 
                      width: 40,
                      margin: const EdgeInsets.only(top: 14, bottom: 16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(4)
                      ),
                    ),
                  ),

                  // ── Capsule Header ──
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF161B22) : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                            blurRadius: 12,
                            offset: const Offset(0, 4)
                          )
                        ]
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.queue_music_rounded, color: accentCol, size: 20),
                          const SizedBox(width: 8),
                          Text('Up Next', style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w900, color: textCol)),
                          const SizedBox(width: 8),
                          Text('•  hold & drag', style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600, color: mutedCol)),
                        ],
                      ),
                    ),
                  ),

                  // ── Reorderable Queue List ──
                  Expanded(
                    child: queue.isEmpty
                        ? Center(
                            child: Text('Queue is empty', 
                              style: TextStyle(color: mutedCol, fontWeight: FontWeight.w600)
                            )
                          )
                        : ReorderableListView.builder(
                            padding: const EdgeInsets.fromLTRB(0, 4, 0, 40),
                            physics: const BouncingScrollPhysics(),
                            itemCount: queue.length,
                            buildDefaultDragHandles: false, // Hide default drag icons
                            onReorder: (oldIndex, newIndex) {
                              HapticFeedback.lightImpact();
                              final adjustedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
                              ref.read(playerProvider.notifier).reorderQueue(oldIndex, adjustedNew);
                            },
                            proxyDecorator: (child, index, animation) {
                              return AnimatedBuilder(
                                animation: animation,
                                builder: (ctx, _) {
                                  final scale = Tween<double>(begin: 1.0, end: 1.04)
                                      .evaluate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
                                  return Transform.scale(
                                    scale: scale,
                                    child: Material(
                                      color: Colors.transparent,
                                      elevation: 0,
                                      child: child,
                                    ),
                                  );
                                },
                              );
                            },
                            itemBuilder: (_, i) {
                              final song = queue[i];
                              final isPlaying = ps.song?.videoId == song.videoId &&
                                  (ps.status == NebulaPlayerStatus.playing || ps.status == NebulaPlayerStatus.loading);
                              
                              final isLiked = likedSongs.any((s) => s.videoId == song.videoId);

                              return ReorderableDelayedDragStartListener(
                                key: ValueKey('upnext_${song.videoId}_$i'),
                                index: i,
                                child: Dismissible(
                                  key: ValueKey('dismiss_${song.videoId}_$i'),
                                  
                                  // ── CHANGED SWIPE DIRECTION TO START FROM LEFT ──
                                  direction: DismissDirection.startToEnd, 
                                  background: Container(
                                    // ── ALIGNED ICON TO LEFT WITH LEFT PADDING ──
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.only(left: 28),
                                    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent.shade400,
                                      borderRadius: BorderRadius.circular(36)
                                    ),
                                    child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
                                  ),
                                  onDismissed: (direction) {
                                    HapticFeedback.mediumImpact();
                                    ref.read(playerProvider.notifier).removeFromQueue(i);
                                  },
                                  child: _CapsuleSongTile(
                                    song: song,
                                    isPlaying: isPlaying,
                                    isLiked: isLiked,
                                    isDark: isDark,
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      ref.read(playerProvider.notifier).playSong(song, queue: queue);
                                      Navigator.pop(context);
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM CAPSULE TILE (Matches MiniPlayer Design)
// ═══════════════════════════════════════════════════════════════════════════════
class _CapsuleSongTile extends StatelessWidget {
  final Song song;
  final bool isPlaying;
  final bool isLiked;
  final bool isDark;
  final VoidCallback onTap;

  const _CapsuleSongTile({
    required this.song,
    required this.isPlaying,
    required this.isLiked,
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
            
            // ── Circular Album Art (Matches MiniPlayer image) ──
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3)
                  )
                ],
              ),
              child: ClipOval(
                child: Transform.scale(
                  scale: 1.35, // Eliminates black bars on YouTube thumbnails
                  child: CachedNetworkImage(
                    imageUrl: song.thumbnailUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.grey[800],
                      child: const Icon(Icons.music_note, color: Colors.white54, size: 18)
                    ),
                  ),
                ),
              ),
            ),
            
            const SizedBox(width: 14),
            
            // ── Song Info ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isPlaying ? accentCol : textCol,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: mutedCol,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            
            // ── Badges & Indicators ──
            if (isLiked)
              const Padding(
                padding: EdgeInsets.only(right: 12.0),
                child: Icon(Icons.favorite_rounded, color: Colors.pinkAccent, size: 18),
              ),
              
            if (isPlaying)
              const Padding(
                padding: EdgeInsets.only(right: 18.0),
                child: Icon(Icons.equalizer_rounded, color: accentCol, size: 22),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 20.0),
                child: Icon(Icons.drag_indicator_rounded, color: mutedCol.withOpacity(0.3), size: 22),
              ),
          ],
        ),
      ),
    );
  }
}