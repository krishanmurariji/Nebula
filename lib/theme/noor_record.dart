import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A black vinyl record: fine grooves, two soft light sweeps, and a cream
/// centre label carrying the girl from the Noor logo. Used as the artwork of
/// the Home slider cards.
class NoorRecord extends StatelessWidget {
  const NoorRecord({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size(size, size), painter: _VinylPainter()),
          ClipOval(
            child: Image.asset('assets/images/noor_record_label.png',
                width: size * 0.40, height: size * 0.40, fit: BoxFit.cover),
          ),
          // spindle hole
          Container(
            width: math.max(4, size * 0.035),
            height: math.max(4, size * 0.035),
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Color(0xFF1A1A1C)),
          ),
        ],
      ),
    );
  }
}

class _VinylPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFF26262A), Color(0xFF131315), Color(0xFF070708)],
            stops: [0.0, 0.7, 1.0],
          ).createShader(rect));
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    final n = (r / 3).floor();
    for (var i = 0; i < n; i++) {
      final rr = r * (0.24 + 0.74 * i / n);
      groove.color = Colors.white.withOpacity(i.isEven ? 0.06 : 0.025);
      canvas.drawCircle(c, rr, groove);
    }
    // track gaps
    for (final f in [0.52, 0.68, 0.84]) {
      canvas.drawCircle(
          c,
          r * f,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = Colors.white.withOpacity(0.08));
    }
    // light sweeps
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = SweepGradient(
            colors: [
              Colors.transparent,
              Colors.white.withOpacity(0.22),
              Colors.transparent,
              Colors.transparent,
              Colors.white.withOpacity(0.16),
              Colors.transparent,
            ],
            stops: const [0.05, 0.12, 0.2, 0.55, 0.62, 0.7],
          ).createShader(rect));
    canvas.drawCircle(
        c,
        r - 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withOpacity(0.12));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
