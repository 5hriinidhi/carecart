// Edge case: the prototype's typefaces must NOT depend on a network fetch on
// first run. They are vendored under assets/fonts/ and declared in pubspec, so
// they ride in the asset bundle. This test proves the wiring: the FontManifest
// lists all three families and every .ttf loads from the bundle with real bytes.

import 'dart:convert';

import 'package:carecart/src/core/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FontManifest declares Bricolage / DMSans / DMMono', () async {
    final raw = await rootBundle.loadString('FontManifest.json');
    final manifest = (json.decode(raw) as List).cast<Map<String, dynamic>>();
    final families = manifest.map((e) => e['family'] as String).toSet();

    expect(families, containsAll(<String>{'Bricolage', 'DMSans', 'DMMono'}));

    // DM Mono ships static Regular + Medium; the other two are variable (1 asset)
    final dmmono = manifest.firstWhere((e) => e['family'] == 'DMMono');
    expect((dmmono['fonts'] as List), hasLength(2));
  });

  test('every declared font asset loads from the bundle with real bytes', () async {
    const assets = [
      'assets/fonts/BricolageGrotesque-VariableFont.ttf',
      'assets/fonts/DMSans-VariableFont.ttf',
      'assets/fonts/DMMono-Regular.ttf',
      'assets/fonts/DMMono-Medium.ttf',
    ];
    for (final a in assets) {
      final data = await rootBundle.load(a);
      expect(data.lengthInBytes, greaterThan(20000), reason: '$a looks empty');
      // TrueType/OpenType magic: 0x00010000, "true", "OTTO", or "ttcf"
      final b = data.buffer.asUint8List(0, 4);
      final magic = b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3];
      const validMagics = {0x00010000, 0x74727565, 0x4F54544F, 0x74746366};
      expect(validMagics.contains(magic), isTrue,
          reason: '$a is not a valid sfnt font (magic 0x${magic.toRadixString(16)})');
    }
  });

  test('a fallback chain is defined for the custom families', () {
    expect(kCcFontFallback, isNotEmpty);
    expect(kCcFontFallback, contains('sans-serif'));
  });
}
