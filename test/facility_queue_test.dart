import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/presentation/game_screen.dart';
import 'package:mars_terraforming/presentation/facility_queue_card.dart';

class QueueMemorySave implements SaveRepository {
  Map<String, dynamic>? data;
  @override
  Future<SaveLoadResult> load() async =>
      SaveLoadResult(data: data, recovered: false, generation: 1);
  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    data = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  }
}

void main() {
  final epoch = DateTime.utc(2026, 10, 13);
  GameEngine fresh() => GameEngine(GameState.initial(epoch)..money = 5000);
  GameState copy(GameState state) => GameState.fromJson(
    jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
  );

  test('moving an affordable contract ahead of a blocked plan starts it', () {
    final engine = fresh();
    engine.enqueue('habitat_kit');
    engine.enqueue('factory_contract');
    final kit = engine.state.plans[0];
    final contract = engine.state.plans[1];
    expect(kit.stopReason, contains('前提研究待ち'));
    expect(
      engine.reorderPlan(contract.id, relativeToPlanId: kit.id, before: true),
      isNull,
    );
    expect(engine.state.currentPlanFor('factory'), contract);
    expect(engine.state.upcomingPlansFor('factory'), [kit]);
    expect(kit.stopReason, '共用設備の順番待ち');
    expect(engine.state.money, 4960);
  });

  for (final repeats in <int?>[3, null]) {
    test(
      'future order preserves the current paid run for $repeats repeats',
      () {
        final engine = fresh();
        engine.state.research.add('life_support');
        engine.enqueue('factory_contract', repeats: repeats);
        engine.enqueue('habitat_kit');
        engine.advanceBy(const Duration(seconds: 30));
        final contract = engine.state.plans[0];
        final kit = engine.state.plans[1];
        final money = engine.state.moneyUnits;
        expect(
          engine.reorderPlan(
            kit.id,
            relativeToPlanId: contract.id,
            before: true,
          ),
          isNull,
        );
        expect(engine.state.currentPlanFor('factory'), contract);
        expect(contract.remainingMs, 60000);
        expect(engine.state.moneyUnits, money);
        expect(engine.state.upcomingPlansFor('factory'), [kit, contract]);
        engine.advanceBy(const Duration(seconds: 60));
        expect(contract.completedRuns, 1);
        expect(contract.status, 'queued');
        expect(engine.state.currentPlanFor('factory'), kit);
        engine.advanceBy(const Duration(seconds: 180));
        expect(engine.state.earthKits, 1);
        expect(engine.state.currentPlanFor('factory'), contract);
        engine.advanceBy(const Duration(seconds: 180));
        expect(contract.completedRuns, 3);
        expect(engine.state.contractRevenue, 660);
        expect(contract.status, repeats == null ? 'running' : 'completed');
      },
    );
  }

  test(
    'moving running repetitions does not consume the current cargo again',
    () {
      final engine = fresh();
      engine.state.earthKits = 3;
      engine.state.achievements.addAll(['first_launch', 'mars_route_open']);
      engine.enqueue('mars_delivery', repeats: 3);
      engine.enqueue('launch_contract');
      engine.advanceBy(const Duration(seconds: 30));
      final delivery = engine.state.plans[0];
      final contract = engine.state.plans[1];
      final money = engine.state.moneyUnits;
      engine.reorderPlan(
        delivery.id,
        relativeToPlanId: contract.id,
        before: false,
      );
      expect(engine.state.currentPlanFor('launch'), delivery);
      expect(engine.state.earthKits, 2);
      expect(engine.state.moneyUnits, money);
      expect(delivery.remainingMs, 150000);
      engine.advanceBy(const Duration(seconds: 150));
      expect(engine.state.marsKits, 1);
      expect(engine.state.earthKits, 2);
      expect(engine.state.currentPlanFor('launch'), contract);
      engine.advanceBy(const Duration(seconds: 120));
      expect(engine.state.currentPlanFor('launch'), delivery);
      expect(engine.state.earthKits, 1);
    },
  );

  testWidgets(
    'RP research reservation shows its point bank without a cash bill or timer',
    (tester) async {
      final controller = GameController(QueueMemorySave(), now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      controller.state.researchPointUnits = 0;
      await controller.command((engine) => engine.enqueue('life_support'));
      final plan = controller.state.plans.single;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FacilityQueueCard(
                controller: controller,
                facilityId: 'lab',
              ),
            ),
          ),
        ),
      );
      final estimate = tester.widget<Text>(
        find.byKey(Key('queue-estimate-${plan.id}')),
      );
      expect(
        estimate.data,
        '必要 ${GameContent.researchPointCost('life_support')} RP · 保有 0.0 RP',
      );
      expect(estimate.data, isNot(contains('ドル')));
      expect(estimate.data, isNot(contains('目安')));
      expect(
        find.byKey(const Key('lab-common-research-points')),
        findsOneWidget,
      );
      expect(find.textContaining('研究ポイント待ち'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'already-paid legacy research keeps its progress without an RP charge',
    (tester) async {
      final controller = GameController(QueueMemorySave(), now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      final plan = PlannedTask(id: 'paid-research', taskId: 'life_support')
        ..status = 'running'
        ..iterationDurationMs = 120000
        ..remainingMs = 60000
        ..iterationSpecialists = GameContent.baselineDepartmentStaff;
      controller.state.plans.add(plan);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FacilityQueueCard(
                controller: controller,
                facilityId: 'lab',
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(Key('current-${plan.id}')), findsOneWidget);
      expect(find.textContaining('支払済み・追加RP不要'), findsOneWidget);
      expect(find.byKey(Key('queue-estimate-${plan.id}')), findsNothing);
      expect(controller.state.research, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'paused paid work stays paused when its future queue position changes',
    () {
      final engine = fresh();
      engine.state.research.add('life_support');
      engine.enqueue('factory_contract', repeats: null);
      engine.enqueue('habitat_kit');
      engine.advanceBy(const Duration(seconds: 30));
      final current = engine.state.plans.first;
      final kit = engine.state.plans.last;
      engine.setFacilityEnabled('factory', false);
      engine.reorderPlan(kit.id, relativeToPlanId: current.id, before: true);
      engine.advanceBy(const Duration(minutes: 1));
      expect(engine.state.currentPlanFor('factory'), current);
      expect(current.remainingMs, 60000);
      expect(kit.stopReason, contains('設備休止中'));
      engine.setFacilityEnabled('factory', true);
      engine.advanceBy(const Duration(minutes: 1));
      expect(engine.state.currentPlanFor('factory'), kit);
    },
  );

  test(
    'order and non-first active job survive save/reload without extra charge',
    () {
      final engine = fresh();
      engine.state.research.add('life_support');
      engine.enqueue('factory_contract', repeats: null);
      engine.enqueue('habitat_kit');
      final current = engine.state.plans.first;
      engine.advanceTo(epoch.add(const Duration(seconds: 30)));
      engine.reorderPlan(
        engine.state.plans.last.id,
        relativeToPlanId: current.id,
        before: true,
      );
      final restored = GameEngine(copy(engine.state));
      restored.advanceTo(epoch.add(const Duration(seconds: 30)));
      expect(restored.state.toJson(), engine.state.toJson());
      expect(restored.state.currentPlanFor('factory')!.id, current.id);
      engine.advanceTo(epoch.add(const Duration(minutes: 8)));
      restored.advanceTo(epoch.add(const Duration(minutes: 8)));
      expect(restored.state.toJson(), engine.state.toJson());
    },
  );

  for (final repeats in <int?>[3, null]) {
    test('reordered $repeats repetitions agree across time partitions', () {
      final one = fresh();
      one.state.research.add('life_support');
      one.enqueue('factory_contract', repeats: repeats);
      one.enqueue('habitat_kit', repeats: 2);
      one.state.achievements.addAll(['first_launch', 'mars_route_open']);
      one.enqueue('mars_delivery', repeats: 2);
      one.enqueue('launch_contract', repeats: repeats);
      one.advanceBy(const Duration(seconds: 17));
      one.reorderPlan(
        one.state.plans[1].id,
        relativeToPlanId: one.state.plans[0].id,
        before: true,
      );
      final split = GameEngine(copy(one.state));
      one.advanceBy(const Duration(minutes: 20));
      for (var i = 0; i < 120; i++) {
        split.advanceBy(const Duration(seconds: 10));
      }
      expect(split.state.toJson(), one.state.toJson());
      expect(one.state.marsKits, 2);
    });
  }

  test(
    'invalid, completed, cross-facility and paid-single moves are rejected',
    () {
      final engine = fresh();
      engine.enqueue('factory_contract');
      engine.enqueue('habitat_kit');
      engine.enqueue('launch_contract', repeats: 3);
      final current = engine.state.plans[0];
      final kit = engine.state.plans[1];
      final launch = engine.state.plans[2];
      var snapshot = engine.state.toJson();
      for (final pair in [
        ('missing', kit.id),
        (kit.id, 'missing'),
        (kit.id, launch.id),
        (kit.id, kit.id),
        (current.id, kit.id),
        (kit.id, current.id),
      ]) {
        expect(
          engine.reorderPlan(pair.$1, relativeToPlanId: pair.$2, before: true),
          isNotNull,
        );
        expect(engine.state.toJson(), snapshot);
      }
      engine.advanceBy(const Duration(seconds: 90));
      snapshot = engine.state.toJson();
      expect(
        engine.reorderPlan(current.id, relativeToPlanId: kit.id, before: true),
        isNotNull,
      );
      expect(engine.state.toJson(), snapshot);
    },
  );

  for (final size in [const Size(1280, 720), const Size(780, 360)]) {
    testWidgets('facility controls reorder and persist at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = QueueMemorySave();
      final controller = GameController(store, now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      controller.state.money = 5000;
      controller.state.research.add('life_support');
      await controller.command(
        (engine) => engine.enqueue('factory_contract', repeats: null),
      );
      await controller.command((engine) => engine.enqueue('habitat_kit'));
      controller.state.achievements.addAll(['first_launch', 'mars_route_open']);
      await controller.command((engine) => engine.enqueue('mars_delivery'));
      await controller.command((engine) => engine.enqueue('build_habitat'));
      final current = controller.state.plans[0];
      final kit = controller.state.plans[1];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: GameScreen(
            showIntroduction: false,
            controller: controller,
            sceneBuilder: (_, _, _, _) => const SizedBox.expand(),
          ),
        ),
      );
      await tester.tap(find.text('設備・進行'));
      await tester.pumpAndSettle();
      final up = find.byKey(Key('queue-up-${kit.id}'));
      await tester.scrollUntilVisible(
        up,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(up);
      await tester.pumpAndSettle();
      await tester.tap(up);
      await tester.pumpAndSettle();
      expect(controller.state.currentPlanFor('factory'), current);
      expect(controller.state.upcomingPlansFor('factory'), [kit, current]);
      expect((store.data!['plans'] as List).first['id'], kit.id);
      expect(tester.widget<IconButton>(up).onPressed, isNull);
      final down = find.byKey(Key('queue-down-${kit.id}'));
      await tester.ensureVisible(down);
      await tester.pumpAndSettle();
      await tester.tap(down);
      await tester.pumpAndSettle();
      expect(controller.state.upcomingPlansFor('factory'), [current, kit]);
      for (final id in ['launch', 'mars']) {
        final card = find.byKey(Key('facility-$id'));
        await tester.scrollUntilVisible(
          card,
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        expect(card, findsOneWidget);
      }
      expect(find.textContaining('火星輸送後に居住方式を選択'), findsWidgets);
      expect(find.textContaining('資源不足'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
