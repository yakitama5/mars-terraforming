import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/infrastructure/file_save_store.dart';

void main() {
  late Directory directory;
  late FileSaveStore store;

  File primary() => File('${directory.path}/normal.json');
  File previous() => File('${directory.path}/normal.previous.json');
  File pending() => File('${directory.path}/normal.pending.json');
  Map<String, dynamic> world(int timestamp, int funds) => {
    'contentVersion': 1,
    'lastProcessedAtMs': timestamp,
    'funds': funds,
    'completedResearch': ['water_recycling'],
    'awardedIds': ['run-1:contract-3'],
    'queue': [
      {'id': 'run-1:job-4', 'remainingMs': 2000},
    ],
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mars_save_test_');
    store = FileSaveStore(directory);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('an absent slot has no snapshot', () async {
    final loaded = await store.load();
    expect(loaded.data, isNull);
    expect(loaded.recovered, isFalse);
    expect(loaded.generation, 0);
  });

  test(
    'one generation stores state, ledger and time as an intact unit',
    () async {
      final state = world(12000, 400);
      await store.save(state);
      final loaded = await FileSaveStore(directory).load();
      expect(loaded.data, state);
      expect(loaded.recovered, isFalse);
      expect(loaded.generation, 1);
      expect((await store.load()).data, state);
      expect((await store.load()).generation, 1);
    },
  );

  test('only two committed generations remain after repeated saves', () async {
    for (var generation = 1; generation <= 8; generation++) {
      await store.save(world(generation * 1000, generation * 10));
    }
    expect((await store.load()).generation, 8);
    expect(
      (jsonDecode(await previous().readAsString()) as Map)['generation'],
      7,
    );
    expect(await directory.list().length, 2);
    expect(await pending().exists(), isFalse);
  });

  test('corrupt primary recovers the previous complete snapshot', () async {
    await store.save(world(1000, 10));
    await store.save(world(2000, 20));
    await primary().writeAsString('{"schemaVersion":');
    final loaded = await store.load();
    expect(loaded.data, world(1000, 10));
    expect(loaded.generation, 1);
    expect(loaded.recovered, isTrue);
  });

  test(
    'tampering with content or generation fails checksum validation',
    () async {
      await store.save(world(1000, 10));
      await store.save(world(2000, 20));
      final envelope = jsonDecode(await primary().readAsString()) as Map;
      envelope['payload'] = jsonEncode(world(2000, 999999));
      envelope['generation'] = 999;
      await primary().writeAsString(jsonEncode(envelope));
      expect((await store.load()).data, world(1000, 10));
    },
  );

  test('invalid UTF-8 is corruption and can recover a valid backup', () async {
    await store.save(world(1000, 10));
    await store.save(world(2000, 20));
    await primary().writeAsBytes([0xff, 0xfe, 0xff]);
    expect((await store.load()).data, world(1000, 10));
  });

  test(
    'a non-integer schema value is corrupt instead of a runtime type error',
    () async {
      await store.save(world(1000, 10));
      await store.save(world(2000, 20));
      final envelope = jsonDecode(await primary().readAsString()) as Map;
      envelope['schemaVersion'] = 1.0;
      await primary().writeAsString(jsonEncode(envelope));
      expect((await store.load()).data, world(1000, 10));
    },
  );

  test('saving after recovery preserves the last valid backup', () async {
    await store.save(world(1000, 10));
    await store.save(world(2000, 20));
    await primary().writeAsString('corrupt');
    final backupBefore = await previous().readAsString();
    await store.save(world(3000, 30));
    expect(await previous().readAsString(), backupBefore);
    expect((await store.load()).data, world(3000, 30));
    await primary().writeAsString('corrupt again');
    expect((await store.load()).data, world(1000, 10));
  });

  test('a torn uncommitted file cannot replace the current world', () async {
    await store.save(world(1000, 10));
    await pending().writeAsString('{"schemaVersion":1,"generation":2');
    final loaded = await store.load();
    expect(loaded.data, world(1000, 10));
    expect(loaded.recovered, isFalse);
    await store.save(world(2000, 20));
    expect((await store.load()).data, world(2000, 20));
  });

  test('even a complete pending file is not a committed operation', () async {
    await store.save(world(1000, 10));
    await store.save(world(2000, 20));
    // Process terminates before pending->primary: the older primary still wins.
    await primary().rename(pending().path);
    await previous().rename(primary().path);
    expect((await store.load()).data, world(1000, 10));
  });

  test(
    'interruption between the two renames recovers newest committed state',
    () async {
      await store.save(world(1000, 10));
      await store.save(world(2000, 20));
      final latest = await primary().readAsString();
      // Pending is flushed; primary->previous has happened; commit has not.
      await pending().writeAsString(latest);
      await primary().rename(previous().path);
      final loaded = await FileSaveStore(directory).load();
      expect(loaded.data, world(2000, 20));
      expect(loaded.recovered, isTrue);
      await store.save(world(3000, 30));
      expect((await store.load()).generation, 3);
      expect(await previous().readAsString(), latest);
    },
  );

  test(
    'a failed disk write leaves the committed state usable and retries work',
    () async {
      await store.save(world(1000, 10));
      await Directory(pending().path).create();
      await expectLater(
        store.save(world(2000, 20)),
        throwsA(isA<SaveStoreException>()),
      );
      expect((await store.load()).data, world(1000, 10));
      await Directory(pending().path).delete();
      await store.save(world(3000, 30));
      expect((await store.load()).data, world(3000, 30));
    },
  );

  test(
    'concurrent writes across instances are ordered and snapshots are captured',
    () async {
      final first = world(1000, 10);
      final write1 = store.save(first);
      first['funds'] = 999;
      final write2 = FileSaveStore(directory).save(world(2000, 20));
      final write3 = store.save(world(3000, 30));
      await Future.wait([write1, write2, write3]);
      expect((await store.load()).data, world(3000, 30));
      expect((await store.load()).generation, 3);
      final backup = jsonDecode(await previous().readAsString()) as Map;
      expect(jsonDecode(backup['payload'] as String), world(2000, 20));
    },
  );

  test('a snapshot is captured before asynchronous file access', () async {
    final state = world(1000, 10);
    final saving = store.save(state);
    state['funds'] = 999;
    (state['awardedIds'] as List).add('should-not-leak');
    await saving;
    expect((await store.load()).data, world(1000, 10));
  });

  test(
    'unknown primary format blocks load and save even with a valid backup',
    () async {
      await store.save(world(1000, 10));
      await store.save(world(2000, 20));
      final envelope = jsonDecode(await primary().readAsString()) as Map;
      envelope['schemaVersion'] = 99;
      final unknown = jsonEncode(envelope);
      await primary().writeAsString(unknown);
      await expectLater(
        store.load(),
        throwsA(isA<UnsupportedSaveVersionException>()),
      );
      await expectLater(
        store.save(world(3000, 30)),
        throwsA(isA<UnsupportedSaveVersionException>()),
      );
      expect(await primary().readAsString(), unknown);
    },
  );

  test('unknown backup format is also preserved', () async {
    await store.save(world(1000, 10));
    await previous().writeAsString('{"schemaVersion":99}');
    await expectLater(
      store.save(world(2000, 20)),
      throwsA(isA<UnsupportedSaveVersionException>()),
    );
    expect(await previous().readAsString(), '{"schemaVersion":99}');
  });

  test('corrupt committed files never become an empty new game', () async {
    await primary().writeAsString('broken primary');
    await previous().writeAsString('broken backup');
    await expectLater(store.load(), throwsA(isA<CorruptSaveException>()));
    await expectLater(
      store.save(world(1000, 10)),
      throwsA(isA<CorruptSaveException>()),
    );
    expect(await primary().readAsString(), 'broken primary');
    expect(await previous().readAsString(), 'broken backup');
  });

  test(
    'one corrupt committed file without a backup also blocks replacement',
    () async {
      await primary().writeAsString('broken primary');
      await expectLater(store.load(), throwsA(isA<CorruptSaveException>()));
      await expectLater(
        store.save(world(1000, 10)),
        throwsA(isA<CorruptSaveException>()),
      );
    },
  );

  test('normal and development slots cannot affect each other', () async {
    final development = FileSaveStore(directory, slot: 'development');
    await store.save(world(1000, 10));
    await development.save(world(999999, 50000));
    expect((await store.load()).data, world(1000, 10));
    expect((await development.load()).data, world(999999, 50000));
  });

  test('slot path traversal is rejected', () {
    expect(
      () => FileSaveStore(directory, slot: '../other'),
      throwsArgumentError,
    );
  });
}
