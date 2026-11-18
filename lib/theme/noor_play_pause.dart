import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'noor_palette.dart';

/// Round play / pause button with the "two bars" morph: while playing it
/// shows two upright bars (pause); when paused the bars swing together into a
/// play arrow. The ring and bars use the Noor accent with a thin stroke.
class NoorPlayPauseButton extends StatefulWidget {
  const NoorPlayPauseButton({
    super.key,
    required this.playing,
    this.onTap,
    this.size = 40,
    this.loading = false,
  });

  /// True shows the pause bars; false shows the play arrow.
  final bool playing;
  final VoidCallback? onTap;
  final double size;

  /// Shows a thin spinner in the ring while a song is being prepared.
  final bool loading;

  @override
  State<NoorPlayPauseButton> createState() => _NoorPlayPauseButtonState();
}

class _NoorPlayPauseButtonState extends State<NoorPlayPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
    value: widget.playing ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant NoorPlayPauseButton old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) {
      widget.playing ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    final s = widget.size;
    return Semantics(
      button: true,
      label: widget.playing ? 'Pause' : 'Play',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: s,
          height: s,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: t.bg,
                  border: Border.all(color: t.ac, width: 1),
                ),
              ),
              if (widget.loading)
                SizedBox(
                  width: s - 6,
                  height: s - 6,
                  child: CircularProgressIndicator(strokeWidth: 1.2, color: t.ac),
                ),
              AnimatedBuilder(
                animation: _c,
                builder: (_, __) => CustomPaint(
                  size: Size(s, s),
                  painter: _BarsPainter(
                      Curves.easeInOut.transform(_c.value), t.ac),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints the two bars. Geometry follows the CSS reference: a 40x40 box,
/// bars 3x20 centred at y=20. Pause: bars upright at x=15 and x=25.5.
/// Play: bar 1 at (21.5,15) turned -55°, bar 2 at (21.5,25) turned -125°,
/// which together draw the arrow. [p] = 1 means pause, 0 means play.
class _BarsPainter extends CustomPainter {
  _BarsPainter(this.p, this.color);
  final double p;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // The 40-unit box sits inside the circle with some breathing room.
    final k = size.width * 0.62 / 40;
    final ox = (size.width - 40 * k) / 2 - 1.2 * k;
    final oy = (size.height - 40 * k) / 2;
    final paint = Paint()..color = color;
    double lerp(double a, double b) => a + (b - a) * p;
    void bar(double px, double py, double pr, double ux, double uy, double ur) {
      final cx = lerp(px, ux), cy = lerp(py, uy);
      final rot = lerp(pr, ur) * math.pi / 180;
      canvas.save();
      canvas.translate(ox + cx * k, oy + cy * k);
      canvas.rotate(rot);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: 3 * k, height: 20 * k),
              Radius.circular(1.5 * k)),
          paint);
      canvas.restore();
    }

    // play pose -> pause pose
    bar(21.5, 15, -55, 15, 20, 0);
    bar(21.5, 25, -125, 25.5, 20, 0);
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.p != p || old.color != color;
}
