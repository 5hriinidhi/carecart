import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/vault_api.dart';
import '../../core/widgets.dart';
import 'add_medication_sheet.dart';
import 'pin_dialog.dart';

/// Medications screen — `state.screen == 'meds'`. Wired to `GET /me/medications`
/// (Phase 3.2). These are what every scanned label gets cross-checked against.
///
/// Adding (searchable picker) and removing a medication are both guarded by the
/// on-device PIN ([showMedPinDialog]).
class MedsScreen extends ConsumerWidget {
  const MedsScreen({super.key, this.onNav, this.onScan});
  final void Function(String route)? onNav;
  final VoidCallback? onScan;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final added = await showAddMedicationSheet(context);
    if (added) {
      ref.invalidate(medicationsProvider);
      ref.invalidate(medicationMappingProvider);
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, Medication med) async {
    final unlocked = await showMedPinDialog(context, ref,
        actionLabel: 'remove ${med.name}');
    if (!unlocked || !context.mounted) return;

    final res = await ref.read(vaultApiProvider).deleteMedication(med.id);
    if (!context.mounted) return;
    if (res is VaultError) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(res.message)));
      return;
    }
    ref.invalidate(medicationsProvider);
    ref.invalidate(medicationMappingProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(medicationsProvider);
    final mapping = ref.watch(medicationMappingProvider).asData?.value ??
        const <String, MedMapping>{};

    return CcScreen(
      background: Cc.paper,
      child: ListView(
        primary: false,
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        children: [
          const SizedBox(height: 6),
          const Text('Medications', style: CcText.h1),
          const SizedBox(height: 4),
          Text('Each one changes what we flag on a label.',
              style: CcText.body.copyWith(color: Cc.muted)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('meds-add-button'),
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add a medication'),
            ),
          ),
          const SizedBox(height: 16),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 36),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, _) => _note("Couldn't load your medications."),
            data: (r) => switch (r) {
              MedicationsFailed(:final message) => _note(message),
              MedicationsLoaded(:final items) when items.isEmpty => _note(
                  'No medications on file. Add them during setup or with the '
                  'button above so scans can cross-check against them.'),
              MedicationsLoaded(:final items) => Column(
                  key: const Key('meds-list'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final m in items) ...[
                      _MedCard(
                          med: m,
                          mapping: mapping[m.name],
                          onDelete: () => _delete(context, ref, m)),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
            },
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: const Color(0xFFEAEADB),
                borderRadius: BorderRadius.circular(20)),
            child: Text(
              'Stored encrypted on device. Adding or removing one needs your '
              'PIN. Nothing leaves the phone without you saying so — and you can '
              'delete all of it in one tap from your profile.',
              style: CcText.bodySm.copyWith(color: Cc.muted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(text,
            key: const Key('meds-note'),
            style: CcText.body.copyWith(color: Cc.muted, height: 1.5)),
      );
}

class _MedCard extends StatelessWidget {
  const _MedCard({required this.med, this.mapping, this.onDelete});
  final Medication med;
  final MedMapping? mapping;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final initial = med.name.isEmpty ? '?' : med.name[0].toUpperCase();
    final map = mapping;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: Cc.paperRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x12151510)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Cc.safeTint,
                    borderRadius: BorderRadius.circular(12)),
                child: Text(initial,
                    style: const TextStyle(
                        fontFamily: 'Bricolage',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Cc.oliveDark)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(med.name,
                        style: const TextStyle(
                            fontFamily: 'Bricolage',
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: Cc.ink)),
                    if ((med.dosage ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(med.dosage!,
                          style: CcText.bodySm.copyWith(color: Cc.muted)),
                    ],
                    if (map != null && map.identified &&
                        map.drugClasses.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(map.drugClasses.join(' · '),
                          style: CcText.mono.copyWith(
                              color: Cc.oliveDark, fontSize: 10.5)),
                    ],
                  ],
                ),
              ),
              IconButton(
                key: Key('med-delete-${med.id}'),
                tooltip: 'Remove',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 20, color: Cc.muted),
              ),
            ],
          ),
          if (map != null) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0x11151510)),
            const SizedBox(height: 9),
            if (!map.identified)
              Text("Couldn't match this to a drug class — it won't affect "
                  'label verdicts.',
                  style: CcText.bodySm.copyWith(color: Cc.muted, fontSize: 11.5))
            else if (map.interactions.isEmpty)
              Text('No known food interactions.',
                  style: CcText.bodySm.copyWith(color: Cc.muted, fontSize: 11.5))
            else ...[
              Text('FOODS WE WATCH FOR YOU',
                  style: CcText.mono.copyWith(
                      color: const Color(0xFFA3A491),
                      fontSize: 9.5,
                      letterSpacing: 0.8)),
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in map.interactions)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7E2D5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(f,
                          style: CcText.bodySm.copyWith(
                              color: const Color(0xFF8A4526), fontSize: 11.5)),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
