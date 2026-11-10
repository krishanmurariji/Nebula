import 'package:flutter/material.dart';
import 'noor_disc.dart';
import 'noor_palette.dart';
import 'noor_song_tile.dart';

/// One song as an "album": a record on the left, half tucked under the cover
/// on its right, then the title and channel. Tap plays; double-tap likes or
/// unlikes and shows a heart animation (a white heart turns red when liked,
/// a red heart turns white when unliked). Pass [isOfficial] to show the
/// OFFICIAL badge centred on the top border.
class NoorAlbumTile extends StatefulWidget {
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

  @override
  State<NoorAlbumTile> createState() => _NoorAlbumTileState();

  static const double _cover = 62;
  static const double _disc = 58;
  static const double _overlap = 28; // how much of the record hides under the cover
  static const double _top = 10; // where the border starts

}

const Color _likeRed = Color(0xFFE5393F);

class _NoorAlbumTileState extends State<NoorAlbumTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heart = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000));
  bool _becomingLiked = true;

  @override
  void dispose() {
    _heart.dispose();
    super.dispose();
  }

  void _doubleTap() {
    _becomingLiked = !widget.liked;
    _heart.forward(from: 0);
    widget.onToggleLike?.call();
  }

  /// The big heart that pops over the tile after a double tap.
  Widget _heartBurst() {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _heart,
          builder: (context, _) {
            final v = _heart.value;
            if (v == 0 || v == 1) return const SizedBox.shrink();
            final start = _becomingLiked ? Colors.white : _likeRed;
            final end = _becomingLiked ? _likeRed : Colors.white;
            final color = Color.lerp(
                start, end, Curves.easeInOut.transform(((v - 0.28) / 0.3).clamp(0.0, 1.0)))!;
            final scale = 0.35 +
                0.85 * Curves.easeOutBack.transform((v / 0.3).clamp(0.0, 1.0));
            final opacity = v < 0.72 ? 1.0 : (1 - (v - 0.72) / 0.28).clamp(0.0, 1.0);
            return Center(
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Icon(Icons.favorite_rounded,
                      size: 52,
                      color: color,
                      shadows: const [
                        Shadow(color: Color(0x55000000), blurRadius: 10),
                      ]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);

    final art = SizedBox(
      width: NoorAlbumTile._disc + NoorAlbumTile._cover - NoorAlbumTile._overlap,
      height: NoorAlbumTile._cover,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The record: darkened and cropped tighter than the cover, so it
          // reads as vinyl and not as a second copy of the picture.
          Positioned(
            left: 0,
            top: (NoorAlbumTile._cover - NoorAlbumTile._disc) / 2,
            child: NoorDisc(url: widget.thumbnailUrl, size: NoorAlbumTile._disc, dim: 0.5, zoom: 2.2),
          ),
          // The cover sits on top and casts a soft shadow onto the record.
          Positioned(
            left: NoorAlbumTile._disc - NoorAlbumTile._overlap,
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
                    child: NoorArt(url: widget.thumbnailUrl, size: NoorAlbumTile._cover, radius: 13),
                  ),
                  if (widget.loading)
                    Container(
                      width: NoorAlbumTile._cover,
                      height: NoorAlbumTile._cover,
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
                  else if (widget.selected && widget.playing)
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
        color: widget.selected ? t.wash : null,
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: widget.selected ? t.ac : t.soft, width: 1),
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
                Text(widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: t.ac)),
                const SizedBox(height: 3),
                Text(widget.channel,
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
            padding: EdgeInsets.only(top: widget.isOfficial ? NoorAlbumTile._top : 2),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onPlay,
              onDoubleTap: widget.onToggleLike == null ? null : _doubleTap,
              child: frame,
            ),
          ),
          if (widget.isOfficial)
            Positioned(
              top: NoorAlbumTile._top - 9,
              left: 0,
              right: 0,
              child: Center(child: _OfficialBadge(t: t)),
            ),
          _heartBurst(),
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
