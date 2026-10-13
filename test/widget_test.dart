import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/main.dart';

class MemorySave implements SaveRepository {
  Map<String, dynamic>? data;
  bool fail = false;
  @override
  Future<SaveLoadResult> load() async =>
      SaveLoadResult(data: data, recovered: false, generation: 1);
  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    if (fail) throw StateError('disk unavailable');
    data = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  }
}

void main() {
  testWidgets(
    'landscape planning controls and finite repetition are operable',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemorySave();
      final controller = GameController(
        store,
        devTools: true,
        now: () => DateTime.utc(2026, 10, 13),
      );
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MarsApp(
          controller: controller,
          sceneBuilder: (_, _, _, _) => const ColoredBox(color: Colors.black),
        ),
      );
      await tester.tap(find.byKey(const Key('queue-life_support')));
      await tester.pumpAndSettle();
      expect(controller.state.plans.single.taskId, 'life_support');
      await tester.tap(find.byKey(const Key('advance-time')));
      await tester.pumpAndSettle();
      expect(controller.state.research, contains('life_support'));
      await tester.tap(find.text('計画をつくる'));
      await tester.pumpAndSettle();
      final factory = find.byKey(const Key('queue-factory_contract'));
      await tester.scrollUntilVisible(
        factory,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(factory);
      await tester.pumpAndSettle();
      await tester.tap(factory);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repeat-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('advance-time')));
      await tester.pumpAndSettle();
      expect(controller.state.plans.last.completedRuns, 3);
      expect(controller.state.plans.last.status, 'completed');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'small landscape has no overflow and normal mode hides development controls',
    (tester) async {
      tester.view.physicalSize = const Size(740, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = GameController(MemorySave());
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MarsApp(
          controller: controller,
          sceneBuilder: (_, _, _, _) => const SizedBox.expand(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('advance-time')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test('controller resumes at same clock without duplicating effects and exposes save errors', () async {
    final store = MemorySave();
    final time = DateTime.utc(2026, 10, 13);
    final first = GameController(store, now: () => time);
    await first.initialize(startTimer: false);
    await first.command((game) {
      game.enqueue('factory_contract');
      game.advanceBy(const Duration(minutes: 2));
      return null;
    });
    final saved = jsonEncode(first.state.toJson());
    first.dispose();
    final resumed = GameController(store, now: () => time);
    await resumed.initialize(startTimer: false);
    expect(jsonEncode(resumed.state.toJson()), saved);
    store.fail = true;
    await resumed.save();
    expect(resumed.error, contains('自動保存に失敗'));
    resumed.dispose();
  });

  test('unsupported game payload remains untouched', () async {
    final store = MemorySave()..data = {'schemaVersion': 99};
    final controller = GameController(store);
    await controller.initialize(startTimer: false);
    expect(controller.engine, isNull);
    expect(controller.error, isNotNull);
    expect(store.data, {'schemaVersion': 99});
    controller.dispose();
  });
}
