// Step 7 — the CareCart Fit screen: overall score up top, a Lifestyle section
// and a Medicines section, each with its own rails.

import 'package:carecart/src/core/fit_api.dart';
import 'package:carecart/src/core/lifestyle_api.dart';
import 'package:carecart/src/features/fit/fit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

const _fitJson = {
  'score': 61,
  'tier': 'some tension',
  'delta': -3,
  'lifestyle': {
    'overall': 78,
    'answered': 5,
    'total': 5,
    'dims': [
      {'key': 'sleep', 'label': 'Sleep', 'score': 100, 'weight': 0.24,
       'detail': '7.5 h — in the 7-9 h target band'},
      {'key': 'stress', 'label': 'Stress', 'score': 42, 'weight': 0.16,
       'detail': 'Self-rated 4/5'},
    ],
  },
  'medicines': {
    'overall': 44,
    'scans_in_window': 12,
    'meds': [
      {'name': 'Telmisartan 40', 'identified': true, 'score': 37,
       'note': 'Sodium flagged in 80% of recent scans',
       'interactions': ['Sodium', 'Potassium']},
    ],
  },
  'focus': {
    'area': 'medicines', 'key': 'Telmisartan 40', 'label': 'Telmisartan 40',
    'score': 37,
    'message': 'Your recent scans are working against Telmisartan 40.',
  },
};

Future<void> _pump(WidgetTester tester, FitResult result) async {
  tester.view.physicalSize = const Size(430, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(
    overrides: fakeBackendOverrides(fit: FakeFitApi(result)),
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: FitScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('Fit.fromJson parses both halves + focus', () {
    final f = Fit.fromJson(Map<String, dynamic>.from(_fitJson));
    expect(f.score, 61);
    expect(f.tier, 'some tension');
    expect(f.lifestyle.dims.map((d) => d.key), ['sleep', 'stress']);
    expect(f.medicines.meds.single.score, 37);
    expect(f.medicines.meds.single.interactions, ['Sodium', 'Potassium']);
    expect(f.focus!.area, 'medicines');
  });

  test('LifestyleProfile round-trips through JSON', () {
    const p = LifestyleProfile(
        sleepHours: 7.5, exerciseDays: 4, smoking: 'none',
        alcohol: 'occasional', stress: 3);
    final back = LifestyleProfile.fromJson(p.toJson());
    expect(back.sleepHours, 7.5);
    expect(back.exerciseDays, 4);
    expect(back.stress, 3);
    // an all-null profile serialises to {}
    expect(const LifestyleProfile().toJson(), isEmpty);
  });

  testWidgets('renders the score, a Lifestyle section and a Medicines section',
      (tester) async {
    await _pump(tester, FitLoaded(Fit.fromJson(Map<String, dynamic>.from(_fitJson))));

    expect(find.byKey(const Key('fit-score')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('fit-score'))).data, '61');
    expect(find.text('Some tension'), findsOneWidget);
    expect(find.text('Lifestyle'), findsOneWidget);
    expect(find.text('Medicines'), findsOneWidget);
    expect(find.byKey(const Key('fit-life-sleep')), findsOneWidget);
    expect(find.byKey(const Key('fit-life-stress')), findsOneWidget);
    expect(find.byKey(const Key('fit-med-Telmisartan 40')), findsOneWidget);
    expect(find.text('WHERE TO FOCUS'), findsOneWidget);
    expect(find.textContaining('working against Telmisartan'), findsOneWidget);
  });

  testWidgets('no data -> a prompt, not a broken screen', (tester) async {
    await _pump(
      tester,
      const FitLoaded(Fit(
        score: null,
        tier: null,
        lifestyle: FitLifestyle(),
        medicines: FitMedicines(),
      )),
    );
    expect(tester.widget<Text>(find.byKey(const Key('fit-score'))).data, '–');
    expect(find.textContaining('Answer the lifestyle questions'), findsOneWidget);
    expect(find.textContaining('haven’t answered the lifestyle questions'),
        findsOneWidget);
    expect(find.textContaining('No medications on file'), findsOneWidget);
  });
}
