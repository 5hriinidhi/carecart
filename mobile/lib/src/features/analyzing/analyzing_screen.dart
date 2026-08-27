import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/text.dart';
import '../../core/theme.dart';
import '../../fixtures/demo_data.dart';

/// Static analyzing screen — `state.screen == 'analyzing'`. Shown here frozen
/// with step 3 of 4 in progress.
class AnalyzingScreen extends StatelessWidget {
  const AnalyzingScreen({super.key, this.activeStep = 2});
  final int activeStep; // 0-based; steps before it are "done"

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Cc.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 34),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 74,
                height: 74,
                child: CustomPaint(painter: _SpinnerPainter()),
              ),
              const SizedBox(height: 30),
              const Text('Setting up your verdict',
                  style: TextStyle(
                      fontFamily: 'Bricolage',
                      fontSize: 20,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: Cc.ink)),
              const SizedBox(height: 6),
              Text('This stays on your phone.',
                  style: CcText.body.copyWith(color: Cc.muted)),
              const SizedBox(height: 30),
              for (var i = 0; i < kAnalyzeSteps.length; i++) ...[
                _StepRow(
                  label: kAnalyzeSteps[i],
                  done: i < activeStep,
                  active: i == activeStep,
                ),
                if (i != kAnalyzeSteps.length - 1) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.done, required this.active});
  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final dotColor =
        done ? Cc.olive : (active ? Cc.accent : const Color(0x24202419));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Cc.paperRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x12151510)),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            child: done
                ? const Icon(Icons.check_rounded, size: 13, color: Cc.paper)
                : null,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 13,
                    fontWeight: done || active ? FontWeight.w500 : FontWeight.w400,
                    color: done || active ? Cc.ink : const Color(0xFFA3A491))),
          ),
        ],
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 2.5;
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = const Color(0x2E63753F));
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 0.9,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = Cc.olive);
    canvas.drawArc(
        rect,
        math.pi / 2,
        math.pi * 0.5,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = Cc.accent);
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => false;
}
