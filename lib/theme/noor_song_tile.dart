import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'noor_palette.dart';
import 'noor_widgets.dart';

/// Square artwork with softly rounded corners. YouTube thumbnails carry black
/// bars, so the picture is scaled up a little to crop them away.
class NoorArt extends StatelessWidget {
  const NoorArt({super.key, required this.url, this.size = 54, this.radius = 14});
  final String url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: t.tint(0.25),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: url.isEmpty
            ? Icon(Icons.music_note_rounded, color: t.bg, size: size * 0.4)
            : Transform.scale(
                scale: 1.35,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorWidget: (_, __, ___) => Icon(Icons.music_note_rounded,
                      color: t.bg, size: size * 0.4),
                ),
              ),
      ),
    );
  }
}

/// One song row: artwork, title, a subtitle line, optional indicators and a
/// round trailing button. The same look on Home, Search and Up next.
class NoorSongTile extends StatelessWidget {
  const NoorSongTile({
    super.key,
    required this.thumbnailUrl,
    required this.title,
    required this.subtitle,
    this.selected = false,
    this.extras = const [],
    required this.trailing,
    this.onTap,
    this.height = 72,
  });

  final String thumbnailUrl;
  final String title;

  /// The line under the title (artist, plus any badges).
  final Widget subtitle;
  final bool selected;

  /// Small indicators shown before the trailing button (a heart, etc.).
  final List<Widget> extras;
  final Widget trailing;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
        child: NoorFrame(
          radius: 22,
          selected: selected,
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                const SizedBox(width: 8),
                NoorArt(url: thumbnailUrl, size: height - 18),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: t.ac)),
                      const SizedBox(height: 3),
                      subtitle,
                    ],
                  ),
                ),
                ...extras,
                trailing,
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtitle text style shared by the tiles.
TextStyle noorSubtitleStyle(BuildContext context) => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: NoorTheme.of(context).mute);
