import 'package:flutter/material.dart';

/// CareCart design tokens, lifted from the `CareCart App.dc.html` prototype.
abstract final class Cc {
  // paper / ink
  static const paper = Color(0xFFF1F0E4);
  static const paperRaised = Color(0xFFFBFAF2);
  static const paperDim = Color(0xFFE7E5D6);
  static const ink = Color(0xFF15150F);
  static const inkSoft = Color(0xFF20241A);
  static const muted = Color(0xFF7C7E6B);

  // brand
  static const olive = Color(0xFF63753F);
  static const oliveDark = Color(0xFF3E4A28);
  static const sage = Color(0xFFBCD5A3);
  static const sageSoft = Color(0xFFDCE8CE);
  static const accent = Color(0xFFE39B74);
  static const accentDeep = Color(0xFFD07E52);

  // severity (foreground + tint), from SEV{} in CareCart App.dc.html
  static const avoid = Color(0xFFB44F35);
  static const avoidTint = Color(0xFFF4DBD3);
  static const caution = Color(0xFFB8860B);
  static const cautionTint = Color(0xFFF6EBD2);
  static const safe = Color(0xFF4A5A33);
  static const safeTint = Color(0xFFDCE8CE);
}

ThemeData buildCareCartTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Cc.olive,
      surface: Cc.paper,
      primary: Cc.olive,
      secondary: Cc.accent,
      error: Cc.avoid,
    ),
    scaffoldBackgroundColor: Cc.paper,
  );

  // Bricolage Grotesque (display) + DM Sans (body) are the prototype fonts.
  // Add the .ttf files under mobile/assets/fonts/ and declare them in pubspec
  // to switch on; falls back to the platform sans until then.
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Cc.ink,
      displayColor: Cc.inkSoft,
      fontFamily: 'DMSans',
    ),
  );
}
