import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/colony_ending.dart';
import 'package:mars_terraforming/domain/contextual_tips.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/presentation/colony_endings.dart';
import 'package:mars_terraforming/presentation/contextual_tips.dart';
import 'package:mars_terraforming/presentation/early_development_guide.dart';
import 'package:mars_terraforming/presentation/mission_adviser.dart';
import 'package:mars_terraforming/presentation/mission_opening.dart';

class _ExpressionSave implements SaveRepository {
  @override
  Future<SaveLoadResult> load() async =>
      const SaveLoadResult(data: null, recovered: false, generation: 1);

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {}
}

Widget _app(Widget home) => MaterialApp(
  theme: ThemeData.dark(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child!,
  ),
  home: home,
);

MinaExpression _expression(WidgetTester tester) => tester
    .widget<MinaPortrait>(
      find.byWidgetPredicate((widget) => widget is MinaPortrait).last,
    )
    .expression;

void main() {
  final epoch = DateTime.utc(2026, 10, 16);
  GameEngine fresh() => GameEngine(GameState.initial(epoch));

  testWidgets('opening expressions follow each chapter and back navigation', (
    tester,
  ) async {
    final controller = GameController(_ExpressionSave(), now: () => epoch);
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    final before = jsonEncode(controller.state.toJson());
    await tester.pumpWidget(
      _app(
        MissionOpening(
          controller: controller,
          replay: true,
          playCinematic: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_expression(tester), MinaExpression.delight);
    await tester.tap(find.byKey(const Key('opening-next')));
    await tester.pumpAndSettle();
    expect(_expression(tester), MinaExpression.normal);
    await tester.tap(find.byKey(const Key('opening-next')));
    await tester.pumpAndSettle();
    expect(_expression(tester), MinaExpression.delight);
    await tester.tap(find.byKey(const Key('opening-back')));
    await tester.pumpAndSettle();
    expect(_expression(tester), MinaExpression.normal);
    expect(jsonEncode(controller.state.toJson()), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tip expressions distinguish opportunity blockage caution and success',
    (tester) async {
      final parallel = fresh()..enqueue('life_support');
      final paused = fresh();
      paused.state.researchPointUnits = 0;
      paused.state.plans.add(
        PlannedTask(id: 'paused-paid', taskId: 'life_support')
          ..status = 'running'
          ..remainingMs = 120000
          ..iterationDurationMs = 120000,
      );
      paused.setFacilityEnabled('lab', false);
      final repeated = fresh();
      repeated.state.research.add('life_support');
      repeated.enqueue('factory_contract', repeats: null);
      repeated.enqueue('habitat_kit');
      final landed = fresh();
      landed.state.achievements.add('first_landing');
      final prerequisite = fresh()..enqueue('habitat_kit');
      final lowFunds = fresh();
      lowFunds.state.money = 0;
      for (final (engine, category, expression) in [
        (parallel, 'parallel-city', MinaExpression.delight),
        (paused, 'paused', MinaExpression.sorrow),
        (repeated, 'unlimited', MinaExpression.anger),
        (landed, 'habitat-choice', MinaExpression.joy),
        (prerequisite, 'requirements', MinaExpression.normal),
        (lowFunds, 'low-operating-funds', MinaExpression.sorrow),
      ]) {
        final tip = evaluateContextualTips(engine.state).first;
        expect(tip.id.split(':').first, category);
        final before = jsonEncode(engine.state.toJson());
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: ContextualTipsPanel(
                game: engine.state,
                onOpen: (_) {},
                onDismiss: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(tip.title), findsOneWidget);
        expect(_expression(tester), expression, reason: tip.id);
        expect(jsonEncode(engine.state.toJson()), before);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'guide expressions respond to funds stops delivery and milestones',
    (tester) async {
      final controller = GameController(_ExpressionSave(), now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      final lowFunds = fresh();
      lowFunds.state.money = 0;
      lowFunds.state.research.add('life_support');
      lowFunds.state.achievements.addAll(['first_launch', 'mars_route_open']);
      final paused = fresh();
      paused.state.researchPointUnits = 0;
      paused.state.plans.add(
        PlannedTask(id: 'paused-paid', taskId: 'life_support')
          ..status = 'running'
          ..remainingMs = 120000
          ..iterationDurationMs = 120000,
      );
      paused.setFacilityEnabled('lab', false);
      final delivery = fresh();
      delivery.state.research.addAll({'life_support', 'urban_planning'});
      delivery.state.earthKits = 1;
      delivery.state.achievements.addAll(['first_launch', 'mars_route_open']);
      final landed = fresh();
      landed.state.research.addAll({'life_support', 'urban_planning'});
      landed.state.achievements.add('first_landing');
      final complete = fresh();
      complete.state.research.addAll({'life_support', 'urban_planning'});
      complete.state.achievements.add('first_landing');
      complete.state.earthLevel = 2;
      complete.state.habitatChoice = 'dome';
      complete.state.marsHabitats = 1;
      for (final (engine, title, expression) in [
        (
          fresh(),
          GameContent.tasks['life_support']!.name,
          MinaExpression.normal,
        ),
        (
          lowFunds,
          '${GameContent.tasks['habitat_kit']!.name}の資金を準備',
          MinaExpression.sorrow,
        ),
        (
          paused,
          '${GameContent.tasks['life_support']!.name}の停止を確認・再開',
          MinaExpression.sorrow,
        ),
        (delivery, '火星への輸送を準備', MinaExpression.delight),
        (landed, '火星の居住方式を選ぶ', MinaExpression.joy),
        (complete, '導入達成 · 次にできること', MinaExpression.joy),
      ]) {
        controller.engine = engine;
        final before = jsonEncode(engine.state.toJson());
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: SingleChildScrollView(
                child: EarlyDevelopmentGuide(
                  controller: controller,
                  compact: true,
                  onResearch: (_) {},
                  onCity: (_) {},
                  onOperations: (_, {String? facilityId}) {},
                  onAgency: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(_expression(tester), expression, reason: title);
        expect(jsonEncode(engine.state.toJson()), before);
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final ending in ColonyEnding.all) {
    testWidgets(
      '${ending.id} expression follows completed home and daily life',
      (tester) async {
        final game = GameState.initial(epoch);
        game.achievements.add(ending.id);
        final before = jsonEncode(game.toJson());
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showColonyEndings(context, game: game),
                  child: const Text('物語'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('物語'));
        await tester.pumpAndSettle();
        expect(_expression(tester), MinaExpression.normal);
        final play = find.byKey(Key('play-ending-${ending.id}'));
        await tester.ensureVisible(play);
        await tester.pumpAndSettle();
        await tester.tap(play);
        await tester.pumpAndSettle();
        expect(_expression(tester), MinaExpression.joy);
        await tester.tap(find.byKey(const Key('ending-next')));
        await tester.pumpAndSettle();
        expect(_expression(tester), MinaExpression.delight);
        await tester.tap(find.byKey(const Key('ending-next')));
        await tester.pumpAndSettle();
        expect(_expression(tester), MinaExpression.joy);
        await tester.tap(find.byKey(const Key('ending-back')));
        await tester.pumpAndSettle();
        expect(_expression(tester), MinaExpression.delight);
        expect(jsonEncode(game.toJson()), before);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
