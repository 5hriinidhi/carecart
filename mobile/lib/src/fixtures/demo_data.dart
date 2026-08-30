// Hardcoded demo fixtures for the static Phase 2.2 screens.
// Simplified Dart ports of PRODUCTS / HISTORY / MEDS / TREND / TREND_LABELS
// (and the small derived lists) from `CareCart App.dc.html`.
//
// Not wired to the backend - these exist only so the screens have something
// to render while the navigation flow and real data are built later.

import '../core/severity.dart';

const kDietScore = 68;
const kTodayLabel = 'Tuesday, 24 Aug';

// --- flags / nutrients on a product verdict ---------------------------------

class DemoFlag {
  const DemoFlag(this.sev, this.title, this.tag, this.why, {this.alias});
  final Severity sev;
  final String title;
  final String tag;
  final String why;
  final String? alias;
}

class DemoNutrient {
  const DemoNutrient(this.k, this.v, this.pct, this.tone);
  final String k;
  final String v;
  final int pct; // % of the user's ceiling
  final Severity tone;
}

class DemoSwap {
  const DemoSwap(this.name, this.score, this.note);
  final String name;
  final int score;
  final String note;
}

class DemoProduct {
  const DemoProduct({
    required this.id,
    required this.name,
    required this.brand,
    required this.serving,
    required this.barcode,
    required this.score,
    required this.verdict,
    required this.summary,
    required this.flags,
    required this.nutrients,
    required this.swaps,
  });

  final String id;
  final String name;
  final String brand;
  final String serving;
  final String barcode;
  final int score;
  final Severity verdict;
  final String summary;
  final List<DemoFlag> flags;
  final List<DemoNutrient> nutrients;
  final List<DemoSwap> swaps;

  String get verdictLabel => switch (verdict) {
        Severity.avoid => 'Not for you',
        Severity.caution => 'Worth a pause',
        Severity.safe => 'Good for you',
      };

  String get flagsHeading =>
      verdict == Severity.safe ? 'What we checked' : 'Why we flagged it';
}

const kProducts = <String, DemoProduct>{
  'noodles': DemoProduct(
    id: 'noodles',
    name: 'Instant Masala Noodles',
    brand: 'Maggo Foods',
    serving: '70 g pack',
    barcode: '8901• 4472',
    score: 24,
    verdict: Severity.avoid,
    summary:
        'Not for you today. Two ingredients here work directly against your '
        'blood-pressure medication, and one is a sugar in disguise.',
    flags: [
      DemoFlag(Severity.avoid, 'Maltodextrin', 'Diabetes',
          "Despite the 'no added sugar' claim, this raises blood glucose faster than table sugar does.",
          alias: 'starch syrup solids, glucose polymer, dextrin'),
      DemoFlag(Severity.avoid, '1,480 mg sodium', 'Telmisartan',
          "That's 82% of your daily ceiling in one pack, and high sodium blunts how well Telmisartan controls your pressure.",
          alias: 'sodium chloride, MSG (E621), disodium inosinate'),
      DemoFlag(Severity.caution, 'Palm oil, 14 g sat fat', '7-day trend',
          'Your saturated fat has been above target for six days running, so this one adds to a pattern rather than starting one.',
          alias: 'palmolein, vegetable fat'),
    ],
    nutrients: [
      DemoNutrient('Sodium', '1,480 mg', 82, Severity.avoid),
      DemoNutrient('Added sugars (incl. aliases)', '9.4 g', 64, Severity.caution),
      DemoNutrient('Saturated fat', '14 g', 71, Severity.caution),
      DemoNutrient('Fibre', '1.2 g', 8, Severity.safe),
    ],
    swaps: [
      DemoSwap('Millet Atta Noodles', 78, '92% less sodium, no maltodextrin'),
      DemoSwap('Whole Wheat Vermicelli', 71, '4x the fibre, cooks the same way'),
      DemoSwap('Buckwheat Soba', 69, 'Low GI, but check the tamari sachet'),
    ],
  ),
  'chana': DemoProduct(
    id: 'chana',
    name: 'Roasted Chana, Lightly Salted',
    brand: 'Farmveda',
    serving: '30 g',
    barcode: '8904• 2210',
    score: 86,
    verdict: Severity.safe,
    summary:
        'Good pick. Nothing here interacts with your medications, and the fibre '
        "helps the glucose curve you've been working on.",
    flags: [
      DemoFlag(Severity.safe, 'No interactions found', '4 medications',
          'Cross-checked against Telmisartan, Metformin, Atorvastatin and Levothyroxine. Nothing flagged.'),
      DemoFlag(Severity.safe, '7.4 g fibre', 'Diabetes',
          'Slows glucose absorption - useful for you specifically, not just generically healthy.'),
      DemoFlag(Severity.caution, '210 mg sodium', 'Portion',
          'Fine at one 30 g portion. Two portions puts you at a quarter of your daily ceiling before lunch.',
          alias: 'sodium chloride'),
    ],
    nutrients: [
      DemoNutrient('Sodium', '210 mg', 12, Severity.safe),
      DemoNutrient('Fibre', '7.4 g', 62, Severity.safe),
      DemoNutrient('Added sugars', '0 g', 0, Severity.safe),
      DemoNutrient('Protein', '6.8 g', 44, Severity.safe),
    ],
    swaps: [],
  ),
  'juice': DemoProduct(
    id: 'juice',
    name: 'Mixed Fruit Juice, No Added Sugar',
    brand: 'Realis',
    serving: '200 ml',
    barcode: '8901• 7735',
    score: 52, // caution band — chipFor(52) == Severity.caution
    verdict: Severity.caution,
    summary:
        'Worth a second thought. The label is honest about added sugar but says '
        'nothing about the fruit concentrate, which behaves the same way in your blood.',
    flags: [
      DemoFlag(Severity.caution, 'Fruit juice concentrate', 'Diabetes',
          "Legally not 'added sugar', but 21 g of free sugars per glass with the fibre stripped out.",
          alias: 'fruit solids, reconstituted juice, apple juice concentrate'),
      DemoFlag(Severity.caution, 'Potassium 480 mg', 'Telmisartan',
          'Telmisartan already raises potassium. One glass is fine; daily glasses are worth mentioning to your doctor.'),
      DemoFlag(Severity.safe, 'No preservative conflicts', '4 medications',
          'The preservative system is clear against everything on your list.'),
    ],
    nutrients: [
      DemoNutrient('Free sugars', '21 g', 88, Severity.avoid),
      DemoNutrient('Potassium', '480 mg', 46, Severity.caution),
      DemoNutrient('Fibre', '0.3 g', 2, Severity.caution),
      DemoNutrient('Sodium', '15 mg', 2, Severity.safe),
    ],
    swaps: [
      DemoSwap('Whole orange, 1 medium', 92, 'Same vitamin C, fibre intact, no concentrate'),
      DemoSwap('Sparkling water + lime', 88, 'Zero free sugars, same ritual'),
    ],
  ),
};

/// The three products offered on the Scan screen's demo picker.
const kDemoPickOrder = ['noodles', 'juice', 'chana'];

// --- history --------------------------------------------------------------

class DemoScan {
  const DemoScan(this.pid, this.name, this.note, this.when, this.score);
  final String pid;
  final String name;
  final String note;
  final String when;
  final int score;
}

class DemoHistoryDay {
  const DemoHistoryDay(this.day, this.dayScore, this.items);
  final String day;
  final int dayScore;
  final List<DemoScan> items;
}

const kHistory = <DemoHistoryDay>[
  DemoHistoryDay('Today · 24 Aug', 71, [
    DemoScan('chana', 'Roasted Chana, Lightly Salted', 'Clean · high fibre', '18:40', 86),
    DemoScan('juice', 'Mixed Fruit Juice', 'Free sugars 88% of ceiling', '13:05', 52),
  ]),
  DemoHistoryDay('Yesterday · 23 Aug', 58, [
    DemoScan('noodles', 'Instant Masala Noodles', 'Sodium + maltodextrin', '20:15', 24),
    DemoScan('chana', 'Roasted Chana', 'Clean', '16:20', 86),
    DemoScan('juice', 'Mixed Fruit Juice', 'Free sugars high', '09:10', 52),
  ]),
  DemoHistoryDay('Fri · 21 Aug', 64, [
    DemoScan('noodles', 'Instant Masala Noodles', 'Third time this week', '13:30', 24),
    DemoScan('chana', 'Multigrain Khakhra', 'Clean · watch portion', '11:00', 74),
  ]),
];

/// "Today" list on the home screen = first history day's items.
List<DemoScan> get kTodayScans => kHistory.first.items;

// --- medications --------------------------------------------------------------

class DemoMed {
  const DemoMed(this.name, this.dose, this.schedule, this.watch, {this.on = true});
  final String name;
  final String dose;
  final String schedule;
  final List<String> watch;
  final bool on;

  String get initial => name.substring(0, 1);
}

const kMeds = <DemoMed>[
  DemoMed('Telmisartan', '40 mg', 'morning',
      ['High sodium', 'Potassium-rich', 'Liquorice', 'Salt substitutes']),
  DemoMed('Metformin', '500 mg', 'twice daily',
      ['Maltodextrin', 'Alcohol', 'High-GI starches']),
  DemoMed('Atorvastatin', '10 mg', 'night', ['Grapefruit', 'Pomelo', 'Excess sat fat']),
  DemoMed('Levothyroxine', '50 mcg', 'empty stomach',
      ['Soy protein', 'Calcium-fortified', 'Iron supplements'], on: false),
];

const kConditions = ['Type 2 diabetes', 'Hypertension', 'Hypothyroidism', 'High LDL'];

// --- trend ----------------------------------------------------------------

const kTrend = <String, List<int>>{
  '7d': [58, 61, 57, 64, 62, 66, 68],
  '30d': [49, 53, 51, 56, 58, 55, 60, 62, 59, 64, 66, 68],
  '90d': [41, 45, 44, 49, 52, 55, 57, 60, 62, 65, 66, 68],
};

const kTrendLabels = <String, List<String>>{
  '7d': ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
  '30d': ['w1', '', 'w2', '', 'w3', '', 'w4', '', 'w5', '', '', 'now'],
  '90d': ['Jun', '', '', 'Jul', '', '', 'Aug', '', '', '', '', 'now'],
};

const kRangeLabels = <String, String>{
  '7d': 'Mon 18 – Sun 24 Aug',
  '30d': 'Rolling 30 days',
  '90d': 'Jun – Aug',
};

class DemoTrajectory {
  const DemoTrajectory(this.k, this.delta, this.tone, this.bars, this.note);
  final String k;
  final String delta;
  final Severity tone;
  final List<int> bars; // 0-100 heights
  final String note;
}

const kTrajectories = <DemoTrajectory>[
  DemoTrajectory('Sodium', '+12% vs target', Severity.avoid,
      [40, 55, 72, 48, 80, 35, 90, 62, 88, 44, 76, 58],
      'Driven by weekday lunches. Three scans account for most of it.'),
  DemoTrajectory('Free sugars', '-18% this month', Severity.safe,
      [82, 74, 70, 66, 58, 60, 52, 48, 44, 40, 38, 34],
      'Cutting the juice glass did most of the work here.'),
  DemoTrajectory('Fibre', 'On target', Severity.safe,
      [30, 42, 48, 55, 52, 60, 64, 58, 66, 70, 68, 72],
      'Chana and khakhra are carrying this. Keep them in the rotation.'),
  DemoTrajectory('Saturated fat', 'Drifting up', Severity.caution,
      [45, 48, 52, 50, 58, 62, 60, 66, 70, 68, 74, 72],
      'Six days above target. Worth watching before it becomes a habit.'),
];

// --- nudge -------------------------------------------------------------------

const kNudgeScans = <DemoScan>[
  DemoScan('noodles', 'Instant Masala Noodles', '1,480 mg sodium', 'Tue', 24),
  DemoScan('noodles', 'Instant Masala Noodles', '1,480 mg sodium', 'Wed', 24),
  DemoScan('noodles', 'Salted Butter Biscuits', '620 mg sodium', 'Thu', 38),
];

// --- profiles ---------------------------------------------------------------

class DemoProfile {
  const DemoProfile(this.name, this.detail, this.initial, {this.active = false});
  final String name;
  final String detail;
  final String initial;
  final bool active;
}

const kProfiles = <DemoProfile>[
  DemoProfile('Aarav Deshmukh', 'You · 4 medications, 4 conditions', 'A', active: true),
  DemoProfile('Sunita Deshmukh', 'Mother, 68 · CKD stage 3, 6 medications', 'S'),
  DemoProfile('Ira Deshmukh', 'Daughter, 7 · Peanut and dairy allergy', 'I'),
];

// --- analyzing --------------------------------------------------------------

const kAnalyzeSteps = [
  'Reading the label',
  'Cross-checking 4 medications',
  'Scoring against your profile',
  'Finding safer swaps',
];
