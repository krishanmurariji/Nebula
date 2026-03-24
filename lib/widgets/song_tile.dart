import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../providers/theme_provider.dart';

class SongTile extends ConsumerWidget {
  final Song song;
  final bool isPlaying;
  final VoidCallback onTap;

  const SongTile({
    super.key,
    required this.song,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark   = ref.watch(themeProvider) == ThemeMode.dark;
    final bg       = isDark ? const Color(0xFF0D1117) : const Color(0xFFEDF2F7);
    final cardBg   = isDark ? const Color(0xFF161B22) : Colors.white;
    final textCol  = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final mutedCol = isDark ? Colors.white54 : const Color(0xFF8A9BB0);

    return Padding(
      // Padding matches list spacing
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          // Exact height from MiniPlayer
          height: 64, 
          decoration: BoxDecoration(
            color: cardBg,
            // Exact pill roundness from MiniPlayer
            borderRadius: BorderRadius.circular(32), 
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                blurRadius: 20,
                offset: const Offset(0, 4),
              )
            ],
            // Adds a subtle blue border if this specific song is playing
            border: isPlaying 
                ? Border.all(color: const Color(0xFF4993FC).withOpacity(0.4), width: 1)
                : null,
          ),
          child: Row(children: [
            
            const SizedBox(width: 9),

            // ── Thumbnail circle (Exact match to MiniPlayer) ───────────
            ClipOval(
              child: song.thumbnailUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: song.thumbnailUrl,
                      width: 46, height: 46, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _thumb(mutedCol, bg))
                  : _thumb(mutedCol, bg),
            ),

            const SizedBox(width: 12),

            // ── Song name + artist (Exact match to MiniPlayer) ─────────
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
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      // Turns text blue if playing
                      color: isPlaying ? const Color(0xFF4993FC) : textCol, 
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: mutedCol),
                  ),
                ],
              ),
            ),

            // ── Trailing Indicator (Play/Pause indicator) ─────────────
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: isPlaying ? const Color(0xFF4993FC) : Colors.transparent,
                shape: BoxShape.circle,
                boxShadow: isPlaying ? [BoxShadow(
                  color: const Color(0xFF4993FC).withOpacity(0.4),
                  blurRadius: 10, offset: const Offset(0, 4))] : [],
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                // Hidden unless playing, so it keeps the UI minimal
                color: isPlaying ? Colors.white : const Color(0xFF4993FC).withOpacity(0.5),
                size: 18,
              ),
            ),

            const SizedBox(width: 14),
          ]),
        ),
      ),
    );
  }

  Widget _thumb(Color mutedCol, Color bg) => Container(
      width: 46, height: 46, color: bg,
      child: Icon(Icons.music_note, color: mutedCol, size: 20));
}