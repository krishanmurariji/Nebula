import 'package:flutter/material.dart';
import 'noor_palette.dart';

/// Font family for headings (bundled Cormorant Garamond).
const String kNoorSerif = 'Cormorant';

TextStyle noorSerif(Color color,
        {double size = 28, FontWeight weight = FontWeight.w700, double? height}) =>
    TextStyle(
        fontFamily: kNoorSerif,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: -0.2);

/// A rounded box with a fine outline and a second, fainter outline just
/// outside it. The Noor replacement for raised cards.
class NoorFrame extends StatelessWidget {
  const NoorFrame({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding = EdgeInsets.zero,
    this.fill,
    this.selected = false,
    this.ring = true,
    this.onTap,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? fill;
  final bool selected;
  final bool ring;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    Widget inner = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill ?? (selected ? t.wash : null),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: t.soft, width: 1),
      ),
      child: child,
    );
    if (ring) {
      inner = Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius + 4),
          border: Border.all(color: t.faint, width: 1),
        ),
        child: inner,
      );
    }
    if (onTap == null) return inner;
    return GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: onTap, child: inner);
  }
}

/// Round outlined button: a fine ring with a faint ring inside. [filled]
/// turns it into a solid accent button (the "on" state).
class NoorRoundButton extends StatelessWidget {
  const NoorRoundButton({
    super.key,
    required this.child,
    this.size = 44,
    this.filled = false,
    this.muted = false,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final double size;
  final bool filled;
  final bool muted;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    final fg = filled ? t.onAc : (muted ? t.mute : t.ac);
    final btn = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? t.ac : null,
        border: Border.all(color: muted ? t.soft : t.ac, width: 1),
      ),
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: filled ? t.onAc.withOpacity(0.6) : t.soft, width: 1),
        ),
        alignment: Alignment.center,
        child: IconTheme(
            data: IconThemeData(color: fg, size: size * 0.42), child: child),
      ),
    );
    final tappable = onTap == null
        ? btn
        : GestureDetector(
            behavior: HitTestBehavior.opaque, onTap: onTap, child: btn);
    if (semanticLabel == null) return tappable;
    return Semantics(
        button: onTap != null, label: semanticLabel, child: tappable);
  }
}

/// Small line ornament: ──◆──
class NoorDivider extends StatelessWidget {
  const NoorDivider({super.key, this.width = 64});
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    return CustomPaint(
        size: Size(width, 12), painter: _DividerPainter(t.ac));
  }
}

class _DividerPainter extends CustomPainter {
  _DividerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..strokeWidth = 1;
    final cy = size.height / 2;
    final cx = size.width / 2;
    canvas.drawLine(Offset(0, cy), Offset(cx - 6, cy), line);
    canvas.drawLine(Offset(cx + 6, cy), Offset(size.width, cy), line);
    final d = Path()
      ..moveTo(cx, cy - 5)
      ..lineTo(cx + 5, cy)
      ..lineTo(cx, cy + 5)
      ..lineTo(cx - 5, cy)
      ..close();
    canvas.drawPath(d, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DividerPainter old) => old.color != color;
}

/// The "Noor" lettering, tinted with the theme accent.
class NoorWordmark extends StatelessWidget {
  const NoorWordmark({super.key, this.height = 36});
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    return Image.asset('assets/images/noor_wordmark.png',
        height: height, color: t.ac, semanticLabel: 'Noor');
  }
}

/// Faint carved-lattice (jali) pattern that fades out downwards. Sits behind
/// the top of every page.
class NoorBackdrop extends StatelessWidget {
  const NoorBackdrop({super.key, this.height = 300});
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.transparent],
          ).createShader(r),
          child: ClipRect(
            child: CustomPaint(
                painter:
                    _JaliPainter(t.ac.withOpacity(t.isDark ? 0.10 : 0.13))),
          ),
        ),
      ),
    );
  }
}

class _JaliPainter extends CustomPainter {
  _JaliPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const u = 44.0;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += u) {
      for (double x = 0; x < size.width; x += u) {
        final path = Path()
          ..moveTo(x + 22, y)
          ..lineTo(x + 28, y + 16)
          ..lineTo(x + 44, y + 22)
          ..lineTo(x + 28, y + 28)
          ..lineTo(x + 22, y + 44)
          ..lineTo(x + 16, y + 28)
          ..lineTo(x, y + 22)
          ..lineTo(x + 16, y + 16)
          ..close();
        canvas.drawPath(path, p);
        canvas.drawCircle(Offset(x + 22, y + 22), 3, p);
      }
    }
  }

  @override
  bool shouldRepaint(_JaliPainter old) => old.color != color;
}
