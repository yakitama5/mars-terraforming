import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/presentation/facility_queue_card.dart';
import 'package:mars_terraforming/presentation/research_tree.dart';

class _MemorySave implements SaveRepository {
  @override
  Future<SaveLoadResult> load() async =>
      const SaveLoadResult(data: null, recovered: false, generation: 0);

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {}
}

void main() {
  final epoch = DateTime.utc(2026, 10, 15);

  testWidgets(
    'next action bypasses unlimited repetitions without interruption',
    (tester) async {
      tester.view.physicalSize = const Size(780, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = GameController(_MemorySave(), now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      final engine = controller.engine!;
      engine.state.money = 5000;
      engine.state.research.add('life_support');
      engine.enqueue('factory_contract', repeats: null);
      engine.enqueue('earth_expansion');
      engine.enqueue('habitat_kit');
      engine.advanceBy(const Duration(seconds: 30));
      final current = engine.state.plans.first;
      final kit = engine.state.plans.last;
      final money = engine.state.moneyUnits;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(
            body: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => SingleChildScrollView(
                child: FacilityQueueCard(
                  controller: controller,
                  facilityId: 'factory',
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(Key('unlimited-before-${kit.id}')), findsOneWidget);
      expect(find.textContaining('開始時 260ドル'), findsOneWidget);
      final next = find.byKey(Key('queue-next-${kit.id}'));
      await tester.ensureVisible(next);
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(engine.state.currentPlanFor('factory'), current);
      expect(current.remainingMs, 60000);
      expect(engine.state.moneyUnits, money);
      expect(engine.state.upcomingPlansFor('factory').first, kit);
      expect(find.byKey(Key('unlimited-before-${kit.id}')), findsNothing);
      expect(find.byKey(Key('queue-next-${kit.id}')), findsNothing);
      engine.advanceBy(const Duration(seconds: 60));
      expect(engine.state.currentPlanFor('factory'), kit);
      expect(tester.takeException(), isNull);
    },
  );

  for (final running in [false, true]) {
    testWidgets('cancel confirmation preserves paid work: running=$running', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(780, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = GameController(_MemorySave(), now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      final engine = controller.engine!;
      engine.state.money = 5000;
      engine.enqueue('factory_contract', repeats: 3);
      if (!running) engine.enqueue('habitat_kit');
      final plan = engine.state.plans.last;
      final money = engine.state.moneyUnits;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(
            body: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => SingleChildScrollView(
                child: FacilityQueueCard(
                  controller: controller,
                  facilityId: 'factory',
                ),
              ),
            ),
          ),
        ),
      );
      final cancel = find.byKey(Key('queue-cancel-${plan.id}'));
      await tester.ensureVisible(cancel);
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(plan.isFinished, isFalse);
      await tester.tap(find.byKey(Key('queue-keep-${plan.id}')));
      await tester.pumpAndSettle();
      expect(plan.remainingRepeats, running ? 3 : 1);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('queue-confirm-cancel-${plan.id}')));
      await tester.pumpAndSettle();
      expect(plan.status, running ? 'running' : 'cancelled');
      expect(plan.remainingRepeats, 1);
      expect(engine.state.moneyUnits, money);
      if (running) {
        expect(plan.remainingMs, 90000);
        engine.advanceBy(const Duration(seconds: 90));
        expect(plan.status, 'completed');
        expect(plan.completedRuns, 1);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('paused vehicle shows why a paid flight is waiting', (
    tester,
  ) async {
    final controller = GameController(_MemorySave(), now: () => epoch);
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    final engine = controller.engine!;
    engine.state.money = 50000;
    engine.state.research.add('cargo_packaging');
    engine.state.achievements.addAll(['first_launch', 'mars_route_open']);
    expect(
      engine.enqueueDevelopment('cargo_packaging', cityId: 'earth_delta'),
      isNull,
    );
    engine.advanceBy(
      Duration(milliseconds: engine.state.plans.last.remainingMs),
    );
    expect(engine.setDevelopmentEnabled('cargo_packaging', true), isNull);
    engine.state.earthKits = 1;
    expect(
      engine.enqueue(GameContent.developmentOperationTaskId('cargo_packaging')),
      isNull,
    );
    engine.advanceBy(const Duration(seconds: 30));
    final flight = engine.state.currentPlanFor('launch')!;
    final remainingMs = flight.remainingMs;
    Future<void> draw() => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: SingleChildScrollView(
            child: FacilityQueueCard(
              controller: controller,
              facilityId: 'launch',
            ),
          ),
        ),
      ),
    );
    await draw();
    expect(find.textContaining('進行中 ·'), findsOneWidget);
    final paidTime = tester.widget<Text>(find.textContaining(' · 支払済み')).data!;
    expect(engine.setDevelopmentEnabled('cargo_packaging', false), isNull);
    engine.advanceBy(const Duration(seconds: 30));
    await draw();
    expect(engine.state.facilities['launch'], isTrue);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('facility-toggle-launch')))
          .value,
      isTrue,
    );
    expect(find.textContaining('条件待ち · 基本維持費'), findsOneWidget);
    expect(find.textContaining('条件待ち · '), findsNWidgets(2));
    expect(find.text('対応する設備・機体が休止中'), findsOneWidget);
    expect(find.text('再開後の$paidTime'), findsOneWidget);
    expect(engine.state.currentPlanFor('launch'), flight);
    expect(flight.remainingMs, remainingMs);
    expect(engine.state.marsKits, 0);

    expect(engine.setFacilityEnabled('launch', false), isNull);
    await draw();
    expect(find.textContaining('休止中 · 基本維持費'), findsOneWidget);
    expect(find.textContaining('一時停止 ·'), findsOneWidget);
    expect(find.text('設備休止中・手動で再開'), findsOneWidget);

    expect(engine.setFacilityEnabled('launch', true), isNull);
    expect(engine.setDevelopmentEnabled('cargo_packaging', true), isNull);
    await draw();
    expect(find.textContaining('進行中 ·'), findsOneWidget);
    expect(find.text(paidTime), findsOneWidget);
    expect(find.byKey(Key('current-stop-reason-${flight.id}')), findsNothing);
    engine.advanceBy(Duration(milliseconds: remainingMs));
    expect(engine.state.marsKits, 1);
    expect(engine.state.earthKits, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'research overview fits the discovered field with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(780, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = GameEngine(GameState.initial(epoch));
      // An existing world's known discoveries are legitimate visible nodes.
      // Unexplored fields and descendants must not affect this overview.
      engine.state.research.addAll([
        'life_support',
        ResearchCatalog.idForCatalog('M01'),
      ]);
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 300,
              child: ResearchTree(
                game: engine.state,
                selectedId: 'life_support',
                onSelected: (id) => selected = id,
                requirementReasons: engine.researchRequirementReasons,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('research-fit')));
      await tester.pumpAndSettle();
      final canvas = tester.getRect(
        find.byKey(const Key('research-tree-canvas')),
      );
      final visible = engine.state.discoveredResearchIds
          .map((id) => ResearchCatalog.technologies[id]!)
          .where(
            (technology) =>
                technology.field == ResearchField.mechanics &&
                technology.isPurchasable,
          );
      for (final task in visible) {
        final node = find.byKey(Key('research-node-${task.id}'));
        final bounds = tester.getRect(node);
        expect(canvas.contains(bounds.topLeft), isTrue, reason: task.id);
        expect(canvas.contains(bounds.bottomRight), isTrue, reason: task.id);
        expect(node.hitTestable(), findsOneWidget, reason: task.id);
      }
      expect(
        find.byKey(const Key('research-node-process_design')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const Key('research-node-automated_fabrication')),
      );
      await tester.pumpAndSettle();
      expect(selected, 'automated_fabrication');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'research nodes show paid time, preserved manual plans and suspension',
    (tester) async {
      tester.view.physicalSize = const Size(780, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // Saved, already-paid research keeps its frozen time on migration. New
      // enqueue calls use RP and cannot create this legacy running state.
      final state = GameState.initial(epoch)..money = 5000;
      state.plans.add(
        PlannedTask(id: 'legacy-paid', taskId: 'life_support')
          ..status = 'running'
          ..iterationDurationMs = 120000
          ..remainingMs = 120000
          ..iterationSpecialists = GameContent.baselineDepartmentStaff,
      );
      state.plans.add(
        PlannedTask(id: 'legacy-next', taskId: 'cargo_packaging'),
      );
      state.nextPlanId = 3;
      final engine = GameEngine(GameState.fromJson(state.toJson()));
      engine.advanceBy(const Duration(seconds: 30));
      Future<void> draw() => tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: ResearchTree(
              game: engine.state,
              selectedId: 'life_support',
              onSelected: (_) {},
              requirementReasons: engine.researchRequirementReasons,
            ),
          ),
        ),
      );
      final semantics = tester.ensureSemantics();
      try {
        await draw();
        final spoken = tester
            .getSemantics(
              find.byKey(const Key('research-semantics-life_support')),
            )
            .getSemanticsData();
        expect(
          spoken.label,
          '${GameContent.tasks['life_support']!.name}、研究中、残り 1分30秒',
        );
        expect(spoken.hasAction(SemanticsAction.tap), isTrue);
        expect(find.text('残り 1分30秒'), findsOneWidget);
        expect(find.textContaining('要着手 · 条件を確認して解放'), findsOneWidget);
        engine.setFacilityEnabled('lab', false);
        await draw();
        expect(find.text('研究中・休止'), findsOneWidget);
        expect(find.text('残り 1分30秒 · 再開待ち'), findsOneWidget);
        expect(find.textContaining('要着手 · 条件を確認して解放'), findsOneWidget);
        // The shared status contract still prevents duplicate reservation in details.
        expect(
          researchStatus(engine.state, GameContent.tasks['life_support']!),
          '研究中',
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
