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
/// search page: a magnifying glass; while search is open it turns into a
/// cross that closes it.
class NoorSearchButton extends StatelessWidget {
  const NoorSearchButton({super.key, required this.open, required this.onTap});
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => NoorCircleIconButton(
        icon: open ? Icons.close_rounded : Icons.search_rounded,
        label: open ? 'Close search' : 'Search',
        onTap: onTap,
      );
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
