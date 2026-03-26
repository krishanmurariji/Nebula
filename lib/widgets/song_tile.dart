import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../providers/theme_provider.dart';

class SongTile extends ConsumerWidget {
  final Song song;
  final bool isPlaying;
  final VoidCallback onTap;
  final Widget? trailing;

  const SongTile({
    super.key,
    required this.song,
    required this.isPlaying,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    
    // Colors matched to your unified Neumorphic app palette
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F4F8);
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final mutedCol = isDark ? Colors.white54 : const Color(0xFF8A9BB0);
    const accentCol = Color(0xFF4993FC);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isPlaying ? accentCol.withOpacity(0.08) : bg,
          borderRadius: BorderRadius.circular(16),
          border: isPlaying
              ? Border.all(color: accentCol.withOpacity(0.3), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
                color: isDark ? Colors.black45 : Colors.grey.shade300,
                blurRadius: 7,
                offset: const Offset(3, 3)),
            BoxShadow(
                color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
                blurRadius: 7,
                offset: const Offset(-3, -3)),
          ],
        ),
        child: Row(
          children: [
            // ── UPDATED THUMBNAIL TO COMPLETELY FILL CIRCLE ──
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ],
              ),
              child: ClipOval(
                child: Transform.scale(
                  scale: 1.35, // Ensures the YouTube image completely fills the circle without black bars
                  child: CachedNetworkImage(
                    imageUrl: song.thumbnailUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[800],
                        child: const Icon(Icons.music_note,
                            color: Colors.white54, size: 18)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
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
                        fontWeight: FontWeight.w700,
                        color: isPlaying ? accentCol : textCol,
                        letterSpacing: -0.2),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: mutedCol,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            if (isPlaying)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.equalizer_rounded,
                    color: accentCol, size: 16),
              ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}