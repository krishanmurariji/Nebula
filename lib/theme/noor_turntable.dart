import 'dart:math';
import 'package:flutter/material.dart';
import 'noor_artwork.dart';

/// A turntable seen from above: a light rounded plinth, a grey platter well,
/// a black record whose centre label is the song's artwork, a tone arm on
/// the top right, a pitch slider and a knob.
///
/// * [spinning]: the record turns;
/// * [armDown]: the stylus rests on the record (lifted and swung out when
///   false);
/// * [discShift]: moves the record sideways, as a fraction of the size
///   (used when one record is swapped for the next);
/// * [incomingArtUrl] / [incomingShift]: a second record (not turning) at
///   that shift, the one sliding in while the record is swiped.
class NoorTurntable extends StatefulWidget {
  const NoorTurntable({
    super.key,
    required this.size,
    required this.artUrl,
    required this.spinning,
    required this.armDown,
    this.discShift = 0,
    this.incomingArtUrl,
    this.incomingShift = 0,
  });

  final String? incomingArtUrl;
  final double incomingShift;
  final double size;
  final String artUrl;
  final bool spinning;
  final bool armDown;
  final double discShift;

  /// Record centre and radius, as fractions of [size].
  static const Offset discCentre = Offset(0.45, 0.5);
  static const double discRadius = 0.39;

  @override
  State<NoorTurntable> createState() => _NoorTurntableState();
}

class _NoorTurntableState extends State<NoorTurntable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _spin.repeat();
  }

  @override
  void didUpdateWidget(NoorTurntable old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.spinning && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final d = NoorTurntable.discRadius * 2 * s;
    final c = NoorTurntable.discCentre;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: CustomPaint(painter: _PlinthPainter())),
          if (widget.incomingArtUrl != null)
            _record(s, d, c, widget.incomingShift, widget.incomingArtUrl!,
                turning: false),
          // The record (and its artwork label) turns and slides.
          _record(s, d, c, widget.discShift, widget.artUrl, turning: true),
          // Spindle (does not turn visibly, so outside the rotation).
          Positioned(
            left: c.dx * s - s * 0.014 + widget.discShift * s,
            top: c.dy * s - s * 0.014,
            child: Container(
              width: s * 0.028,
              height: s * 0.028,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: Alignment(-0.4, -0.4),
                  colors: [Color(0xFFE6E6E6), Color(0xFF8C8C8C)],
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black38,
                      blurRadius: 2,
                      offset: Offset(0.5, 1))
                ],
              ),
            ),
          ),
          Positioned.fill(child: CustomPaint(painter: _ControlsPainter())),
          // Tone arm, swinging about its pivot.
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: widget.armDown ? 0 : 1),
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeInOutCubic,
              builder: (context, lift, _) =>
                  CustomPaint(painter: _ArmPainter(lift)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _record(double s, double d, Offset c, double shift, String art,
      {required bool turning}) {
    final record = Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _VinylPainter()),
        Center(
          child: SizedBox(
            width: d * 0.41,
            height: d * 0.41,
            child: ClipOval(
              child: Stack(fit: StackFit.expand, children: [
                const ColoredBox(color: Color(0xFFE8673F)),
                if (art.isNotEmpty) NoorArtwork(url: art),
              ]),
            ),
          ),
        ),
        // Light sheen over the label so it sits under the same lighting as
        // the vinyl.
        CustomPaint(painter: _SheenPainter()),
      ],
    );
    return Positioned(
      left: c.dx * s - d / 2 + shift * s,
      top: c.dy * s - d / 2,
      width: d,
      height: d,
      child: turning ? RotationTransition(turns: _spin, child: record) : record,
    );
  }
}

/// The body: rounded plinth with a soft drop shadow and the grey well the
/// platter sits in.
class _PlinthPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final body =
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.1));

    // Shadow under the body.
    canvas.drawRRect(
      body.shift(Offset(0, s * 0.03)),
      Paint()
        ..color = const Color(0xFF5A6478).withOpacity(0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.035),
    );
    // Body.
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF4F3F1), Color(0xFFE2E1DE)],
        ).createShader(Offset.zero & size),
    );
    // Rim highlight / lower edge.
    canvas.drawRRect(
      body.deflate(s * 0.012),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.012
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withOpacity(0.9), const Color(0xFFCFCECB)],
        ).createShader(Offset.zero & size),
    );

    // Grey well: square on the left (clipped to the body), round on the right.
    final c = Offset(
        NoorTurntable.discCentre.dx * s, NoorTurntable.discCentre.dy * s);
    final r = s * 0.42;
    final well = Path()
      ..addRect(Rect.fromLTRB(0, c.dy - r, c.dx, c.dy + r))
      ..addOval(Rect.fromCircle(center: c, radius: r));
    canvas.save();
    canvas.clipRRect(body.deflate(s * 0.018));
    canvas.drawPath(
      well,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFADB3B2), Color(0xFF9EA4A6)],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlinthPainter old) => false;
}

/// The black record with grooves, track gaps and two broad reflections.
class _VinylPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    canvas.drawCircle(
        c,
        r + 1,
        Paint()
          ..color = Colors.black.withOpacity(0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF111213));
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Colors.white.withOpacity(0.06);
    for (var rr = r * 0.96; rr > r * 0.46; rr -= r * 0.022) {
      canvas.drawCircle(c, rr, groove);
    }
    final gap = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Colors.black.withOpacity(0.9);
    for (final f in [0.88, 0.76, 0.64, 0.55]) {
      canvas.drawCircle(c, r * f, gap);
    }
    // Lead-out ring around the label.
    canvas.drawCircle(c, r * 0.47, Paint()..color = const Color(0xFF0A0A0B));
    // Outer edge.
    canvas.drawCircle(
        c,
        r - 0.8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = const Color(0xFF2A2B2E));
  }

  @override
  bool shouldRepaint(_VinylPainter old) => false;
}

/// Two soft diagonal reflections across the record, like in a lit room.
class _SheenPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.saveLayer(rect, Paint());
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = SweepGradient(
          colors: [
            Colors.white.withOpacity(0.0),
            Colors.white.withOpacity(0.16),
            Colors.white.withOpacity(0.0),
            Colors.white.withOpacity(0.0),
            Colors.white.withOpacity(0.13),
            Colors.white.withOpacity(0.0),
            Colors.white.withOpacity(0.0),
          ],
          stops: const [0.05, 0.13, 0.22, 0.55, 0.63, 0.72, 1.0],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SheenPainter old) => false;
}

/// Pitch slider and knob on the right of the plinth.
class _ControlsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Slider slot.
    final x = s * 0.875;
    final top = s * 0.42, bottom = s * 0.60;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(x - s * 0.006, top, x + s * 0.006, bottom),
          Radius.circular(s * 0.006)),
      Paint()..color = const Color(0xFF3A3B3D),
    );
    final tick = Paint()..color = const Color(0xFF7F8590);
    for (var i = 0; i <= 12; i++) {
      final y = top + (bottom - top) * i / 12;
      final long = i % 3 == 0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x - s * (long ? 0.03 : 0.022), y - s * 0.002,
                s * (long ? 0.012 : 0.004), s * 0.004),
            Radius.circular(s * 0.002)),
        tick,
      );
    }
    // Slider cap with a red dot.
    final capY = top + (bottom - top) * 0.58;
    final cap = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(x, capY), width: s * 0.026, height: s * 0.05),
        Radius.circular(s * 0.006));
    canvas.drawRRect(
        cap.shift(Offset(0, s * 0.004)), Paint()..color = Colors.black26);
    canvas.drawRRect(
        cap,
        Paint()
          ..shader = const LinearGradient(
                  colors: [Color(0xFFF2F2F2), Color(0xFFCFCFCF)])
              .createShader(cap.outerRect));
    canvas.drawCircle(
        Offset(x, capY), s * 0.004, Paint()..color = const Color(0xFFD2412F));

    // Knob.
    final k = Offset(s * 0.84, s * 0.80);
    final kr = s * 0.075;
    canvas.drawCircle(
        k + Offset(0, s * 0.008),
        kr,
        Paint()
          ..color = Colors.black.withOpacity(0.18)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.01));
    canvas.drawCircle(
        k,
        kr,
        Paint()
          ..shader = const SweepGradient(colors: [
            Color(0xFFB9BCC4),
            Color(0xFFE9EAEE),
            Color(0xFF9DA1AA),
            Color(0xFFDADCE1),
            Color(0xFFA4A8B0),
            Color(0xFFE6E7EB),
            Color(0xFFB9BCC4),
          ]).createShader(Rect.fromCircle(center: k, radius: kr)));
    canvas.drawCircle(
        k,
        kr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF8E929B));
    final a = -pi / 4;
    canvas.drawLine(
        k + Offset(cos(a), sin(a)) * kr * 0.25,
        k + Offset(cos(a), sin(a)) * kr * 0.85,
        Paint()
          ..strokeWidth = s * 0.006
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF5D616A));
    canvas.drawCircle(k + Offset(kr * 1.05, -kr * 1.05), s * 0.008,
        Paint()..color = const Color(0xFF4A4C50));
  }

  @override
  bool shouldRepaint(_ControlsPainter old) => false;
}

/// The tone arm. [lift] 0 = stylus on the record, 1 = parked to the right.
class _ArmPainter extends CustomPainter {
  _ArmPainter(this.lift);
  final double lift;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final pivot = Offset(s * 0.84, s * 0.16);

    // Base (does not move).
    canvas.drawCircle(
        pivot + Offset(0, s * 0.006),
        s * 0.095,
        Paint()
          ..color = Colors.black.withOpacity(0.12)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.01));
    canvas.drawCircle(
        pivot, s * 0.095, Paint()..color = const Color(0xFF8D9097));
    canvas.drawCircle(
        pivot, s * 0.078, Paint()..color = const Color(0xFFB8BBC1));
    canvas.drawCircle(
        pivot, s * 0.064, Paint()..color = const Color(0xFF9A9DA3));

    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    // Positive angle swings the arm clockwise, off the record.
    canvas.rotate(-0.22 * lift);
    canvas.translate(-pivot.dx, -pivot.dy);

    // Counterweight behind the pivot (up and to the right).
    final cwDir = Offset(cos(-1.05), sin(-1.05));
    final cwStart = pivot + cwDir * s * 0.03;
    final cwEnd = pivot + cwDir * s * 0.12;
    final cw = Paint()
      ..strokeWidth = s * 0.042
      ..strokeCap = StrokeCap.butt
      ..shader = const LinearGradient(
              colors: [Color(0xFFD9D9D9), Color(0xFFF7F7F7), Color(0xFFC8C8C8)])
          .createShader(Rect.fromPoints(cwStart, cwEnd));
    canvas.drawLine(cwStart, cwEnd, cw);
    canvas.drawLine(
        cwEnd - cwDir * s * 0.012,
        cwEnd,
        Paint()
          ..strokeWidth = s * 0.046
          ..color = const Color(0xFFBEBEBE));

    // Tube: from the pivot down, bending left into the headshell.
    final p1 = pivot + Offset(-s * 0.012, s * 0.07);
    final p2 = Offset(s * 0.795, s * 0.56);
    final p3 = Offset(s * 0.67, s * 0.735);
    final tube = Path()
      ..moveTo(pivot.dx, pivot.dy)
      ..lineTo(p1.dx, p1.dy)
      ..quadraticBezierTo(s * 0.81, s * 0.44, p2.dx, p2.dy)
      ..quadraticBezierTo(s * 0.775, s * 0.66, p3.dx, p3.dy);
    canvas.drawPath(
        tube,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.017
          ..strokeCap = StrokeCap.round
          ..color = Colors.black.withOpacity(0.15)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.006));
    canvas.drawPath(
        tube,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.014
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF8F949C));
    canvas.drawPath(
        tube,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.004
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withOpacity(0.45));

    // Pivot cap on top of the tube.
    canvas.drawCircle(
        pivot,
        s * 0.044,
        Paint()
          ..shader = const RadialGradient(
                  center: Alignment(-0.3, -0.3),
                  colors: [Color(0xFFF5F5F5), Color(0xFFBDBDBD)])
              .createShader(Rect.fromCircle(center: pivot, radius: s * 0.044)));

    // Headshell: a white block angled along the end of the tube, a blue
    // cartridge and the finger lift.
    canvas.save();
    canvas.translate(p3.dx, p3.dy);
    canvas.rotate(0.92);
    final shell = RRect.fromRectAndRadius(
        Rect.fromLTWH(-s * 0.03, -s * 0.004, s * 0.06, s * 0.075),
        Radius.circular(s * 0.006));
    canvas.drawRRect(shell.shift(Offset(s * 0.004, s * 0.006)),
        Paint()..color = Colors.black26);
    canvas.drawRRect(shell, Paint()..color = const Color(0xFFF1F1F1));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(-s * 0.022, s * 0.045, s * 0.034, s * 0.036),
            Radius.circular(s * 0.004)),
        Paint()..color = const Color(0xFF8DB8DE));
    canvas.drawLine(
        Offset(s * 0.022, s * 0.05),
        Offset(s * 0.05, s * 0.095),
        Paint()
          ..strokeWidth = s * 0.006
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFF4F4F4));
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArmPainter old) => old.lift != lift;
}
