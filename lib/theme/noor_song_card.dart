import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'noor_disc.dart';
import 'noor_palette.dart';
import 'noor_play_pause.dart';

/// Font family for song titles (bundled Dancing Script).
const String kNoorScript = 'NoorScript';

/// Every card in the app shares this corner radius: a 64-high card with a
/// 32 radius has fully round ends, matching the record on its left.
const double kNoorCardRadius = 32;

TextStyle noorSongTitleStyle(Color color, {double size = 20}) => TextStyle(
    fontFamily: kNoorScript,
    fontSize: size,
    fontWeight: FontWeight.w700,
    height: 1.1,
    color: color);

TextStyle noorArtistStyle(Color color, {double size = 12}) => TextStyle(
    fontSize: size, fontWeight: FontWeight.w400, color: color, height: 1.2);

/// One song: a record on the left (its round end matches the card's round
/// end), the title in a script face with the artist under it, and the
/// animated play / pause button in a thin ring on the right.
///
/// * tap the card: [onTap] (plays the song);
/// * tap the button: [onPlayPause] (toggles this song);
/// * double tap the card: [onToggleLike] with a heart animation (an empty
///   heart turns red when liked; a red heart turns empty when unliked).
class NoorSongCard extends StatefulWidget {
  const NoorSongCard({
    super.key,
    required this.thumbnailUrl,
    required this.title,
    required this.artist,
    required this.onTap,
    this.onPlayPause,
    this.onToggleLike,
    this.liked = false,
    this.current = false,
    this.playing = false,
    this.loading = false,
    this.badge,
    this.onLongPress,
  });

  /// Long press (opens the song's actions where available).
  final VoidCallback? onLongPress;

  final String thumbnailUrl;
  final String title;
  final String artist;
  final VoidCallback onTap;
  final VoidCallback? onPlayPause;
  final VoidCallback? onToggleLike;
  final bool liked;

  /// This is the song in the player (playing or paused).
  final bool current;

  /// The player is playing this song right now.
  final bool playing;
  final bool loading;

  /// Optional short word after the artist (e.g. "Official").
  final String? badge;

  static const double height = 64;
  static const double _disc = 52;

  @override
  State<NoorSongCard> createState() => _NoorSongCardState();
}

const Color _likeRed = Color(0xFFE5393F);

class _NoorSongCardState extends State<NoorSongCard>
    with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 8));
  late final AnimationController _heart = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000));
  bool _becomingLiked = true;

  /// The finger is on the card: it dips a little at once, so a tap never
  /// feels ignored while Flutter waits to see if it becomes a double tap.
  bool _pressed = false;

  Timer? _releaseTimer;

  void _press(bool down) {
    _releaseTimer?.cancel();
    if (_pressed != down && mounted) setState(() => _pressed = down);
  }

  /// Lets the dip show for a moment even on a very quick tap.
  void _release() {
    _releaseTimer?.cancel();
    _releaseTimer =
        Timer(const Duration(milliseconds: 120), () => _press(false));
  }

  @override
  void initState() {
    super.initState();
    _syncSpin();
  }

  @override
  void didUpdateWidget(covariant NoorSongCard old) {
    super.didUpdateWidget(old);
    _syncSpin();
  }

  void _syncSpin() {
    final turn = widget.playing || widget.loading;
    if (turn && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!turn && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    _spin.dispose();
    _heart.dispose();
    super.dispose();
  }

  void _doubleTap() {
    _becomingLiked = !widget.liked;
    _heart.forward(from: 0);
    widget.onToggleLike?.call();
  }

  Widget _burst(NoorTheme t) => Positioned.fill(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _heart,
            builder: (context, _) {
              final v = _heart.value;
              if (v == 0 || v == 1) return const SizedBox.shrink();
              final mix = Curves.easeInOut
                  .transform(((v - 0.28) / 0.3).clamp(0.0, 1.0));
              // 0 = empty heart, 1 = red heart
              final fill = _becomingLiked ? mix : 1 - mix;
              final scale = 0.35 +
                  0.85 *
                      Curves.easeOutBack.transform((v / 0.3).clamp(0.0, 1.0));
              final opacity =
                  v < 0.72 ? 1.0 : (1 - (v - 0.72) / 0.28).clamp(0.0, 1.0);
              return Center(
                child: Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: scale,
                    child: Stack(alignment: Alignment.center, children: [
                      Icon(Icons.favorite_rounded,
                          size: 44,
                          color: Color.lerp(Colors.white, _likeRed, fill)),
                      Icon(Icons.favorite_border_rounded,
                          size: 44, color: Color.lerp(t.ac, _likeRed, fill)),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    final w = widget;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _press(true),
            onTapUp: (_) => _release(),
            onTapCancel: () => _press(false),
            onTap: w.onTap,
            onDoubleTap: w.onToggleLike == null ? null : _doubleTap,
            onLongPress: w.onLongPress,
            child: AnimatedScale(
              scale: _pressed ? 0.975 : 1,
              duration: const Duration(milliseconds: 110),
              curve: Curves.easeOut,
              child: Container(
                height: NoorSongCard.height,
                decoration: BoxDecoration(
                  color: w.current ? t.wash.withOpacity(0.06) : t.bg,
                  borderRadius: BorderRadius.circular(kNoorCardRadius),
                  border: Border.all(color: t.ac, width: w.current ? 1.2 : 0.8),
                ),
                // Narrow (actions open): no play button. Tiny (naming a
                // playlist): just the record.
                child: LayoutBuilder(builder: (context, box) {
                  final compact = box.maxWidth < 230;
                  if (box.maxWidth < 120) {
                    return Center(
                      child: RotationTransition(
                        turns: _spin,
                        child: NoorDisc(
                            url: w.thumbnailUrl,
                            size: min(NoorSongCard._disc, box.maxWidth - 8)),
                      ),
                    );
                  }
                  return Row(
                    children: [
                      const SizedBox(width: 6),
                      RotationTransition(
                        turns: _spin,
                        child: NoorDisc(
                            url: w.thumbnailUrl, size: NoorSongCard._disc),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(w.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: noorSongTitleStyle(t.ac)),
                            const SizedBox(height: 2),
                            if (w.loading)
                              _Pulse(
                                child: Text('Loading…',
                                    maxLines: 1, style: noorArtistStyle(t.ac)),
                              )
                            else
                              Text(
                                  w.badge == null
                                      ? w.artist
                                      : '${w.artist}  ·  ${w.badge}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: noorArtistStyle(t.mute)),
                          ],
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 8),
                        NoorPlayPauseButton(
                          playing: w.current && w.playing,
                          loading: w.loading,
                          onTap: w.onPlayPause ?? w.onTap,
                        ),
                      ],
                      const SizedBox(width: 12),
                    ],
                  );
                }),
              ),
            ),
          ),
          // While the song loads, a thin line runs along the card's bottom.
          if (w.loading)
            Positioned(
              left: 24,
              right: 24,
              bottom: 1,
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: t.ac,
                    backgroundColor: t.ac.withOpacity(0.12),
                  ),
                ),
              ),
            ),
          _burst(t),
        ],
      ),
    );
  }
}

/// A centred label with a thin line running out to each side:
/// `────── My Favorites ──────`.
class NoorLinedLabel extends StatelessWidget {
  const NoorLinedLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    Widget line(Alignment fadeFrom) => Expanded(
          child: Container(
            height: 0.8,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: fadeFrom,
                end: -fadeFrom,
                colors: [t.ac.withOpacity(0.0), t.ac.withOpacity(0.7)],
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          line(Alignment.centerLeft),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(text,
                  key: ValueKey(text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: t.ac,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
            ),
          ),
          line(Alignment.centerRight),
        ],
      ),
    );
  }
}

/// Gently fades its child in and out (used for "Loading…").
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});
  final Widget child;
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child);
}
