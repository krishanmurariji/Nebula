import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'noor_palette.dart';

/// Noor's one like / unlike animation, the same on song cards, the bottom
/// card and the player.
///
/// * Like: a red heart springs up with a little overshoot, a ring ripples
///   out and sparks burst around it, then it floats up and fades.
/// * Unlike: an outlined heart appears, cracks down the middle, and its two
///   halves tip apart and fall away.
///
/// It plays each time [trigger] changes (keep a counter and bump it),
/// showing [liked] (true: became liked). Draws nothing while idle and never
/// takes touches. [size] is the heart's width.
class NoorLikeBurst extends StatefulWidget {
  const NoorLikeBurst({
    super.key,
    required this.trigger,
    required this.liked,
    this.size = 44,
  });

  final int trigger;
  final bool liked;
  final double size;

  @override
  State<NoorLikeBurst> createState() => _NoorLikeBurstState();
}

class _NoorLikeBurstState extends State<NoorLikeBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 950));
  bool _liked = true;

  @override
  void didUpdateWidget(covariant NoorLikeBurst old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) {
      _liked = widget.liked;
      _c.forward(from: 0);
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
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final v = _c.value;
          if (v == 0 || v == 1) return const SizedBox.shrink();
          final box = widget.size * 2.4;
          return Center(
            child: SizedBox(
              width: box,
              height: box,
              child: CustomPaint(
                painter: _liked
                    ? _LikePainter(v, widget.size)
                    : _UnlikePainter(v, widget.size, t.ac, t.bg),
              ),
            ),
          );
        },
      ),
    );
  }
}

const Color _red = Color(0xFFE5393F);
const Color _gold = Color(0xFFD8B06A);

/// A heart filling a [w]-wide box centred on [c].
Path _heart(Offset c, double w) {
  final h = w * 0.9;
  final x = c.dx - w / 2, y = c.dy - h / 2;
  return Path()
    ..moveTo(x + w / 2, y + h * 0.28)
    ..cubicTo(x + w * 0.5, y + h * 0.05, x + w * 0.05, y - h * 0.02,
        x + w * 0.02, y + h * 0.32)
    ..cubicTo(x, y + h * 0.58, x + w * 0.3, y + h * 0.78, x + w / 2, y + h)
    ..cubicTo(x + w * 0.7, y + h * 0.78, x + w, y + h * 0.58, x + w * 0.98,
        y + h * 0.32)
    ..cubicTo(x + w * 0.95, y - h * 0.02, x + w * 0.5, y + h * 0.05, x + w / 2,
        y + h * 0.28)
    ..close();
}

double _seg(double v, double a, double b) =>
    ((v - a) / (b - a)).clamp(0.0, 1.0);

class _LikePainter extends CustomPainter {
  _LikePainter(this.v, this.size);
  final double v;
  final double size;

  @override
  void paint(Canvas canvas, Size box) {
    final c = box.center(Offset.zero);

    // The ring ripples out and fades.
    final ring = Curves.easeOutCubic.transform(_seg(v, 0.05, 0.55));
    if (ring > 0 && ring < 1) {
      canvas.drawCircle(
          c,
          size * (0.45 + 0.6 * ring),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * 0.05 * (1 - ring)
            ..color = _red.withOpacity(0.7 * (1 - ring)));
    }

    // Sparks: eight dots flying out, red and gold by turns.
    final fly = Curves.easeOutCubic.transform(_seg(v, 0.1, 0.65));
    if (fly > 0 && fly < 1) {
      for (var k = 0; k < 8; k++) {
        final a = k * math.pi / 4 - math.pi / 2;
        final d = size * (0.55 + 0.55 * fly);
        final p = c + Offset(math.cos(a), math.sin(a)) * d;
        canvas.drawCircle(
            p,
            size * 0.06 * (1 - fly),
            Paint()
              ..color = (k.isEven ? _red : _gold).withOpacity(1 - fly * 0.6));
      }
    }

    // The heart: springs up (overshoot), holds, then floats up and fades.
    final pop = Curves.elasticOut.transform(_seg(v, 0, 0.5));
    final out = Curves.easeInCubic.transform(_seg(v, 0.68, 1));
    final scale = (pop * (1 - 0.15 * out)).clamp(0.0, 1.4);
    if (scale <= 0) return;
    final at = c - Offset(0, size * 0.35 * out);
    final heart = _heart(at, size * scale);
    canvas.drawPath(
        heart.shift(Offset(0, size * 0.04)),
        Paint()
          ..color = Colors.black.withOpacity(0.12 * (1 - out))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawPath(heart, Paint()..color = _red.withOpacity(1 - out));
    // A small shine.
    canvas.drawCircle(
        at + Offset(-size * scale * 0.2, -size * scale * 0.12),
        size * scale * 0.08,
        Paint()..color = Colors.white.withOpacity(0.55 * (1 - out)));
  }

  @override
  bool shouldRepaint(_LikePainter old) => old.v != v;
}

class _UnlikePainter extends CustomPainter {
  _UnlikePainter(this.v, this.size, this.color, this.bg);
  final double v;
  final double size;
  final Color color;
  final Color bg;

  @override
  void paint(Canvas canvas, Size box) {
    final c = box.center(Offset.zero);
    final appear = Curves.easeOutBack.transform(_seg(v, 0, 0.25));
    final crack = _seg(v, 0.25, 0.38);
    final fall = Curves.easeInCubic.transform(_seg(v, 0.38, 1));
    final w = size * appear.clamp(0.0, 1.2);
    if (w <= 0) return;
    final heart = _heart(c, w);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.055
      ..strokeJoin = StrokeJoin.round
      ..color = color.withOpacity(1 - fall);
    final fill = Paint()..color = bg.withOpacity(0.85 * (1 - fall));

    // The crack: a zigzag down the middle.
    final h = w * 0.9;
    final top = c.dy - h / 2 + h * 0.28, bottom = c.dy + h / 2;
    final zig = Path()..moveTo(c.dx, top);
    for (var i = 1; i <= 5; i++) {
      zig.lineTo(
          c.dx + (i.isOdd ? 1 : -1) * w * 0.06, top + (bottom - top) * i / 5);
    }

    void half(bool left) {
      final dir = left ? -1.0 : 1.0;
      canvas.save();
      canvas.translate(dir * size * 0.22 * fall, size * 0.6 * fall * fall);
      final pivot = Offset(c.dx, bottom);
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(dir * 0.55 * fall);
      canvas.translate(-pivot.dx, -pivot.dy);
      // Each half: the heart clipped to its side of the crack.
      final side = Path()
        ..addRect(left
            ? Rect.fromLTRB(c.dx - w, c.dy - w, c.dx, c.dy + w)
            : Rect.fromLTRB(c.dx, c.dy - w, c.dx + w, c.dy + w));
      canvas.clipPath(side);
      canvas.drawPath(heart, fill);
      canvas.drawPath(heart, line);
      canvas.restore();
    }

    half(true);
    half(false);
    if (crack > 0 && fall < 1) {
      canvas.drawPath(
          zig,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * 0.045
            ..color = color.withOpacity(crack * (1 - fall)));
    }
  }

  @override
  bool shouldRepaint(_UnlikePainter old) => old.v != v;
}
