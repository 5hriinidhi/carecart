// Phase 6.3 — the on-device cache round-trips products + history and is bounded.

import 'package:carecart/src/core/history_api.dart';
import 'package:carecart/src/core/local_cache.dart';
import 'package:carecart/src/core/product_api.dart';
import 'package:flutter_test/flutter_test.dart';

ScannedProduct _p(String barcode, {String? name}) => ScannedProduct(
      barcode: barcode,
      name: name ?? 'Product $barcode',
      ingredients: const ['Water', 'Sugar'],
      nutriments: const {'sugars_g_100g': 5},
    );

ScanHistoryEntry _h(String id, String tier) => ScanHistoryEntry(
      id: id,
      productName: 'Item $id',
      score: tier == 'safe' ? 90 : 40,
      tier: tier,
      scannedAt: DateTime.utc(2026, 8, 20, 12, 0).add(Duration(minutes: int.parse(id))),
      keyReasons: const [
        HistoryReason(kind: 'poor_fit', severity: 'low', title: 'x', factor: 'sodium')
      ],
    );

void main() {
  test('a product round-trips through the cache', () async {
    final c = LocalCache(MemoryKV());
    await c.putProduct(_p('111', name: 'Oats'));

    final hit = await c.getProduct('111');
    expect(hit, isNotNull);
    expect(hit!.product.barcode, '111');
    expect(hit.product.displayName, 'Oats');
    expect(hit.product.ingredients, ['Water', 'Sugar']);
    expect(hit.cachedAt.isBefore(DateTime.now().add(const Duration(seconds: 2))),
        isTrue);
    expect(await c.getProduct('nope'), isNull);
  });

  test('product cache is LRU-capped at 30', () async {
    final c = LocalCache(MemoryKV());
    for (var i = 0; i < 35; i++) {
      await c.putProduct(_p('bc$i'));
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    // the 5 oldest were evicted
    expect(await c.getProduct('bc0'), isNull);
    expect(await c.getProduct('bc4'), isNull);
    expect(await c.getProduct('bc5'), isNotNull);
    expect(await c.getProduct('bc34'), isNotNull);
  });

  test('history snapshot round-trips and keeps order', () async {
    final c = LocalCache(MemoryKV());
    final items = [_h('3', 'avoid'), _h('2', 'caution'), _h('1', 'safe')];
    await c.putHistory(items);

    final snap = await c.getHistory();
    expect(snap, isNotNull);
    expect(snap!.items.map((e) => e.id).toList(), ['3', '2', '1']);
    expect(snap.items.first.tier, 'avoid');
    expect(snap.items.first.keyReasons.first.factor, 'sodium');
  });

  test('clear() wipes both caches', () async {
    final c = LocalCache(MemoryKV());
    await c.putProduct(_p('111'));
    await c.putHistory([_h('1', 'safe')]);
    await c.clear();
    expect(await c.getProduct('111'), isNull);
    expect(await c.getHistory(), isNull);
  });

  test('a corrupt blob is treated as empty, not a crash', () async {
    final kv = MemoryKV();
    await kv.write('cc_cache_products_v1', 'not json{');
    await kv.write('cc_cache_history_v1', '{"items": 42}');
    final c = LocalCache(kv);
    expect(await c.getProduct('x'), isNull);
    expect(await c.getHistory(), isNull);
  });
}
