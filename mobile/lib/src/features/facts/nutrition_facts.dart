import 'package:flutter/material.dart';

import '../../core/text.dart';
import '../../core/theme.dart';

/// Shared "Nutrition — per 100 g" panel, used by the scanned-product screen and
/// the food-search screen so both render the same way. Input is the per-100 g
/// map produced by the backend (Open Food Facts keys: `energy_kcal_100g`, …).

class _Nutrient {
  const _Nutrient(this.label, this.value, this.unit, {this.indent = false});
  final String label;
  final num value;
  final String unit;
  final bool indent;
}

const _kNutritionOrder = <(String, String, String, bool)>[
  ('energy_kcal_100g', 'Energy', 'kcal', false),
  ('fat_g_100g', 'Fat', 'g', false),
  ('saturated_fat_g_100g', 'of which saturates', 'g', true),
  ('carbohydrates_g_100g', 'Carbohydrate', 'g', false),
  ('sugars_g_100g', 'of which sugars', 'g', true),
  ('fiber_g_100g', 'Fibre', 'g', false),
  ('protein_g_100g', 'Protein', 'g', false),
  ('salt_g_100g', 'Salt', 'g', false),
  ('sodium_mg_100g', 'Sodium', 'mg', false),
];

List<_Nutrient> _rows(Map<String, dynamic> n) {
  final out = <_Nutrient>[];
  for (final (key, label, unit, indent) in _kNutritionOrder) {
    final raw = n[key];
    final v = raw is num ? raw : num.tryParse('${raw ?? ''}');
    if (v == null) continue;
    out.add(_Nutrient(label, v, unit, indent: indent));
  }
  return out;
}

String _fmt(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// True if [nutriments] carries at least one value the panel would show.
bool hasNutritionFacts(Map<String, dynamic> nutriments) =>
    _rows(nutriments).isNotEmpty;

class NutritionFactsCard extends StatelessWidget {
  const NutritionFactsCard({
    super.key,
    required this.nutriments,
    this.servingSize,
    required this.emptyText,
  });

  final Map<String, dynamic> nutriments;
  final String? servingSize;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final rows = _rows(nutriments);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Nutrition', style: CcText.h2),
            Text('PER 100 G',
                style: CcText.mono.copyWith(color: Cc.muted, fontSize: 10.5)),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          FactsEmptyNote(emptyText)
        else
          Container(
            decoration: BoxDecoration(
              color: Cc.paperRaised,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0x14151510)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  _NutrientRow(row: rows[i], last: i == rows.length - 1),
              ],
            ),
          ),
        if ((servingSize ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Serving size — ${servingSize!.trim()}',
              style: CcText.bodySm.copyWith(color: Cc.muted)),
        ],
      ],
    );
  }
}

class _NutrientRow extends StatelessWidget {
  const _NutrientRow({required this.row, required this.last});
  final _Nutrient row;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(row.indent ? 26 : 14, 11, 14, 11),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0x11151510))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(row.label,
                style: CcText.body.copyWith(
                    color: row.indent ? Cc.muted : Cc.ink,
                    fontWeight:
                        row.indent ? FontWeight.w400 : FontWeight.w500)),
          ),
          const SizedBox(width: 10),
          Text('${_fmt(row.value)} ${row.unit}',
              style: CcText.mono.copyWith(color: Cc.ink, fontSize: 12.5)),
        ],
      ),
    );
  }
}

/// A soft "nothing here" note, sized to fill its row.
class FactsEmptyNote extends StatelessWidget {
  const FactsEmptyNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Cc.paperRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x14151510)),
        ),
        child: Text(text,
            style: CcText.bodySm.copyWith(color: Cc.muted, height: 1.5)),
      );
}
