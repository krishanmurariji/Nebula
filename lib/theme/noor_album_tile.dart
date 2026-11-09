import 'package:flutter/material.dart';
import 'noor_disc.dart';
import 'noor_palette.dart';
import 'noor_song_tile.dart';

/// One song as an "album": the cover with half a record peeking out from
/// behind it, the title and channel in the middle and a Play button.
///
/// * a heart sits on the top-right edge of the border (tap, or double-tap the
///   tile, to like / unlike);
/// * an official upload gets a small badge centred on the top border.
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

  static const double _cover = 84;
  static const double _disc = 78;
  static const double _top = 12; // where the border starts
  static const double _pillHeight = 30;
  // left padding 10 + cover block + gap 12
  static const double _pillLeft = 10 + _cover + _disc * 0.5 - 2 + 12;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    final label = loading ? 'Loading' : (selected && playing ? 'Pause' : 'Play');

    // The Play button is a sibling of the tile's gesture area (not inside it),
    // so a tap on it is instant instead of waiting for a possible double tap.
    final playButton = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPlay,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected && !loading ? t.ac : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.ac, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.6, color: t.ac))
            else
              Icon(
                  selected && playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 16,
                  color: selected ? t.onAc : t.ac),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected && !loading ? t.onAc : t.ac)),
          ],
        ),
      ),
    );

    final frame = Container(
      decoration: BoxDecoration(
        color: selected ? t.wash : null,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: selected ? t.ac : t.soft, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(10, 14, 12, 10),
      child: Row(
        children: [
          SizedBox(
            width: _cover + _disc * 0.5 - 2,
            height: _cover,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: _cover - _disc * 0.5,
                  top: (_cover - _disc) / 2,
                  child: NoorDisc(url: thumbnailUrl, size: _disc),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: t.ac, width: 1),
                    ),
                    child: NoorArt(url: thumbnailUrl, size: _cover, radius: 15),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: t.ac)),
                const SizedBox(height: 3),
                Text(channel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: noorSubtitleStyle(context)),
                const SizedBox(height: 9),
                const SizedBox(height: _pillHeight),
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
          Positioned(left: _pillLeft, bottom: 10, child: playButton),
          if (isOfficial)
            Positioned(
              top: _top - 9,
              left: 0,
              right: 0,
              child: Center(child: _OfficialBadge(t: t)),
            ),
          Positioned(
            top: _top - 14,
            right: 18,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleLike,
              child: Semantics(
                button: true,
                label: liked ? 'Unlike' : 'Like',
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.bg,
                    border: Border.all(color: liked ? t.ac : t.soft, width: 1),
                  ),
                  child: Icon(
                      liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 15,
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
