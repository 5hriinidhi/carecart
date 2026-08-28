import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/severity.dart';
import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../fixtures/demo_data.dart';

/// True under `flutter test` — used to skip the real camera (no plugin there).
bool get _inFlutterTest =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

/// Scan screen — `state.screen == 'scan'`. Live camera barcode reader
/// ([onBarcode]) + a manual-entry field + the demo product picker.
class ScanScreen extends StatelessWidget {
  const ScanScreen({
    super.key,
    this.onBack,
    this.onPick,
    this.onBarcode,
    this.cameraEnabled = true,
  });
  final VoidCallback? onBack;
  final void Function(String pid)? onPick;

  /// Called with a decoded barcode (from the camera or the manual field).
  final void Function(String barcode)? onBarcode;

  /// Off in the debug gallery / tests, where there's no camera plugin.
  final bool cameraEnabled;

  bool get _showCamera => cameraEnabled && !_inFlutterTest;

  static const _paper70 = Color(0xB3F1F0E4);

  @override
  Widget build(BuildContext context) {
    return CcScreen(
      background: const Color(0xFF14170F),
      safeBottom: true,
      child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CcRoundButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: onBack,
                      bg: const Color(0x24F1F0E4),
                      fg: Cc.paper),
                  Text('SCAN LABEL',
                      style: CcText.mono
                          .copyWith(color: _paper70, letterSpacing: 0.96, fontSize: 12)),
                  const CcRoundButton(
                      icon: Icons.tune_rounded, bg: Color(0x24F1F0E4), fg: Cc.paper),
                ],
              ),
            ),
            // Viewfinder centres in the free space when it fits; on short
            // screens the whole area scrolls so nothing clips.
            Expanded(
              child: LayoutBuilder(
                builder: (context, cons) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: cons.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _showCamera
                                  ? _BarcodeCamera(onDetect: onBarcode)
                                  : _Viewfinder(),
                              const SizedBox(height: 22),
                              const Text('Hold the barcode in the frame',
                                  style: TextStyle(
                                      fontFamily: 'Bricolage',
                                      fontSize: 18,
                                      height: 1.3,
                                      fontWeight: FontWeight.w700,
                                      color: Cc.paper)),
                              const SizedBox(height: 6),
                              const SizedBox(
                                width: 250,
                                child: Text(
                                  "No barcode on the pack? Point at the ingredients list instead — we'll read the text.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontFamily: 'DMSans',
                                      fontSize: 12.5,
                                      height: 1.5,
                                      color: Color(0x9EF1F0E4)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ENTER A BARCODE',
                                  style: CcText.mono.copyWith(
                                      color: const Color(0x73F1F0E4),
                                      letterSpacing: 1.05,
                                      fontSize: 10.5)),
                              const SizedBox(height: 9),
                              _ManualBarcodeField(onSubmit: onBarcode),
                              const SizedBox(height: 18),
                              Text('DEMO — PICK A PRODUCT TO SCAN',
                                  style: CcText.mono.copyWith(
                                      color: const Color(0x73F1F0E4),
                                      letterSpacing: 1.05,
                                      fontSize: 10.5)),
                              const SizedBox(height: 9),
                              for (final pid in kDemoPickOrder) ...[
                                _DemoRow(
                                    product: kProducts[pid]!,
                                    onTap: () => onPick?.call(pid)),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }
}

class _Viewfinder extends StatelessWidget {
  static const _sage = Cc.sage;

  Widget _corner({bool top = true, bool left = true}) {
    const w = 3.0;
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: left ? 0 : null,
      right: left ? null : 0,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          border: Border(
            top: top ? const BorderSide(color: _sage, width: w) : BorderSide.none,
            bottom: !top ? const BorderSide(color: _sage, width: w) : BorderSide.none,
            left: left ? const BorderSide(color: _sage, width: w) : BorderSide.none,
            right: !left ? const BorderSide(color: _sage, width: w) : BorderSide.none,
          ),
          borderRadius: BorderRadius.only(
            topLeft: top && left ? const Radius.circular(16) : Radius.zero,
            topRight: top && !left ? const Radius.circular(16) : Radius.zero,
            bottomLeft: !top && left ? const Radius.circular(16) : Radius.zero,
            bottomRight: !top && !left ? const Radius.circular(16) : Radius.zero,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 246,
      height: 170,
      decoration: BoxDecoration(
        color: const Color(0x12BCD5A3),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // faint barcode
          Opacity(
            opacity: 0.28,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 22; i++)
                  Container(
                    width: i % 4 == 0 ? 4 : (i % 3 == 0 ? 3 : 1.5),
                    height: 96,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    color: Cc.paper,
                  ),
              ],
            ),
          ),
          // sweep line
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            height: 2,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Colors.transparent, Cc.accent, Colors.transparent]),
            ),
          ),
          _corner(top: true, left: true),
          _corner(top: true, left: false),
          _corner(top: false, left: true),
          _corner(top: false, left: false),
        ],
      ),
    );
  }
}

class _DemoRow extends StatelessWidget {
  const _DemoRow({required this.product, this.onTap});
  final DemoProduct product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0x17F1F0E4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x24F1F0E4)),
        ),
        child: Row(
          children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: chipFor(product.score).color, shape: BoxShape.circle)),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      style: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Cc.paper)),
                  const SizedBox(height: 2),
                  Text(product.brand,
                      style: const TextStyle(
                          fontFamily: 'DMSans', fontSize: 11, color: Color(0x8CF1F0E4))),
                ],
              ),
            ),
            Text(product.barcode,
                style: CcText.mono.copyWith(color: const Color(0x80F1F0E4))),
          ],
        ),
      ),
    );
  }
}

/// Live camera preview that reports the first stable barcode it decodes.
/// Debounced so a held barcode fires [onDetect] once, not every frame.
class _BarcodeCamera extends StatefulWidget {
  const _BarcodeCamera({this.onDetect});
  final void Function(String barcode)? onDetect;

  @override
  State<_BarcodeCamera> createState() => _BarcodeCameraState();
}

class _BarcodeCameraState extends State<_BarcodeCamera> {
  final _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.itf,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  String? _last;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.trim().isNotEmpty, orElse: () => null);
    if (raw == null) return;
    final code = raw.trim();
    final now = DateTime.now();
    if (code == _last && now.difference(_lastAt) < const Duration(seconds: 3)) {
      return;
    }
    _last = code;
    _lastAt = now;
    widget.onDetect?.call(code);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 246,
      height: 170,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // reuse the corner frame overlay
          IgnorePointer(child: _Viewfinder()),
        ],
      ),
    );
  }
}

/// Manual barcode entry — lets the flow be exercised without a camera
/// (debug gallery, desktop, tests).
class _ManualBarcodeField extends StatefulWidget {
  const _ManualBarcodeField({this.onSubmit});
  final void Function(String barcode)? onSubmit;

  @override
  State<_ManualBarcodeField> createState() => _ManualBarcodeFieldState();
}

class _ManualBarcodeFieldState extends State<_ManualBarcodeField> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _c.text.trim();
    if (code.isEmpty) return;
    widget.onSubmit?.call(code);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0x14F1F0E4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x24F1F0E4)),
            ),
            child: TextField(
              controller: _c,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(
                  fontFamily: 'DMMono', fontSize: 14, color: Cc.paper),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                hintText: '8901234567890',
                hintStyle: TextStyle(
                    fontFamily: 'DMMono', fontSize: 14, color: Color(0x66F1F0E4)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _submit,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
                color: Cc.accent, borderRadius: BorderRadius.circular(14)),
            child: const Text('Look up',
                style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Cc.inkSoft)),
          ),
        ),
      ],
    );
  }
}
