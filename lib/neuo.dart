import 'package:flutter/material.dart';

class N {
  static const bg       = Color(0xFFF5FAFF);
  static const surface  = Color(0xFFFFFFFF);
  static const primary  = Color(0xFF005EB9);
  static const onSurf   = Color(0xFF28343B);
  static const muted    = Color(0xFF556169);
  static const outline  = Color(0xFFA7B4BD);
  static const error    = Color(0xFFA83836);
  static const surfHigh = Color(0xFFDFEAF2);
  static const surfLow  = Color(0xFFEDF5FB);
  static const surfHst  = Color(0xFFD8E4EE);

  static List<BoxShadow> lift({double intensity = 1.0}) => [
    BoxShadow(
      color: Color.fromRGBO(209, 217, 230, intensity.clamp(0.0, 1.0)),
      blurRadius: (16 * intensity).clamp(1.0, 32.0),
      offset: Offset(
        (8 * intensity).clamp(0.0, 16.0),
        (8 * intensity).clamp(0.0, 16.0),
      ),
    ),
    BoxShadow(
      color: Colors.white.withOpacity(intensity.clamp(0.0, 1.0)),
      blurRadius: (16 * intensity).clamp(1.0, 32.0),
      offset: Offset(
        -(8 * intensity).clamp(0.0, 16.0),
        -(8 * intensity).clamp(0.0, 16.0),
      ),
    ),
  ];

  static List<BoxShadow> get inset => const [
    BoxShadow(
      color: Color(0xFFD1D9E6),
      blurRadius: 8,
      offset: Offset(4, 4),
    ),
    BoxShadow(
      color: Colors.white,
      blurRadius: 8,
      offset: Offset(-4, -4),
    ),
  ];
}

// Neumorphic card
class NCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final double intensity;
  final VoidCallback? onTap;

  const NCard({
    super.key,
    required this.child,
    this.padding   = const EdgeInsets.all(16),
    this.radius    = 16,
    this.intensity = 1.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: N.bg,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: N.lift(intensity: intensity),
        ),
        child: child,
      ),
    );
  }
}

// Neumorphic button - fixed zero-size assertion
class NButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double size;
  final bool filled;
  final double radius;

  const NButton({
    super.key,
    required this.child,
    this.onTap,
    this.size   = 48,
    this.filled = false,
    this.radius = 999,
  }) : assert(size > 0, 'NButton size must be > 0');

  @override
  State<NButton> createState() => _NButtonState();
}

class _NButtonState extends State<NButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // Ensure size is always positive to prevent painting assertion
    final sz = widget.size.clamp(24.0, 200.0);

    return GestureDetector(
      onTapDown:   (_) => setState(() => _pressed = true),
      onTapUp:     (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: Container(
        width: sz,
        height: sz,
        decoration: BoxDecoration(
          color: widget.filled ? N.primary : N.bg,
          borderRadius: BorderRadius.circular(widget.radius),
          boxShadow: _pressed
              ? (widget.filled
                  ? const []
                  : N.inset)
              : (widget.filled
                  ? [BoxShadow(
                      color: N.primary.withOpacity(0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8))]
                  : N.lift()),
        ),
        child: Center(child: widget.child),
      ),
    );
  }
}
