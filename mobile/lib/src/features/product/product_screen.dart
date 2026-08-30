import 'package:flutter/material.dart';

import '../../core/product_api.dart';
import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// What a real barcode scan lands on today — the product's facts straight from
/// Open Food Facts (name, brand, nutrition per 100 g, ingredients).
///
/// No CareCart score / tier / "why this verdict": the personalised judgement is
/// gated on the medicines + lifestyle correlation score and is not shown here.
class ProductScreen extends StatelessWidget {
  const ProductScreen({
    super.key,
    required this.product,
    this.onClose,
    this.onScanNext,
  });

  final ScannedProduct product;
  final VoidCallback? onClose;
  final VoidCallback? onScanNext;

  @override
  Widget build(BuildContext context) {
    final rows = _nutritionRows(product.nutriments);
    final offline = product.fromLocalCache || product.stale;

    return CcScreen(
      background: Cc.paper,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ---- header ----
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
            decoration: const BoxDecoration(
              color: Cc.sageSoft,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CcRoundButton(
                        icon: Icons.close_rounded,
                        onTap: onClose,
                        bg: Colors.white.withValues(alpha: 0.55),
                        size: 36),
                    Text(
                        offline
                            ? 'FROM THIS DEVICE'
                            : 'OPEN FOOD FACTS',
                        style: CcText.mono.copyWith(
                            color: Cc.oliveDark.withValues(alpha: 0.75),
                            fontSize: 10.5,
                            letterSpacing: 1.0)),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Thumb(url: product.imageUrl),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.displayName,
                              style: CcText.h1.copyWith(fontSize: 22, height: 1.2)),
                          if ((product.brand ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(product.brand!.trim(),
                                style: CcText.bodySm.copyWith(color: Cc.muted)),
                          ],
                          const SizedBox(height: 6),
                          Text('Barcode ${product.barcode}',
                              style: CcText.mono.copyWith(
                                  color: Cc.oliveDark.withValues(alpha: 0.7),
                                  fontSize: 10.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- nutrition ----
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Nutrition', style: CcText.h2),
                    Text('PER 100 G',
                        style: CcText.mono
                            .copyWith(color: Cc.muted, fontSize: 10.5)),
                  ],
                ),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  _EmptyNote(
                    "Open Food Facts doesn't list nutrition values for this "
                    'product.',
                  )
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
                if ((product.servingSize ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Serving size — ${product.servingSize!.trim()}',
                      style: CcText.bodySm.copyWith(color: Cc.muted)),
                ],

                const SizedBox(height: 22),

                // ---- ingredients ----
                const Text('Ingredients', style: CcText.h2),
                const SizedBox(height: 10),
                _Ingredients(product: product),

                const SizedBox(height: 22),

                // ---- what's not here yet ----
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: Cc.sageSoft,
                      borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    "This is the label as-is. CareCart isn't scoring it against "
                    'your medications, conditions and profile yet — that arrives '
                    'with the medicines + lifestyle score.',
                    style: CcText.bodySm
                        .copyWith(color: Cc.oliveDark, height: 1.5),
                  ),
                ),

                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onScanNext,
                        child: Container(
                          padding: const EdgeInsets.all(15),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: Cc.accent,
                              borderRadius: BorderRadius.circular(999)),
                          child: const Text('Scan next',
                              style: TextStyle(
                                  fontFamily: 'DMSans',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Cc.inkSoft)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: onClose,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 15),
                        decoration: BoxDecoration(
                          color: Cc.paperRaised,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0x1F151510)),
                        ),
                        child: const Text('Home',
                            style: TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Cc.ink)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Thumb extends StatelessWidget {
  const _Thumb({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    final u = (url ?? '').trim();
    if (u.isEmpty) return const CcThumb(size: size, radius: 14);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        u,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const CcThumb(size: size, radius: 14),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : const CcThumb(size: size, radius: 14),
      ),
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
            : const Border(
                bottom: BorderSide(color: Color(0x11151510))),
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

class _Ingredients extends StatelessWidget {
  const _Ingredients({required this.product});
  final ScannedProduct product;

  @override
  Widget build(BuildContext context) {
    final text = (product.ingredientsText ?? '').trim();
    if (text.isNotEmpty) {
      return Text(text,
          style: CcText.body.copyWith(color: const Color(0xFF4A4C3D), height: 1.55));
    }
    if (product.ingredients.isNotEmpty) {
      return Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final ing in product.ingredients)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Cc.paperRaised,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0x14151510)),
              ),
              child: Text(ing, style: CcText.bodySm),
            ),
        ],
      );
    }
    return _EmptyNote(
      "No ingredient list on file for this product. Point the camera at the "
      "pack's ingredients list to read it instead.",
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);
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

// ---------------------------------------------------------------------------

class _Nutrient {
  const _Nutrient(this.label, this.value, this.unit, {this.indent = false});
  final String label;
  final num value;
  final String unit;
  final bool indent;
}

/// The Open Food Facts keys we normalise on the backend, in label order.
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

List<_Nutrient> _nutritionRows(Map<String, dynamic> n) {
  final out = <_Nutrient>[];
  for (final (key, label, unit, indent) in _kNutritionOrder) {
    final raw = n[key];
    final v = raw is num ? raw : num.tryParse('${raw ?? ''}');
    if (v == null) continue;
    out.add(_Nutrient(label, v, unit, indent: indent));
  }
  return out;
}

String _fmt(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1);
}
