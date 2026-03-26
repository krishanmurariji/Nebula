import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/song_tile.dart';

class UpNextScreen extends ConsumerWidget {
  const UpNextScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ps     = ref.watch(playerProvider);
    final queue  = ps.queue;
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final h      = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(context);
          },
          child: Container(
            height: h * 0.62,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF5F8FF),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -5))],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  // Drag handle
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 4, width: 36,
                      margin: const EdgeInsets.only(top: 14, bottom: 10),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2)),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Row(
                      children: [
                        Text('Up Next', style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                            letterSpacing: -0.2)),
                        const SizedBox(width: 8),
                        Text('— hold & drag to reorder',
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white38 : const Color(0xFFB0BEC5))),
                      ],
                    ),
                  ),

                  // Reorderable queue list
                  Expanded(
                    child: queue.isEmpty
                        ? const Center(child: Text('Queue is empty', style: TextStyle(color: Color(0xFF8A9BB0))))
                        : ReorderableListView.builder(
                            padding: const EdgeInsets.fromLTRB(0, 4, 0, 40),
                            physics: const BouncingScrollPhysics(),
                            itemCount: queue.length,
                            onReorder: (oldIndex, newIndex) {
                              HapticFeedback.lightImpact();
                              final adjustedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
                              ref.read(playerProvider.notifier).reorderQueue(oldIndex, adjustedNew);
                            },
                            proxyDecorator: (child, index, animation) {
                              return AnimatedBuilder(
                                animation: animation,
                                builder: (ctx, _) {
                                  final scale = Tween<double>(begin: 1.0, end: 1.03)
                                      .evaluate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
                                  return Transform.scale(
                                    scale: scale,
                                    child: Material(
                                      color: Colors.transparent,
                                      elevation: 8,
                                      shadowColor: Colors.black38,
                                      child: child,
                                    ),
                                  );
                                },
                              );
                            },
                            itemBuilder: (_, i) {
                              final song = queue[i];
                              final isPlaying = ps.song?.videoId == song.videoId &&
                                  ps.status == NebulaPlayerStatus.playing;
                              return ReorderableDragStartListener(
                                key: ValueKey('upnext_${song.videoId}_$i'),
                                index: i,
                                child: SongTile(
                                  song: song,
                                  isPlaying: isPlaying,
                                  onTap: () {
                                    ref.read(playerProvider.notifier).playSong(song, queue: queue);
                                    Navigator.pop(context);
                                  },
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
