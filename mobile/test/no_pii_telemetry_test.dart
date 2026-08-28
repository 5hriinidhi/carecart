// Guardrail (all phases): data entered during onboarding — phone number,
// medication names, gender, body measurements, diet, allergies — and, from
// Phase 3, real health data must NEVER be handed to analytics or
// crash-reporting tools. Right now the app has no such tooling; this test
// fails loudly the moment any is added, or the moment raw logging that could
// capture interpolated user data lands in production code, so the PII-scrubbing
// decision is made deliberately rather than by accident.
//
//   flutter test test/no_pii_telemetry_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _bannedPackages = <String>[
  'firebase_analytics',
  'firebase_crashlytics',
  'firebase_performance',
  'sentry',
  'sentry_flutter',
  'sentry_dart_plugin',
  'mixpanel_flutter',
  'amplitude_flutter',
  'amplitude',
  'posthog_flutter',
  'datadog_flutter_plugin',
  'bugsnag_flutter',
  'flutter_appcenter_bundle',
  'segment_analytics',
  'countly_flutter',
  'google_analytics',
  'appsflyer_sdk',
  'facebook_app_events',
];

Iterable<File> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('no analytics / crash-reporting / telemetry package is a dependency', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final hits = _bannedPackages
        .where((p) => RegExp('^\\s+${RegExp.escape(p)}\\s*:', multiLine: true)
            .hasMatch(pubspec))
        .toList();
    expect(
      hits,
      isEmpty,
      reason: 'Telemetry SDK(s) added to pubspec: $hits.\n'
          'Onboarding + health data must be scrubbed of PII before anything '
          'like this is wired up (see CLAUDE.md "Privacy & telemetry"). '
          'If this is intentional, update that policy and this allow-list in '
          'the same change.',
    );
  });

  test('no raw print / debugPrint in production code (lib/)', () {
    final rx = RegExp(r'(?<![\w.])(print|debugPrint)\s*\(');
    final offenders = <String>[];
    for (final f in _dartFiles('lib')) {
      final src = f.readAsStringSync();
      for (final m in rx.allMatches(src)) {
        final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        offenders.add('${f.path.replaceAll(r'\', '/')}:$line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Raw logging in production code can silently emit interpolated '
          'user data. Route logs through a scrubbing logger instead:\n'
          '${offenders.join('\n')}',
    );
  });

  test('Dio has no payload-dumping LogInterceptor', () {
    final offenders = <String>[];
    for (final f in _dartFiles('lib')) {
      final src = f.readAsStringSync();
      if (src.contains('LogInterceptor(') &&
          (src.contains('requestBody: true') ||
              src.contains('responseBody: true'))) {
        offenders.add(f.path.replaceAll(r'\', '/'));
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Dio LogInterceptor(requestBody/responseBody: true) writes full '
          'request/response bodies to the log — phone numbers, medications, '
          'scan payloads. Not allowed here: $offenders',
    );
  });
}
