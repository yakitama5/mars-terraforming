import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/main.dart';
import 'package:mars_terraforming/presentation/research_tree.dart';

import 'widget_test.dart' show MemorySave;

void main() {
  Future<GameController> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = GameController(MemorySave());
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MarsApp(controller: controller, renderScene: false),
    );
    return controller;
  }

  testWidgets(
    'research prerequisites lead to their actionable details without changing the world',
    (tester) async {
      final controller = await open(tester);
      final before = jsonEncode(controller.state.toJson());
      await tester.tap(find.byKey(const Key('navigation-2')));
      await tester.pumpAndSettle();
      tester
          .widget<ResearchTree>(find.byType(ResearchTree))
          .onSelected('habitat_operations');
      await tester.pumpAndSettle();
      final prerequisite = find.byKey(
        const Key('research-prerequisite-life_support'),
      );
      await tester.scrollUntilVisible(
        prerequisite,
        100,
        scrollable: find.descendant(
          of: find.byKey(const Key('research-detail')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(prerequisite);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('queue-life_support')), findsOneWidget);
      expect(find.byKey(const Key('research-unlocks')), findsOneWidget);
      expect(jsonEncode(controller.state.toJson()), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'transport habitat choice can be cancelled and only confirmed once',
    (tester) async {
      final controller = await open(tester);
      controller.state.achievements.add('first_landing');
      await tester.tap(find.byKey(const Key('navigation-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('operations-2')));
      await tester.pumpAndSettle();
      final choice = find.byKey(const Key('choose-dome'));
      await tester.scrollUntilVisible(
        choice,
        120,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('operations-list-2')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(controller.state.habitatChoice, isNull);
      await tester.tap(find.byKey(const Key('cancel-habitat-choice')));
      await tester.pumpAndSettle();
      expect(controller.state.habitatChoice, isNull);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-habitat-choice')));
      await tester.pumpAndSettle();
      expect(controller.state.habitatChoice, 'dome');
      expect(find.byKey(const Key('choose-dome')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
