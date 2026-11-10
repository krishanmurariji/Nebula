import 'package:flutter/material.dart';
import 'noor_disc.dart';
import 'noor_palette.dart';
import 'noor_song_tile.dart';

/// One song as an "album": a record on the left, half tucked under the cover
/// on its right, then the title and channel. Tap plays; double-tap (or the
/// heart) likes. A heart sits on the top-right edge of the border and an
/// official upload gets a badge centred on the top border.
class NoorAlbumTile extends StatelessWidget {
  const NoorAlbumTile({
    super.key,
    required this.thumbnailUrl,
    required this.title,
    required this.channel,
    required this.onPlay,
    this.onToggleLike,
    this.isOfficial = false,
    this.liked = false,
    this.selected = false,
    this.loading = false,
    this.playing = false,
  });

  final String thumbnailUrl;
  final String title;
  final String channel;
  final VoidCallback onPlay;
  final VoidCallback? onToggleLike;
  final bool isOfficial;
  final bool liked;

  /// This is the current song.
  final bool selected;
  final bool loading;

  /// The current song is actually playing audio right now.
  final bool playing;

  static const double _cover = 62;
  static const double _disc = 58;
  static const double _overlap = 28; // how much of the record hides under the cover
  static const double _top = 10; // where the border starts

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);

    final art = SizedBox(
      width: _disc + _cover - _overlap,
      height: _cover,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The record: darkened and cropped tighter than the cover, so it
          // reads as vinyl and not as a second copy of the picture.
          Positioned(
            left: 0,
            top: (_cover - _disc) / 2,
            child: NoorDisc(url: thumbnailUrl, size: _disc, dim: 0.5, zoom: 2.2),
          ),
          // The cover sits on top and casts a soft shadow onto the record.
          Positioned(
            left: _disc - _overlap,
            top: 0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(t.isDark ? 0.6 : 0.38),
                    blurRadius: 7,
                    offset: const Offset(-3, 1),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: t.ac, width: 1),
                    ),
                    child: NoorArt(url: thumbnailUrl, size: _cover, radius: 13),
                  ),
                  if (loading)
                    Container(
                      width: _cover,
                      height: _cover,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: t.ac.withOpacity(0.45),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: t.bg),
                        ),
                      ),
                    )
                  else if (selected && playing)
                    Positioned(
                      right: 3,
                      bottom: 3,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration:
                            BoxDecoration(shape: BoxShape.circle, color: t.ac),
                        child: Icon(Icons.equalizer_rounded,
                            size: 12, color: t.bg),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final frame = Container(
      decoration: BoxDecoration(
        color: selected ? t.wash : null,
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: selected ? t.ac : t.soft, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
      child: Row(
        children: [
          art,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: t.ac)),
                const SizedBox(height: 3),
                Text(channel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: noorSubtitleStyle(context)),
              ],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: _top),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onPlay,
              onDoubleTap: onToggleLike,
              child: frame,
            ),
          ),
          if (isOfficial)
            Positioned(
              top: _top - 9,
              left: 0,
              right: 0,
              child: Center(child: _OfficialBadge(t: t)),
            ),
          Positioned(
            top: _top - 13,
            right: 22,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleLike,
              child: Semantics(
                button: true,
                label: liked ? 'Unlike' : 'Like',
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.bg,
                    border: Border.all(color: liked ? t.ac : t.soft, width: 1),
                  ),
                  child: Icon(
                      liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 14,
                      color: liked ? t.ac : t.mute),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficialBadge extends StatelessWidget {
  const _OfficialBadge({required this.t});
  final NoorTheme t;

  @override
  Widget build(BuildContext context) => Container(
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: t.ac, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_rounded, size: 11, color: t.ac),
            const SizedBox(width: 3),
            Text('OFFICIAL',
                style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: t.ac)),
          ],
        ),
      );
}
