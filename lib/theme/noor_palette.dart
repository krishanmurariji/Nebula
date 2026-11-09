import 'package:flutter/material.dart';

/// Noor uses exactly two colours: ivory + copper by day, espresso + gold by
/// night. Everything else is a tint of those two (see [NoorTheme]).
class NoorColors {
  NoorColors._();

  static const ivory = Color(0xFFE8E0CE);
  static const copper = Color(0xFF8E4A27);
  static const espresso = Color(0xFF1F1914);
  static const gold = Color(0xFFD8B06A);
}

/// The two colours of the current theme plus their tints.
class NoorTheme {
  const NoorTheme._(this.isDark, this.bg, this.ac);

  static const light = NoorTheme._(false, NoorColors.ivory, NoorColors.copper);
  static const dark = NoorTheme._(true, NoorColors.espresso, NoorColors.gold);

  static NoorTheme ofBrightness(Brightness b) =>
      b == Brightness.dark ? dark : light;

  /// The theme of the nearest [Theme]; the app switches it with ThemeMode.
  static NoorTheme of(BuildContext context) =>
      ofBrightness(Theme.of(context).brightness);

  static NoorTheme byMode(bool isDark) => isDark ? dark : light;

  final bool isDark;

  /// Page / surface colour.
  final Color bg;

  /// The one accent: text, icons, outlines and filled buttons.
  final Color ac;

  /// Text or icon colour on top of a filled [ac] surface.
  Color get onAc => bg;

  /// Main text (the accent itself).
  Color get text => ac;

  /// Secondary text.
  Color get mute => Color.lerp(bg, ac, 0.62)!;

  /// Outline strength levels.
  Color get soft => ac.withOpacity(0.45);
  Color get faint => ac.withOpacity(0.22);
  Color get wash => ac.withOpacity(0.10);

  /// Artwork tint: [level] 0..1 of accent over the surface. Used where the app
  /// has no picture to show, and for the optional two-colour artwork.
  Color tint(double level) => Color.lerp(bg, ac, level)!;
}
