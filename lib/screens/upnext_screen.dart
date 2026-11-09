import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_song_tile.dart';
import '../theme/noor_widgets.dart';

class UpNextScreen extends ConsumerWidget {
  const UpNextScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ps = ref.watch(playerProvider);
    final queue = ps.queue;
    final likedSongs = ref.watch(likedProvider); 
    
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final h = MediaQuery.of(context).size.height;

    final t = NoorTheme.byMode(isDark);
    final bg = t.bg;
    final textCol = t.ac;
    final mutedCol = t.mute;
    final accentCol = t.ac;

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
              border: Border.all(color: t.soft, width: 1),
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
                        color: t.soft,
                        borderRadius: BorderRadius.circular(4)
                      ),
                    ),
                  ),

                  // ── Capsule Header ──
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: NoorFrame(
                        radius: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.queue_music_rounded, color: accentCol, size: 20),
                            const SizedBox(width: 8),
                            Text('Up Next', style: noorSerif(textCol, size: 22, height: 1.0)),
                            const SizedBox(width: 8),
                            Text('•  hold & drag', style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600, color: mutedCol)),
                          ],
                        ),
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
                                    margin: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: t.ac,
                                      borderRadius: BorderRadius.circular(22)
                                    ),
                                    child: Icon(Icons.delete_outline_rounded, color: t.bg, size: 26),
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
    final t = NoorTheme.byMode(isDark);
    return NoorSongTile(
      thumbnailUrl: song.thumbnailUrl,
      title: song.title,
      subtitle: Text(song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: noorSubtitleStyle(context)),
      selected: isPlaying,
      onTap: onTap,
      extras: [
        if (isLiked)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Icon(Icons.favorite_rounded, color: t.ac, size: 17),
          ),
      ],
      trailing: NoorRoundButton(
        size: 38,
        filled: isPlaying,
        muted: !isPlaying,
        child: Icon(
            isPlaying ? Icons.equalizer_rounded : Icons.drag_indicator_rounded,
            size: 20),
      ),
    );
  }
}
