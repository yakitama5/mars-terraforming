import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/main.dart';
import 'package:mars_terraforming/presentation/first_run_tutorial.dart';
import 'package:mars_terraforming/presentation/mission_sound.dart';
import 'package:mars_terraforming/rendering/city_scene.dart';

import 'widget_test.dart' show MemorySave;

void main() {
  Future<GameController> open(
    WidgetTester tester, {
    Size size = const Size(844, 390),
    double scale = 1,
    MemorySave? store,
    bool introduction = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    missionSoundEnabled.value = false;
    addTearDown(() => missionSoundEnabled.value = true);
    final controller = GameController(
      store ?? MemorySave(),
      now: () => DateTime.utc(2026, 10, 16),
    );
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    if (!controller.state.openingSeen) await controller.skipOpening();
    await tester.pumpWidget(
      MarsApp(
        showTitle: false,
        controller: controller,
        renderScene: false,
        showIntroduction: introduction,
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> placeHouse(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('district-option-housing')));
    await tester.pumpAndSettle();
    final scene = tester.widget<CityScene>(find.byType(CityScene));
    expect(scene.buildablePlots, contains(1));
    expect(scene.buildablePlots, isNot(contains(12)));
    expect(tester.getSize(find.byType(CityScene)).height, greaterThan(110));
    final confirm = find.byKey(const Key('confirm-district'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    final plot = find.byKey(const Key('plot-earth_delta-1'));
    expect(plot.hitTestable(), findsOneWidget);
    await tester.tap(plot);
    await tester.pumpAndSettle();
    expect(tester.widget<CityScene>(find.byType(CityScene)).selectedPlot, 1);
    expect(confirm.hitTestable(), findsOneWidget);
    final coach = tester.getRect(find.byKey(const Key('first-run-coach')));
    expect(coach.overlaps(tester.getRect(confirm)), isFalse);
    expect(coach.overlaps(tester.getRect(plot)), isFalse);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
  }

  for (final (size, scale) in [
    (const Size(844, 390), 1.0),
    (const Size(568, 320), 1.5),
  ]) {
    testWidgets('first orders stay reachable at $size / $scale', (
      tester,
    ) async {
      final controller = await open(tester, size: size, scale: scale);
      expect(find.byType(FirstRunTutorial), findsOneWidget);
      expect(find.byKey(const Key('navigation-2')), findsNothing);
      expect(find.byKey(const Key('open-guidance')), findsNothing);
      expect(find.byKey(const Key('district-option-industry')), findsNothing);
      expect(find.byKey(const Key('queue-life_support')), findsNothing);
      // A plot cannot skip the required facility selection.
      tester.widget<CityScene>(find.byType(CityScene)).onPlotSelected(1);
      await tester.pump();
      expect(find.byKey(const Key('district-option-housing')), findsOneWidget);
      await placeHouse(tester);
      expect(
        controller.state.firstRunTutorial,
        FirstRunTutorialStep.finishConstruction,
      );
      expect(controller.state.districtAt('earth_delta', 1), isNull);
      final finish = find.byKey(const Key('tutorial-complete-construction'));
      expect(finish.hitTestable(), findsOneWidget);
      await tester.tap(finish);
      await tester.pumpAndSettle();
      expect(controller.state.firstRunTutorial, FirstRunTutorialStep.income);
      expect(controller.state.districtAt('earth_delta', 1)?.level, 1);
      expect(controller.state.netPerMinute, greaterThan(0));
      expect(controller.state.completionNotices, hasLength(1));
      final income = find.byKey(const Key('tutorial-continue-income'));
      expect(income.hitTestable(), findsOneWidget);
      await tester.tap(income);
      await tester.pumpAndSettle();
      expect(
        controller.state.firstRunTutorial,
        FirstRunTutorialStep.startResearch,
      );
      final research = find.byKey(const Key('queue-life_support'));
      expect(research.hitTestable(), findsOneWidget);
      final detail = find.byKey(const Key('first-run-research-detail'));
      final costTime = find.byKey(const Key('first-run-research-cost-time'));
      final title = find.byKey(const Key('first-run-research-title'));
      expect(
        tester.widget<Text>(costTime).data,
        '必要 ${GameContent.researchPointCost('life_support')} RP · 保有 24.0 RP',
      );
      expect(find.text('技術を解放する'), findsOneWidget);
      expect(
        tester
            .state<ScrollableState>(
              find.descendant(of: detail, matching: find.byType(Scrollable)),
            )
            .position
            .pixels,
        0,
        reason: 'The RP cost and bank must be readable before scrolling.',
      );
      final visible = tester.getRect(detail);
      final facts = tester.getRect(costTime);
      expect(facts.top, greaterThanOrEqualTo(tester.getRect(title).bottom));
      expect(facts.top, greaterThanOrEqualTo(visible.top));
      expect(facts.bottom, lessThanOrEqualTo(visible.bottom));
      expect(facts.overlaps(tester.getRect(research)), isFalse);
      await tester.tap(research);
      await tester.pumpAndSettle();
      expect(
        controller.state.firstRunTutorial,
        FirstRunTutorialStep.researchStarted,
      );
      expect(
        controller.state.plans.where((p) => p.taskId == 'life_support'),
        hasLength(1),
      );
      expect(controller.state.research, contains('life_support'));
      expect(controller.state.currentPlanFor('lab'), isNull);
      expect(find.text('技術を解放しました'), findsOneWidget);
      expect(
        tester.widget<Text>(costTime).data,
        '${GameContent.researchPointCost('life_support')} RPを使用 · 解放済み',
      );
      final done = find.byKey(const Key('tutorial-finish'));
      expect(done.hitTestable(), findsOneWidget);
      await tester.tap(done);
      await tester.pumpAndSettle();
      expect(controller.state.firstRunTutorial, FirstRunTutorialStep.completed);
      expect(find.byType(FirstRunTutorial), findsNothing);
      expect(find.byKey(const Key('navigation-2')), findsOneWidget);
      expect(find.byKey(const Key('open-guidance')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'failed instant completion keeps the same order and exposes retry',
    (tester) async {
      final store = MemorySave();
      final controller = await open(tester, store: store);
      await placeHouse(tester);
      final money = controller.state.money;
      store.fail = true;
      await tester.tap(find.byKey(const Key('tutorial-complete-construction')));
      await tester.pumpAndSettle();
      expect(
        controller.state.firstRunTutorial,
        FirstRunTutorialStep.finishConstruction,
      );
      expect(controller.state.districtAt('earth_delta', 1), isNull);
      expect(controller.state.money, money);
      final retry = find.byKey(const Key('retry-game-save'));
      expect(retry.hitTestable(), findsOneWidget);
      store.fail = false;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tutorial-complete-construction')));
      await tester.pumpAndSettle();
      expect(controller.state.firstRunTutorial, FirstRunTutorialStep.income);
      expect(controller.state.completionNotices, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'paid research resumed from an older save keeps its remaining time',
    (tester) async {
      final engine = GameEngine(
        GameState.initial(DateTime.utc(2026, 10, 16))..openingSeen = true,
      );
      engine.enqueueDistrict('earth_delta', 0, 'housing');
      engine.completeTutorialConstruction();
      engine.continueFirstRunTutorial();
      engine.state
        ..firstRunTutorial = FirstRunTutorialStep.researchStarted
        ..researchPointUnits = 0
        ..plans.add(
          PlannedTask(
              id: 'plan-${engine.state.nextPlanId++}',
              taskId: 'life_support',
            )
            ..status = 'running'
            ..iterationDurationMs = 120000
            ..remainingMs = 90000
            ..iterationSpecialists = GameContent.baselineDepartmentStaff,
        );
      final old = engine.state.toJson()
        ..['contentVersion'] = 'district-6'
        ..remove('researchPointUnits');
      final store = MemorySave()..data = old;
      final controller = await open(tester, store: store);
      final facts = tester.widget<Text>(
        find.byKey(const Key('first-run-research-cost-time')),
      );
      expect(facts.data, contains('着手済み · 残り'));
      expect(facts.semanticsLabel, contains('支払済み'));
      expect(facts.semanticsLabel, contains('追加RPは必要ありません'));
      expect(find.text('着手済みの研究を継続中'), findsOneWidget);
      expect(controller.state.currentPlanFor('lab')!.remainingMs, 90000);
      expect(controller.state.researchPoints, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'resuming restores the first construction and does not place a second one',
    (tester) async {
      final store = MemorySave();
      final first = await open(tester, store: store);
      await placeHouse(tester);
      final world = first.state.worldId;
      await tester.pumpWidget(const SizedBox.shrink());
      final resumed = GameController(
        store,
        now: () => DateTime.utc(2026, 10, 17),
      );
      await resumed.initialize(startTimer: false);
      addTearDown(resumed.dispose);
      await tester.pumpWidget(
        MarsApp(showTitle: false, controller: resumed, renderScene: false),
      );
      await tester.pumpAndSettle();
      expect(resumed.state.worldId, world);
      expect(
        resumed.state.firstRunTutorial,
        FirstRunTutorialStep.finishConstruction,
      );
      expect(resumed.state.plans, hasLength(1));
      expect(tester.widget<CityScene>(find.byType(CityScene)).selectedPlot, 1);
      expect(
        find.byKey(const Key('tutorial-complete-construction')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byKey(const Key('district-option-housing')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'older saves and explicit introduction suppression remain free to play',
    (tester) async {
      final old = GameState.initial(DateTime.utc(2026, 10, 16)).toJson()
        ..remove('firstRunTutorial')
        ..remove('firstRunTutorialPlanId')
        ..['openingSeen'] = true;
      final store = MemorySave()..data = old;
      final controller = await open(tester, store: store);
      expect(controller.state.firstRunTutorial, FirstRunTutorialStep.completed);
      expect(find.byType(FirstRunTutorial), findsNothing);
      await tester.tap(find.byKey(const Key('navigation-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('research-detail')), findsNothing);
      await tester.tap(find.byKey(const Key('research-node-life_support')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('queue-life_support')).hitTestable(),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, introduction: false);
      expect(find.byType(FirstRunTutorial), findsNothing);
      expect(find.byKey(const Key('navigation-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
