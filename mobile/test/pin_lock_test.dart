// The on-device medications PIN — set / verify / clear, hashing only.

import 'package:carecart/src/core/pin_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MemoryPinStore store;
  late PinLock lock;

  setUp(() {
    store = MemoryPinStore();
    lock = PinLock(store);
  });

  test('isValidPin: 4–6 digits only', () {
    expect(isValidPin('1234'), isTrue);
    expect(isValidPin('123456'), isTrue);
    expect(isValidPin('123'), isFalse);
    expect(isValidPin('1234567'), isFalse);
    expect(isValidPin('12a4'), isFalse);
    expect(isValidPin(''), isFalse);
  });

  test('no PIN until one is set', () async {
    expect(await lock.isSet(), isFalse);
    expect(await lock.verify('1234'), isFalse);
  });

  test('set then verify; wrong PIN fails', () async {
    await lock.setPin('4271');
    expect(await lock.isSet(), isTrue);
    expect(await lock.verify('4271'), isTrue);
    expect(await lock.verify('0000'), isFalse);
  });

  test('the raw PIN is never stored; only a salted hash', () async {
    await lock.setPin('918273');
    final rec = await store.read();
    expect(rec, isNotNull);
    expect(rec!.hash, isNot(contains('918273')));
    expect(rec.hash.length, 64); // sha-256 hex
    expect(rec.salt.length, 32); // 16 random bytes, hex
  });

  test('re-setting rotates the salt', () async {
    await lock.setPin('1234');
    final first = await store.read();
    await lock.setPin('1234');
    final second = await store.read();
    expect(second!.salt, isNot(first!.salt));
    expect(second.hash, isNot(first.hash));
    expect(await lock.verify('1234'), isTrue);
  });

  test('setPin rejects a malformed PIN', () async {
    expect(() => lock.setPin('12'), throwsArgumentError);
    expect(await lock.isSet(), isFalse);
  });

  test('clear forgets it', () async {
    await lock.setPin('4271');
    await lock.clear();
    expect(await lock.isSet(), isFalse);
    expect(await lock.verify('4271'), isFalse);
  });
}
