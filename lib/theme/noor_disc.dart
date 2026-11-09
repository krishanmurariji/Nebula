import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'noor_palette.dart';

/// A vinyl record whose whole face is the song's artwork, with fine grooves
/// over it and a small spindle hole. Spin it by wrapping it in a
/// [RotationTransition].
class NoorDisc extends StatelessWidget {
  const NoorDisc({
    super.key,
    required this.url,
    required this.size,
    this.shadow = true,
  });

  final String url;
  final double size;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    final base = Color.lerp(t.ac, Colors.black, 0.6)!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: base,
        border: Border.all(color: t.ac, width: 1),
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url.isNotEmpty)
              Transform.scale(
                scale: 1.35,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox(),
                ),
              ),
            // Grooves + a soft dark rim, drawn over the artwork.
            CustomPaint(painter: _GroovePainter(t.bg)),
            Center(
              child: Container(
                width: size * 0.07 < 6 ? 6 : size * 0.07,
                height: size * 0.07 < 6 ? 6 : size * 0.07,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: t.bg,
                  border: Border.all(color: t.ac, width: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroovePainter extends CustomPainter {
  _GroovePainter(this.light);
  final Color light;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    // Darken the outer edge a little so it reads as a record, not a photo.
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.transparent,
              Colors.transparent,
              Colors.black.withOpacity(0.28),
            ],
            stops: const [0.0, 0.78, 1.0],
          ).createShader(Rect.fromCircle(center: c, radius: r)));
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    final n = (r / 4).floor().clamp(5, 22);
    for (var i = 1; i <= n; i++) {
      final rr = r * (0.22 + 0.76 * i / n);
      groove.color = (i.isEven ? Colors.black : light).withOpacity(0.10);
      canvas.drawCircle(c, rr, groove);
    }
    // A single soft light sweep so it catches the light while it spins.
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 0.6),
        -0.6,
        0.9,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.5
          ..color = light.withOpacity(0.07));
  }

  @override
  bool shouldRepaint(_GroovePainter old) => old.light != light;
}
