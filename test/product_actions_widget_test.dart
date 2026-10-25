import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/main.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/presentation/research_tree.dart';
import 'package:mars_terraforming/presentation/research_display.dart';
import 'package:mars_terraforming/presentation/early_development_guide.dart';

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
      MarsApp(
        showTitle: false,
        showIntroduction: false,
        controller: controller,
        renderScene: false,
      ),
    );
    return controller;
  }

  testWidgets('guide destination scrolls the requested facility into view', (
    tester,
  ) async {
    await open(tester);
    tester
        .widget<EarlyDevelopmentGuide>(find.byType(EarlyDevelopmentGuide))
        .onOperations(0, facilityId: 'launch');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('facility-toggle-launch')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('command refusal remains visible over unread completions', (
    tester,
  ) async {
    final controller = await open(tester);
    controller.state.completionNotices.add(
      const CompletionNotice(
        id: 1,
        planId: 'finished-research',
        taskId: 'life_support',
        simulatedMs: 0,
      ),
    );
    controller.state.nextCompletionNoticeId = 2;
    await controller.command(
      (engine) => engine.setFacilityEnabled('factory', false),
    );
    controller.state.moneyUnits = 0;
    await controller.command(
      (engine) => engine.setFacilityEnabled('factory', true),
    );
    await tester.pump();
    final status = find.byKey(const Key('status-message'));
    expect(tester.widget<Text>(status).data, contains('再開には維持費1分分'));
    expect(controller.state.facilities['factory'], isFalse);
    expect(find.text('通知 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(
      tester.widget<Text>(status).data,
      contains('${GameContent.tasks['life_support']!.name}が完了'),
    );
    expect(controller.state.unreadCompletionNotices, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('unseen research selection leaves the tree unselected', (
    tester,
  ) async {
    final controller = await open(tester);
    final before = jsonEncode(controller.state.toJson());
    await tester.tap(find.byKey(const Key('navigation-2')));
    await tester.pumpAndSettle();
    tester
        .widget<ResearchTree>(find.byType(ResearchTree))
        .onSelected('habitat_operations');
    await tester.pumpAndSettle();
    expect(
      controller.state.isResearchDiscovered('habitat_operations'),
      isFalse,
    );
    expect(
      find.text(GameContent.tasks['habitat_operations']!.name),
      findsNothing,
    );
    final known = tester
        .widget<ResearchTree>(find.byType(ResearchTree))
        .selectedId;
    expect(known, isNull);
    expect(find.byKey(const Key('research-detail')), findsNothing);
    tester
        .widget<ResearchTree>(find.byType(ResearchTree))
        .onSelected('life_support');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('queue-life_support')), findsOneWidget);
    expect(find.byKey(const Key('research-unlocks')), findsOneWidget);
    expect(jsonEncode(controller.state.toJson()), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'research unlocks use player city names without cascading replacements',
    (tester) async {
      final controller = await open(tester);
      await controller.updateMissionIdentity(
        cities: {
          'earth_highland': 'エリシウム研究都市',
          'mars_elysium': 'ヘラス・第2港',
          'mars_hellas': '新しい空',
        },
        rocket: controller.state.rocketName,
      );
      // Imported knowledge is an explicit existing-world fixture. These three
      // routes may then be inspected, while other discoveries remain hidden.
      controller.state.research.addAll([
        'urban_planning',
        'orbital_logistics',
        'intercity_logistics',
      ]);
      final namedPreview = TaskDefinition(
        id: 'city_name_preview',
        name: '都市名を使う解放説明',
        facilityId: 'lab',
        durationSeconds: 0,
        cost: 0,
        description: '',
        unlockSummary: [
          GameContent.cities['earth_highland']!.name,
          GameContent.cities['mars_elysium']!.name,
          GameContent.cities['mars_hellas']!.name,
        ].join('・'),
      );
      expect(
        researchUnlockSummary(controller.state, namedPreview),
        'エリシウム研究都市・ヘラス・第2港・新しい空',
      );
      await tester.tap(find.byKey(const Key('navigation-2')));
      await tester.pumpAndSettle();
      for (final id in [
        'urban_planning',
        'orbital_logistics',
        'intercity_logistics',
      ]) {
        final expected = researchUnlockSummary(
          controller.state,
          GameContent.tasks[id]!,
        );
        tester.widget<ResearchTree>(find.byType(ResearchTree)).onSelected(id);
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.byKey(const Key('research-unlocks'))).data,
          expected,
        );
        expect(
          tester.widget<Text>(find.byKey(Key('research-progress-$id'))).data,
          expected,
        );
      }
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();
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
