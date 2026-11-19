import 'package:flutter/material.dart';
import 'noor_palette.dart';

/// Size of the round header buttons and of the logo beside them.
const double kNoorHeaderSize = 44;

/// The Noor sun-and-record logo, used in place of the "Noor" word in the
/// page headers.
class NoorLogo extends StatelessWidget {
  const NoorLogo({super.key, this.size = kNoorHeaderSize});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Noor',
        image: true,
        child: Image.asset('assets/images/noor_sun_logo.png',
            width: size, height: size, filterQuality: FilterQuality.medium),
      );
}

/// A round button with a thin ring and one icon, the size of the logo.
class NoorCircleIconButton extends StatelessWidget {
  const NoorCircleIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = kNoorHeaderSize,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.bg,
            border: Border.all(color: t.ac, width: 0.8),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, a) => RotationTransition(
                turns: Tween(begin: 0.75, end: 1.0).animate(a),
                child: FadeTransition(opacity: a, child: child)),
            child: Icon(icon,
                key: ValueKey(icon), color: t.ac, size: size * 0.48),
          ),
        ),
      ),
    );
  }
}

/// The round search button at the top right of Home, the player and the
/// search page. While search is open the magnifying glass turns into a
/// cross that closes it: like the play / pause button, the strokes move
/// rather than swap, the handle swinging into one bar of the cross while
/// the lens folds into the other.
class NoorSearchButton extends StatefulWidget {
  const NoorSearchButton({super.key, required this.open, required this.onTap});
  final bool open;
  final VoidCallback onTap;

  @override
  State<NoorSearchButton> createState() => _NoorSearchButtonState();
}

class _NoorSearchButtonState extends State<NoorSearchButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: widget.open ? 1 : 0);

  @override
  void didUpdateWidget(covariant NoorSearchButton old) {
    super.didUpdateWidget(old);
    if (old.open != widget.open) widget.open ? _c.forward() : _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    const size = kNoorHeaderSize;
    return Semantics(
      button: true,
      label: widget.open ? 'Close search' : 'Search',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.bg,
            border: Border.all(color: t.ac, width: 0.8),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(
              painter: SearchClosePainter(
                  Curves.easeInOutCubic.transform(_c.value), t.ac),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the magnifying glass ([p] = 0) turning into a cross ([p] = 1).
/// Geometry in a 24-unit box, centred in the button.
class SearchClosePainter extends CustomPainter {
  SearchClosePainter(this.p, this.color);
  final double p;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width * 0.5 / 24;
    final o = Offset((size.width - 24 * k) / 2, (size.height - 24 * k) / 2);
    Offset at(double x, double y) => o + Offset(x * k, y * k);
    double lerp(double a, double b) => a + (b - a) * p;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2 * k;

    // A slight turn through the morph, as the play / pause bars swing.
    canvas.save();
    final c = at(12, 12);
    canvas.translate(c.dx, c.dy);
    canvas.rotate(p * 3.14159265 / 2);
    canvas.translate(-c.dx, -c.dy);

    // The handle becomes the "\" bar of the cross (it ends a quarter turn
    // round, which reads as the same cross).
    canvas.drawLine(at(lerp(15.2, 5.5), lerp(15.2, 5.5)),
        at(lerp(20.5, 18.5), lerp(20.5, 18.5)), stroke);

    // The lens folds away while the "/" bar grows out of its centre.
    final r = lerp(6.3, 0);
    if (r > 0.2) {
      canvas.drawCircle(at(lerp(10.2, 12), lerp(10.2, 12)), r * k,
          stroke..color = color.withOpacity((1 - p * 1.4).clamp(0.0, 1.0)));
      stroke.color = color;
    }
    final half = 6.5 * p;
    if (half > 0.2) {
      canvas.drawLine(at(12 + half, 12 - half), at(12 - half, 12 + half), stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SearchClosePainter old) => old.p != p || old.color != color;
}

/// The round settings button beside search. What it opens depends on the
/// page: Settings on Home, the search filters while searching.
class NoorSettingsButton extends StatelessWidget {
  const NoorSettingsButton({super.key, required this.onTap, this.label = 'Settings'});
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) => NoorCircleIconButton(
        icon: Icons.settings_outlined,
        label: label,
        onTap: onTap,
      );
}
