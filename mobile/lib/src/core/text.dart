import 'package:flutter/material.dart';

import 'theme.dart';

/// The prototype's type ramp. The real faces — Bricolage Grotesque (display),
/// DM Sans (body), DM Mono (labels) — are vendored under assets/fonts/ and
/// declared in pubspec, so they are bundled (no runtime Google Fonts fetch).
/// [kCcFontFallback] keeps metrics sane if an asset ever fails to load.
abstract final class CcText {
  static const _display = 'Bricolage';
  static const _sans = 'DMSans';
  static const _mono = 'DMMono';
  static const _fb = kCcFontFallback;

  // display / headings (Bricolage Grotesque, weights 700-800)
  static const h1 = TextStyle(
      fontFamily: _display,
      fontFamilyFallback: _fb,
      fontSize: 25,
      height: 1.15,
      fontWeight: FontWeight.w700,
      color: Cc.ink);
  static const hero = TextStyle(
      fontFamily: _display,
      fontFamilyFallback: _fb,
      fontSize: 62,
      height: .82,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.8,
      color: Cc.ink);
  static const h2 = TextStyle(
      fontFamily: _display,
      fontFamilyFallback: _fb,
      fontSize: 16,
      height: 1.2,
      fontWeight: FontWeight.w700,
      color: Cc.ink);
  static const h3 = TextStyle(
      fontFamily: _display,
      fontFamilyFallback: _fb,
      fontSize: 13.5,
      height: 1.2,
      fontWeight: FontWeight.w700,
      color: Cc.ink);

  // body (DM Sans)
  static const body = TextStyle(
      fontFamily: _sans,
      fontFamilyFallback: _fb,
      fontSize: 12.5,
      height: 1.5,
      color: Cc.ink);
  static const bodySm = TextStyle(
      fontFamily: _sans,
      fontFamilyFallback: _fb,
      fontSize: 11.5,
      height: 1.35,
      color: Cc.muted);
  static const listTitle = TextStyle(
      fontFamily: _sans,
      fontFamilyFallback: _fb,
      fontSize: 13.5,
      height: 1.25,
      fontWeight: FontWeight.w500,
      color: Cc.ink);

  // labels / numerals (DM Mono, uppercased + tracked)
  static const label = TextStyle(
      fontFamily: _mono,
      fontFamilyFallback: _fb,
      fontSize: 10.5,
      fontWeight: FontWeight.w500,
      letterSpacing: 1.05,
      color: Cc.muted);
  static const mono = TextStyle(
      fontFamily: _mono,
      fontFamilyFallback: _fb,
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: Cc.muted);

  static TextStyle chipNum(Color c) => TextStyle(
      fontFamily: _display,
      fontFamilyFallback: _fb,
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: c);
}
