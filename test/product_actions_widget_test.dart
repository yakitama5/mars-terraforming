import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/main.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/presentation/research_tree.dart';
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
    expect(tester.widget<Text>(status).data, contains('生命維持の実証が完了'));
    expect(controller.state.unreadCompletionNotices, hasLength(1));
    expect(tester.takeException(), isNull);
  });

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
      await tester.tap(find.byKey(const Key('navigation-2')));
      await tester.pumpAndSettle();
      for (final (id, expected) in [
        ('urban_planning', '住宅Lv.2・研究地区・工業地区・エリシウム研究都市'),
        ('orbital_logistics', '軌道補給受注・火星へ6基輸送・ヘラス・第2港・輸送効率上限45%'),
        ('intercity_logistics', '全輸送の効率を追加+15%・新しい空・輸送効率上限60%'),
      ]) {
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
