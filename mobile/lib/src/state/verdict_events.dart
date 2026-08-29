import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/product_api.dart';

/// One successful `POST /scan/verdict` — the integration seam Phase 5's diet
/// logging hooks into.
///
/// [MainApp.scanBarcode] pushes a [VerdictEvent] here every time a scan lands on
/// a verdict (and only then — not on "not found" or an error, and not for the
/// Phase 2 demo picker). Phase 5's logger will:
///
/// ```dart
/// ref.listen(verdictEventProvider, (prev, next) {
///   if (next != null) dietLog.record(next);  // POST /diet-log, etc.
/// });
/// ```
@immutable
class VerdictEvent {
  const VerdictEvent({
    required this.barcode,
    required this.verdict,
    required this.at,
    this.productName,
    this.product,
  });

  final String barcode;
  final String? productName;
  final ScannedProduct? product;
  final ScanVerdict verdict;
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is VerdictEvent &&
      other.barcode == barcode &&
      other.at == at &&
      identical(other.verdict, verdict);

  @override
  int get hashCode => Object.hash(barcode, at, identityHashCode(verdict));
}

/// Holds the most recent [VerdictEvent] (null until the first successful scan).
/// A `Notifier` rather than a stream so a listener that attaches late still sees
/// the last event, and `ref.listen` fires on every new one.
class VerdictEvents extends Notifier<VerdictEvent?> {
  @override
  VerdictEvent? build() => null;

  void emit(VerdictEvent event) => state = event;
}

final verdictEventProvider =
    NotifierProvider<VerdictEvents, VerdictEvent?>(VerdictEvents.new);
