import 'package:flutter/material.dart';

/// Noor's colours. The light background is #DCD8CD and the accents come from
/// the copper of the Noor logo. Change a value here for the shared widgets
/// (app theme, neumorphic cards); screens still carry a few inline values that
/// were migrated to the same numbers.
class NoorColors {
  NoorColors._();

  // light
  static const bg = Color(0xFFDCD8CD);
  static const card = Color(0xFFE9E5DB);       // raised surface on bg
  static const shadowDark = Color(0xFFB8B3A6); // neumorphic dark side
  static const shadowLight = Color(0xFFF7F5EE); // neumorphic light side
  static const ink = Color(0xFF2B2420);        // main text
  static const muted = Color(0xFF6E6459);      // secondary text
  static const outline = Color(0xFFB5AE9F);

  // brand (from the logo)
  static const copper = Color(0xFFB0653A);
  static const copperDeep = Color(0xFF8E4A27);
  static const copperSoft = Color(0xFFD79A6B);

  // dark
  static const darkBg = Color(0xFF1C1814);
  static const darkSurface = Color(0xFF28221C);
  static const darkRaised = Color(0xFF352D25);
}
