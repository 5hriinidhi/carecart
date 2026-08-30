import 'package:flutter/material.dart';

import '../../core/foods_api.dart';
import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'nutrition_facts.dart';

/// The facts for one food from the everyday-food dataset — the "search only"
/// counterpart to the barcode [ProductScreen]. Same as that screen: no CareCart
/// score / verdict yet; that arrives with the medicines + lifestyle score.
class FoodScreen extends StatelessWidget {
  const FoodScreen({super.key, required this.food, this.onClose});

  final FoodHit food;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
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
                    Text(food.isPackaged ? 'PACKAGED FOOD' : 'HOME DISH',
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
                    const CcThumb(size: 64, radius: 14),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(food.name,
                              style:
                                  CcText.h1.copyWith(fontSize: 22, height: 1.2)),
                          if (food.subtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(food.subtitle,
                                style: CcText.bodySm.copyWith(color: Cc.muted)),
                          ],
                          if ((food.diet ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _Chip(food.diet!.trim()),
                          ],
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
                NutritionFactsCard(
                  nutriments: food.nutriments,
                  servingSize: food.servingSize,
                  emptyText: food.isPackaged
                      ? "This product doesn't have a nutrition panel on file."
                      : 'This is a home-cooked dish — the dataset lists what goes '
                          'in it, not a per-100 g nutrition panel.',
                ),
                const SizedBox(height: 22),
                const Text('Ingredients', style: CcText.h2),
                const SizedBox(height: 10),
                if ((food.ingredientsText ?? '').trim().isNotEmpty)
                  Text(food.ingredientsText!.trim(),
                      style: CcText.body.copyWith(
                          color: const Color(0xFF4A4C3D), height: 1.55))
                else
                  const FactsEmptyNote(
                      'No ingredient list on file for this item.'),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: Cc.sageSoft,
                      borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    "These are the facts as the dataset has them. CareCart isn't "
                    'scoring this against your medications, conditions and '
                    'profile yet — that arrives with the medicines + lifestyle '
                    'score.',
                    style: CcText.bodySm
                        .copyWith(color: Cc.oliveDark, height: 1.5),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onClose,
                    child: const Text('Search another'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(999)),
        child: Text(text.toUpperCase(),
            style: CcText.mono.copyWith(
                color: Cc.oliveDark, fontSize: 10, letterSpacing: 0.8)),
      );
}
