import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Noor's card outline: a thin rounded border with a small dot at the top
/// centre and a short gap on each side of it.
class NoorGapBorderPainter extends CustomPainter {
  const NoorGapBorderPainter({
    required this.color,
    this.width = 1,
    this.radius = 32,
    this.gap = 7,
    this.dot = 2.6,
  });

  final Color color;
  final double width;
  final double radius;

  /// Space left free on each side of the dot.
  final double gap;

  /// Radius of the dot.
  final double dot;

  @override
  void paint(Canvas canvas, Size size) {
    final i = width / 2; // keep the stroke inside the box
    final l = i, t = i, rgt = size.width - i, b = size.height - i;
    final r = math.min(radius, math.min(rgt - l, b - t) / 2);
    final cx = size.width / 2;
    final arc = Radius.circular(r);
    final path = Path()
      ..moveTo(cx + gap, t)
      ..lineTo(rgt - r, t)
      ..arcToPoint(Offset(rgt, t + r), radius: arc)
      ..lineTo(rgt, b - r)
      ..arcToPoint(Offset(rgt - r, b), radius: arc)
      ..lineTo(l + r, b)
      ..arcToPoint(Offset(l, b - r), radius: arc)
      ..lineTo(l, t + r)
      ..arcToPoint(Offset(l + r, t), radius: arc)
      ..lineTo(cx - gap, t);
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(Offset(cx, t), dot, Paint()..color = color);
  }

  @override
  bool shouldRepaint(NoorGapBorderPainter old) =>
      old.color != color ||
      old.width != width ||
      old.radius != radius ||
      old.gap != gap ||
      old.dot != dot;
}

/// A circle with a gap and a dot in it. [turn] is where the dot sits, in
/// turns clockwise from the top (0 = top).
class NoorGapRingPainter extends CustomPainter {
  const NoorGapRingPainter({
    required this.color,
    required this.turn,
    this.width = 1,
    this.gapAngle = 0.42, // radians on each side of the dot
    this.dot = 2.2,
  });

  final Color color;
  final double turn;
  final double width;
  final double gapAngle;
  final double dot;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - width / 2 - dot / 2;
    // Canvas angles start at 3 o'clock; the dot starts at 12.
    final at = -math.pi / 2 + turn * 2 * math.pi;
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        at + gapAngle,
        2 * math.pi - 2 * gapAngle,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(c + Offset(math.cos(at), math.sin(at)) * r, dot,
        Paint()..color = color);
  }

  @override
  bool shouldRepaint(NoorGapRingPainter old) =>
      old.turn != turn || old.color != color || old.width != width;
}
