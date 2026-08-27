import 'package:flutter/material.dart';

import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../fixtures/demo_data.dart';

/// Static medications screen — `state.screen == 'meds'`.
class MedsScreen extends StatelessWidget {
  const MedsScreen({super.key, this.onNav, this.onScan});
  final void Function(String route)? onNav;
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Cc.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
          children: [
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(child: Text('Medications', style: CcText.h1)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                      color: Cc.safeTint, borderRadius: BorderRadius.circular(999)),
                  child: Text('Scan Rx',
                      style: CcText.bodySm.copyWith(
                          color: Cc.oliveDark, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Cc.olive, shape: BoxShape.circle),
                  child: const Icon(Icons.add_rounded, color: Cc.paper, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Each one changes what we flag on a label.',
                style: CcText.body.copyWith(color: Cc.muted)),
            const SizedBox(height: 16),
            for (final m in kMeds) ...[
              _MedCard(med: m),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFFEAEADB), borderRadius: BorderRadius.circular(20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Conditions on file',
                      style: TextStyle(
                          fontFamily: 'Bricolage',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Cc.ink)),
                  const SizedBox(height: 11),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final c in kConditions)
                        Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: Cc.paperRaised,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0x14151510)),
                          ),
                          child: Text(c,
                              style: CcText.bodySm.copyWith(
                                  color: Cc.oliveDark, fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                      'Stored encrypted on device. Nothing leaves the phone without you saying so.',
                      style: CcText.bodySm.copyWith(color: Cc.muted, height: 1.5)),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          CcBottomNav(active: 'meds', onTapItem: onNav, onTapScan: onScan),
    );
  }
}

class _MedCard extends StatelessWidget {
  const _MedCard({required this.med});
  final DemoMed med;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(
        color: Cc.paperRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x12151510)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Cc.safeTint, borderRadius: BorderRadius.circular(12)),
                child: Text(med.initial,
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
                    const SizedBox(height: 3),
                    Text('${med.dose} · ${med.schedule}',
                        style: CcText.bodySm.copyWith(color: Cc.muted)),
                  ],
                ),
              ),
              _Toggle(on: med.on),
            ],
          ),
          const SizedBox(height: 12),
          const _DashDivider(),
          const SizedBox(height: 12),
          Text('FOODS WE WATCH FOR YOU',
              style: CcText.mono.copyWith(
                  color: const Color(0xFFA3A491), letterSpacing: 0.84, fontSize: 10.5)),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final w in med.on ? med.watch : const <String>[])
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF7E2D5),
                      borderRadius: BorderRadius.circular(999)),
                  child: Text(w,
                      style: CcText.bodySm.copyWith(color: const Color(0xFF8A4526))),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 25,
      padding: const EdgeInsets.all(3),
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: on ? Cc.olive : const Color(0x2E202419),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Container(
        width: 19,
        height: 19,
        decoration: const BoxDecoration(color: Cc.paperRaised, shape: BoxShape.circle),
      ),
    );
  }
}

class _DashDivider extends StatelessWidget {
  const _DashDivider();
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const dash = 4.0, gap = 4.0;
        final n = (c.maxWidth / (dash + gap)).floor();
        return Row(
          children: List.generate(
            n,
            (_) => Container(
              width: dash,
              height: 1,
              margin: const EdgeInsets.only(right: gap),
              color: const Color(0x24202419),
            ),
          ),
        );
      },
    );
  }
}
