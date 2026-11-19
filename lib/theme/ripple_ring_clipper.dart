import 'dart:math';
import 'package:flutter/material.dart';

// ── Custom Clipper: Flawless Concentric Ring Reveal (CodePen Replica) ──

class RippleRingClipper extends CustomClipper<Path> {
  final double fraction;
  RippleRingClipper(this.fraction);

  @override
  Path getClip(Size size) {
    if (fraction <= 0.0) return Path();
    if (fraction >= 1.0) return Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final center = Offset(size.width / 2, 0); // Top-center
    final double maxRadius = sqrt(size.width * size.width + size.height * size.height);
    
    // Exactly mimics the CodePen spacing and sizing
    const double ringSpacing = 80.0; 
    final int numRings = (maxRadius / ringSpacing).ceil() + 1;
    const double maxStroke = 85.0; // Slightly larger than spacing to ensure they merge

    List<List<double>> intervals = [];

    // 1. Mathematically calculate all expanding rings
    for (int i = 0; i < numRings; i++) {
      // Stagger the delay just like the CSS transition-delay
      final double delayFraction = i * (0.4 / numRings); 
      double progress = ((fraction - delayFraction) / 0.6).clamp(0.0, 1.0);
      progress = Curves.easeInOutCubic.transform(progress);

      if (progress > 0.0) {
        final double baseRadius = (i * ringSpacing) + 20.0;
        final double currentStroke = progress * maxStroke;

        final double outer = baseRadius + (currentStroke / 2);
        double inner = baseRadius - (currentStroke / 2);
        if (inner < 0) inner = 0.0;

        intervals.add([inner, outer]);
      }
    }

    // 2. Merge overlapping rings to prevent Impeller from crashing/skipping frames
    List<List<double>> merged = [];
    for (var interval in intervals) {
      if (merged.isEmpty) {
        merged.add(interval);
      } else {
        var last = merged.last;
        if (interval[0] <= last[1]) {
          last[1] = max(last[1], interval[1]); // Rings touch and merge!
        } else {
          merged.add(interval);
        }
      }
    }

    // 3. Draw the perfectly optimized path
    Path finalPath = Path()..fillType = PathFillType.evenOdd;
    for (var interval in merged) {
      finalPath.addOval(Rect.fromCircle(center: center, radius: interval[1])); // Outer edge
      if (interval[0] > 0) {
        finalPath.addOval(Rect.fromCircle(center: center, radius: interval[0])); // Inner edge creates the hole
      }
    }

    return finalPath;
  }

  @override
  bool shouldReclip(RippleRingClipper old) => old.fraction != fraction;
}


/// A route that reveals the new page with the same concentric-ring wipe the
/// Home list uses when you change category. Going back plays it in reverse.
class NoorRippleRoute<T> extends PageRouteBuilder<T> {
  NoorRippleRoute({required WidgetBuilder builder})
      : super(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 900),
          reverseTransitionDuration: const Duration(milliseconds: 700),
          pageBuilder: (context, _, __) => builder(context),
          transitionsBuilder: (context, animation, _, child) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, _) => ClipPath(
                clipper: RippleRingClipper(animation.value),
                child: child,
              ),
            );
          },
        );
}
