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
      await tester.tap(find.byKey(const Key('navigation-2')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('queue-life_support')),
        150,
        scrollable: find.descendant(
          of: find.byKey(const Key('research-detail')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byKey(const Key('queue-life_support')));
      await tester.pumpAndSettle();
      expect(controller.state.plans.single.taskId, 'life_support');
      await tester.tap(find.byKey(const Key('advance-time')));
      await tester.pumpAndSettle();
      expect(controller.state.research, contains('life_support'));
      await tester.tap(find.byKey(const Key('operations-1')));
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

  for (final size in [const Size(844, 390), const Size(1280, 800)]) {
    testWidgets('all strategy views fit ${size.width} by ${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
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
      for (var tab = 1; tab <= 3; tab++) {
        await tester.tap(find.byKey(Key('navigation-$tab')));
        await tester.pumpAndSettle();
        if (tab == 1) {
          expect(
            find.byKey(const Key('confirm-district')).hitTestable(),
            findsOneWidget,
          );
        }
        if (tab == 2) {
          expect(
            find.byKey(const Key('queue-life_support')).hitTestable(),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const Key('research-fit')));
          await tester.pumpAndSettle();
          expect(
            find
                .byKey(const Key('research-node-intercity_logistics'))
                .hitTestable(),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      }
      for (var tab = 1; tab <= 3; tab++) {
        await tester.tap(find.byKey(Key('operations-$tab')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets(
    'city selection and plot preview do not construct until confirmed',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
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
      await tester.ensureVisible(find.byKey(const Key('open-city')));
      await tester.tap(find.byKey(const Key('open-city')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plot-earth_delta-0')));
      await tester.pumpAndSettle();
      expect(find.text('区画 1  ·  海岸'), findsOneWidget);
      expect(find.text('建設前の見積もり'), findsOneWidget);
      expect(find.text('立地・隣接ボーナス'), findsOneWidget);
      expect(controller.state.plans, isEmpty);
      await tester.ensureVisible(find.byKey(const Key('confirm-district')));
      await tester.tap(find.byKey(const Key('confirm-district')));
      await tester.pumpAndSettle();
      expect(controller.state.plans.single.cityId, 'earth_delta');
      expect(controller.state.plans.single.plotIndex, 0);
      expect(controller.state.districtAt('earth_delta', 0), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'research tree exposes practical requirements after prerequisite research',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = GameController(MemorySave());
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await controller.command((engine) {
        engine.state.research.add('urban_planning');
        return null;
      });
      await tester.pumpWidget(
        MarsApp(
          controller: controller,
          sceneBuilder: (_, _, _, _) => const SizedBox.expand(),
        ),
      );
      await tester.tap(find.byKey(const Key('navigation-2')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('research-node-automated_fabrication')),
      );
      await tester.pumpAndSettle();
      expect(find.text('必要な研究・実証条件'), findsOneWidget);
      expect(find.text('完成するとできること'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('queue-automated_fabrication')),
      );
      await tester.tap(find.byKey(const Key('queue-automated_fabrication')));
      await tester.pumpAndSettle();
      expect(controller.state.plans.single.taskId, 'automated_fabrication');
      expect(controller.state.plans.single.status, 'queued');
      expect(controller.state.research, contains('urban_planning'));
      expect(
        controller.state.research,
        isNot(contains('automated_fabrication')),
      );
      expect(controller.state.plans.single.stopReason, contains('実証待ち'));
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
