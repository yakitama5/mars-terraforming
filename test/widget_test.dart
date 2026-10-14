import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_state.dart';
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
      final researchSteps =
          (GameContent.tasks['life_support']!.durationSeconds / 300).ceil();
      for (var i = 0; i < researchSteps; i++) {
        await tester.tap(find.byKey(const Key('advance-time')));
        await tester.pumpAndSettle();
      }
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
      expect(
        find.byKey(const Key('select-city-earth_delta')).hitTestable(),
        findsOneWidget,
      );
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
      await tester.scrollUntilVisible(
        find.text('立地・隣接ボーナス'),
        140,
        scrollable: find.descendant(
          of: find.byKey(const Key('district-detail')),
          matching: find.byType(Scrollable),
        ),
      );
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

  for (final size in [const Size(844, 390), const Size(1280, 800)]) {
    testWidgets('investment comparison remains live across cities at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = GameController(
        MemorySave(),
        now: () => DateTime.utc(2026, 10, 13),
      );
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      controller.state.research.addAll([
        'urban_planning',
        'automated_fabrication',
      ]);
      const house = DistrictState(
        cityId: 'earth_delta',
        plotIndex: 0,
        districtId: 'housing',
      );
      controller.state.districts[house.key] = house;
      await tester.pumpWidget(
        MarsApp(
          controller: controller,
          sceneBuilder: (_, _, _, _) => const SizedBox.expand(),
        ),
      );
      final before = jsonEncode(controller.state.toJson());
      await tester.tap(find.byKey(const Key('navigation-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plot-earth_delta-0')));
      await tester.pumpAndSettle();
      Future<void> detailTap(String key) async {
        final finder = find.byKey(Key(key));
        await tester.scrollUntilVisible(
          finder,
          140,
          scrollable: find.descendant(
            of: find.byKey(const Key('district-detail')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        expect(finder.hitTestable(), findsOneWidget);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await detailTap('save-investment');
      // A tab change disposes the district screen but must keep the comparison.
      await tester.tap(find.byKey(const Key('navigation-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('navigation-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('city-selector')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(GameContent.cities['earth_highland']!.name).last,
      );
      await tester.pumpAndSettle();
      await detailTap('compare-investments');
      expect(
        find.byKey(const Key('investment-comparison-saved')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('investment-comparison-current')),
        findsOneWidget,
      );
      expect(find.text('住宅地区 Lv.1 → 2'), findsOneWidget);
      expect(find.text('住宅地区 新設 Lv.1'), findsOneWidget);
      expect(find.text('0区画 · 空地を温存'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('investment-comparison-current')),
          matching: find.text('1区画'),
        ),
        findsOneWidget,
      );
      expect(jsonEncode(controller.state.toJson()), before);
      expect(tester.takeException(), isNull);
      // The saved placement now has a reservation. The open dialog must show it
      // without requiring another save or charging/reserving a second time.
      await controller.command(
        (engine) => engine.upgradeDistrict('earth_delta', 0),
      );
      await tester.pumpAndSettle();
      expect(controller.state.plans, hasLength(1));
      expect(find.text('この区画は建設・増強を予約済みです'), findsOneWidget);
      await tester.tap(find.byKey(const Key('close-investment-comparison')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('confirm-district')).hitTestable(),
        findsOneWidget,
      );
      expect(controller.state.plans, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a maximum-level district cannot save a nonexistent upgrade', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = GameController(MemorySave());
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    const house = DistrictState(
      cityId: 'earth_delta',
      plotIndex: 0,
      districtId: 'housing',
      level: 3,
    );
    controller.state.districts[house.key] = house;
    await tester.pumpWidget(
      MarsApp(
        controller: controller,
        sceneBuilder: (_, _, _, _) => const SizedBox.expand(),
      ),
    );
    await tester.tap(find.byKey(const Key('navigation-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plot-earth_delta-0')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-investment')),
      120,
      scrollable: find.descendant(
        of: find.byKey(const Key('district-detail')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('save-investment')))
          .onPressed,
      isNull,
    );
    expect(find.text('建設前の見積もり'), findsNothing);
    expect(find.textContaining('Lv.3 → 4'), findsNothing);
    expect(controller.state.plans, isEmpty);
    expect(tester.takeException(), isNull);
  });

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
