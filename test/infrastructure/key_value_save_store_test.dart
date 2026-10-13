import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/infrastructure/key_value_save_store.dart';

void main() {
  late _Storage storage;
  late KeyValueSaveStore store;
  KeyValueSaveStore reopen({String slot = 'normal'}) =>
      KeyValueSaveStore(read: storage.read, write: storage.write, slot: slot);
  Map<String, dynamic> world(int timestamp, int funds) => {
    'lastProcessedAtMs': timestamp,
    'funds': funds,
    'research': ['life_support'],
    'awardedIds': ['world-1:job-1'],
    'queue': [
      {'id': 'world-1:job-2', 'remainingMs': 2000},
    ],
  };
  Map<String, dynamic> bundle() =>
      jsonDecode(storage.values[store.storageKey]!) as Map<String, dynamic>;
  void changeEnvelope(String name, void Function(Map<String, dynamic>) edit) {
    final saved = bundle();
    final envelope = jsonDecode(saved[name] as String) as Map<String, dynamic>;
    edit(envelope);
    saved[name] = jsonEncode(envelope);
    storage.values[store.storageKey] = jsonEncode(saved);
  }

  setUp(() {
    storage = _Storage();
    store = reopen();
  });

  test('an absent browser slot starts empty', () async {
    final loaded = await store.load();
    expect(loaded.data, isNull);
    expect(loaded.generation, 0);
    expect(loaded.recovered, isFalse);
    expect(storage.writeCount, 0);
  });

  test(
    'state, clock and awards round-trip in one checksummed payload',
    () async {
      await store.save(world(1000, 400));
      final loaded = await reopen().load();
      expect(loaded.data, world(1000, 400));
      expect(loaded.generation, 1);
      expect(loaded.recovered, isFalse);
      expect(storage.writeCount, 1);
      expect(storage.values, hasLength(1));
      final envelope = jsonDecode(bundle()['primary'] as String) as Map;
      final payload = envelope['payload'] as String;
      expect(
        envelope['checksum'],
        sha256.convert(utf8.encode('1:1:$payload')).toString(),
      );
    },
  );

  test('each atomic bundle retains only the latest two generations', () async {
    for (var generation = 1; generation <= 8; generation++) {
      await store.save(world(generation * 1000, generation * 10));
    }
    final saved = bundle();
    expect((await reopen().load()).generation, 8);
    expect((jsonDecode(saved['previous'] as String) as Map)['generation'], 7);
    expect(
      saved.keys,
      unorderedEquals(['formatVersion', 'primary', 'previous']),
    );
    expect(storage.values, hasLength(1));
    expect(storage.writeCount, 8);
  });

  test('snapshot data is captured before caller mutations', () async {
    final snapshot = world(1000, 10);
    final saving = store.save(snapshot);
    snapshot['funds'] = 999;
    (snapshot['awardedIds'] as List).add('must-not-leak');
    await saving;
    expect((await reopen().load()).data, world(1000, 10));
  });

  test('a corrupt primary recovers the previous complete generation', () async {
    await store.save(world(1000, 10));
    await store.save(world(2000, 20));
    final saved = bundle()..['primary'] = '{"schemaVersion":';
    storage.values[store.storageKey] = jsonEncode(saved);
    final loaded = await reopen().load();
    expect(loaded.data, world(1000, 10));
    expect(loaded.generation, 1);
    expect(loaded.recovered, isTrue);
  });

  test('checksum detects altered payload and altered generation', () async {
    await store.save(world(1000, 10));
    await store.save(world(2000, 20));
    changeEnvelope('primary', (envelope) {
      envelope['payload'] = jsonEncode(world(2000, 999999));
      envelope['generation'] = 999;
    });
    expect((await reopen().load()).data, world(1000, 10));
  });

  test(
    'invalid schema types are corruption, not a runtime cast failure',
    () async {
      await store.save(world(1000, 10));
      await store.save(world(2000, 20));
      changeEnvelope('primary', (envelope) => envelope['schemaVersion'] = '1');
      expect((await reopen().load()).data, world(1000, 10));
    },
  );

  test(
    'saving after recovery keeps the last valid snapshot as previous',
    () async {
      await store.save(world(1000, 10));
      await store.save(world(2000, 20));
      final saved = bundle();
      final validPrevious = saved['previous'];
      saved['primary'] = 'broken';
      storage.values[store.storageKey] = jsonEncode(saved);
      final recovered = reopen();
      await recovered.load();
      await recovered.save(world(3000, 30));
      expect(bundle()['previous'], validPrevious);
      expect((await reopen().load()).data, world(3000, 30));
    },
  );

  test(
    'the highest valid generation wins if bundle fields were swapped',
    () async {
      await store.save(world(1000, 10));
      await store.save(world(2000, 20));
      final saved = bundle();
      final primary = saved['primary'];
      saved['primary'] = saved['previous'];
      saved['previous'] = primary;
      storage.values[store.storageKey] = jsonEncode(saved);
      final loaded = await reopen().load();
      expect(loaded.generation, 2);
      expect(loaded.data, world(2000, 20));
      expect(loaded.recovered, isTrue);
    },
  );

  for (final position in ['primary', 'previous']) {
    test('an unsupported $position blocks reads and writes', () async {
      await store.save(world(1000, 10));
      await store.save(world(2000, 20));
      changeEnvelope(position, (envelope) => envelope['schemaVersion'] = 99);
      final protectedRaw = storage.values[store.storageKey];
      final oldApplication = reopen();
      await expectLater(
        oldApplication.load(),
        throwsA(isA<UnsupportedBrowserSaveVersionException>()),
      );
      await expectLater(
        oldApplication.save(world(3000, 30)),
        throwsA(isA<UnsupportedBrowserSaveVersionException>()),
      );
      expect(storage.values[store.storageKey], protectedRaw);
    });
  }

  test('an unknown browser bundle version cannot be overwritten', () async {
    await store.save(world(1000, 10));
    final saved = bundle()..['formatVersion'] = 99;
    final protectedRaw = jsonEncode(saved);
    storage.values[store.storageKey] = protectedRaw;
    await expectLater(
      reopen().load(),
      throwsA(isA<UnsupportedBrowserSaveVersionException>()),
    );
    await expectLater(
      reopen().save(world(2000, 20)),
      throwsA(isA<UnsupportedBrowserSaveVersionException>()),
    );
    expect(storage.values[store.storageKey], protectedRaw);
  });

  for (final corrupt in [
    'broken outer bundle',
    '{"formatVersion":1,"primary":"broken","previous":"broken"}',
    '{"formatVersion":1,"primary":"broken","previous":null}',
    '{"formatVersion":1,"primary":null,"previous":null}',
  ]) {
    test('corrupt data never becomes a new world: $corrupt', () async {
      storage.values[store.storageKey] = corrupt;
      await expectLater(
        store.load(),
        throwsA(isA<CorruptBrowserSaveException>()),
      );
      await expectLater(
        store.save(world(1000, 10)),
        throwsA(isA<CorruptBrowserSaveException>()),
      );
      expect(storage.values[store.storageKey], corrupt);
      expect(storage.writeCount, 0);
    });
  }

  test(
    'failed atomic commit preserves both generations and permits retry',
    () async {
      await store.save(world(1000, 10));
      await store.save(world(2000, 20));
      final before = storage.values[store.storageKey];
      storage.failWrite = true;
      await expectLater(
        store.save(world(3000, 30)),
        throwsA(isA<BrowserSaveStoreException>()),
      );
      expect(storage.values[store.storageKey], before);
      expect((await reopen().load()).data, world(2000, 20));
      storage.failWrite = false;
      await store.save(world(4000, 40));
      expect((await reopen().load()).generation, 3);
      expect((await reopen().load()).data, world(4000, 40));
    },
  );

  test('storage access denial is not an empty new world', () async {
    await store.save(world(1000, 10));
    final before = storage.values[store.storageKey];
    storage.failRead = true;
    await expectLater(store.load(), throwsA(isA<BrowserSaveStoreException>()));
    await expectLater(
      store.save(world(2000, 20)),
      throwsA(isA<BrowserSaveStoreException>()),
    );
    expect(storage.values[store.storageKey], before);
  });

  test(
    'normal and development slots have independent keys and generations',
    () async {
      final development = reopen(slot: 'development');
      await store.save(world(1000, 10));
      await development.save(world(999999, 50000));
      expect((await reopen().load()).data, world(1000, 10));
      expect(
        (await reopen(slot: 'development').load()).data,
        world(999999, 50000),
      );
      expect(storage.values, hasLength(2));
    },
  );

  test(
    'stale writers detect a competing update without overwriting it',
    () async {
      await store.save(world(1000, 10));
      final competing = reopen();
      await competing.load();
      await store.save(world(2000, 20));
      await expectLater(
        competing.save(world(3000, 999999)),
        throwsA(isA<BrowserSaveConflictException>()),
      );
      expect((await reopen().load()).data, world(2000, 20));
    },
  );

  test(
    'an empty slot loaded elsewhere cannot replace a new committed world',
    () async {
      final competing = reopen();
      await competing.load();
      await store.save(world(1000, 10));
      await expectLater(
        competing.save(world(2000, 999)),
        throwsA(isA<BrowserSaveConflictException>()),
      );
      expect((await reopen().load()).data, world(1000, 10));
    },
  );

  test(
    'external deletion is detected instead of silently recreating a save',
    () async {
      await store.save(world(1000, 10));
      storage.values.clear();
      await expectLater(
        store.save(world(2000, 20)),
        throwsA(isA<BrowserSaveConflictException>()),
      );
      expect(storage.values, isEmpty);
    },
  );

  test('non-JSON snapshots fail before changing a committed world', () async {
    await store.save(world(1000, 10));
    final before = storage.values[store.storageKey];
    await expectLater(store.save({'invalid': Object()}), throwsA(anything));
    expect(storage.values[store.storageKey], before);
  });

  test(
    'resume preserves game state, completed research and contract awards',
    () async {
      final epoch = DateTime.utc(2026, 10, 13);
      final engine = GameEngine(GameState.initial(epoch));
      engine.enqueue('factory_contract', repeats: 3);
      engine.enqueue('life_support');
      final resumedAt = epoch.add(const Duration(seconds: 270));
      engine.advanceTo(resumedAt);
      await store.save(engine.state.toJson());
      final restored = GameEngine(
        GameState.fromJson((await reopen().load()).data!),
      );
      restored.advanceTo(resumedAt);
      expect(restored.state.toJson(), engine.state.toJson());
      expect(restored.state.contractRevenue, 660);
      expect(restored.state.research, contains('life_support'));
    },
  );
}

class _Storage {
  final values = <String, String>{};
  int writeCount = 0;
  bool failRead = false;
  bool failWrite = false;

  String? read(String key) {
    if (failRead) throw StateError('Access denied');
    return values[key];
  }

  void write(String key, String value) {
    if (failWrite) throw StateError('Quota exceeded before atomic commit');
    values[key] = value;
    writeCount++;
  }
}
