import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/presentation/early_development_guide.dart';
import 'package:mars_terraforming/presentation/mission_dialogue.dart';

class _GuideSave implements SaveRepository {
  bool conflict = false;

  @override
  Future<SaveLoadResult> load() async =>
      const SaveLoadResult(data: null, recovered: false, generation: 1);

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    if (conflict) throw const SaveConflictException('別の画面で更新');
  }
}

Future<void> _mount(
  WidgetTester tester,
  GameController controller,
  List<String> opened,
  Size size, {
  double textScale = 1,
  double cardWidth = 320,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: cardWidth,
            child: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: controller,
                builder: (_, _) => controller.engine == null
                    ? const Text('保存状態を確認')
                    : EarlyDevelopmentGuide(
                        controller: controller,
                        compact: true,
                        onResearch: (id) => opened.add('research:$id'),
                        onCity: (id) => opened.add('city:$id'),
                        onOperations: (id, {String? facilityId}) => opened.add(
                          'operations:$id${facilityId == null ? '' : ':$facilityId'}',
                        ),
                        onAgency: (id) => opened.add('agency:$id'),
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  final epoch = DateTime.utc(2026, 10, 15);

  for (final size in [const Size(568, 320), const Size(844, 390)]) {
    testWidgets('roadmap remains readable and routes actions at $size', (
      tester,
    ) async {
      final controller = GameController(_GuideSave(), now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      final opened = <String>[];
      await _mount(tester, controller, opened, size);
      expect(find.text('手引き'), findsOneWidget);
      expect(find.byTooltip('導入の手順と達成状況を確認'), findsOneWidget);
      final before = jsonEncode(controller.state.toJson());
      await tester.tap(find.byKey(const Key('guide-roadmap')));
      await tester.pumpAndSettle();
      expect(find.byType(MissionDialogue), findsOneWidget);
      expect(
        find.byKey(const Key('mission-dialogue-portrait')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('onboarding-open-first_research')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('onboarding-open-first_district')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('onboarding-list')));
      await tester.pumpAndSettle();
      expect(find.textContaining('順番や期限の制限はなく'), findsOneWidget);
      for (final id in [
        'first_research',
        'first_district',
        'urban_planning',
        'first_kit',
        'first_launch',
        'moon_base',
        'mars_probe',
        'first_landing',
        'first_habitat',
      ]) {
        expect(find.byKey(Key('onboarding-step-$id')), findsOneWidget);
      }
      final expandCity = find.byKey(
        const Key('onboarding-toggle-first_district'),
      );
      await tester.ensureVisible(expandCity);
      await tester.pumpAndSettle();
      await tester.tap(expandCity);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('onboarding-open-first_research')),
        findsNothing,
      );
      final city = find.byKey(const Key('onboarding-open-first_district'));
      await tester.ensureVisible(city);
      await tester.pumpAndSettle();
      await tester.tap(city);
      await tester.pumpAndSettle();
      expect(opened, ['city:earth_delta']);
      expect(find.byType(Dialog), findsNothing);
      expect(jsonEncode(controller.state.toJson()), before);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('wide guide names the nine-step instructions beside progress', (
    tester,
  ) async {
    final controller = GameController(_GuideSave(), now: () => epoch);
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    await _mount(tester, controller, [], const Size(844, 390), cardWidth: 560);
    expect(find.text('9工程の手引き'), findsOneWidget);
    expect(
      tester.getCenter(find.text('9工程の手引き')).dy,
      closeTo(tester.getCenter(find.text('最初の1時間 · 0/9達成')).dy, 1),
    );
    await tester.tap(find.byKey(const Key('guide-roadmap')));
    await tester.pumpAndSettle();
    expect(find.text('宇宙開発の手引き · 0/9達成'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'primary action and dialogue navigation stay usable with larger text',
    (tester) async {
      final controller = GameController(_GuideSave(), now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      final opened = <String>[];
      await _mount(
        tester,
        controller,
        opened,
        const Size(568, 320),
        textScale: 1.5,
      );
      expect(
        tester.widget(find.byKey(const Key('next-goal'))),
        isA<FilledButton>(),
      );
      expect(find.text('研究を開く'), findsOneWidget);
      await tester.tap(find.byKey(const Key('next-goal')));
      expect(opened, ['research:life_support']);
      await tester.tap(find.byKey(const Key('guide-roadmap')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('onboarding-open-first_research')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('onboarding-list')));
      await tester.pumpAndSettle();
      final last = find.byKey(const Key('onboarding-toggle-first_habitat'));
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      await tester.tap(last);
      await tester.pumpAndSettle();
      final destination = find.byKey(
        const Key('onboarding-open-first_habitat'),
      );
      await tester.ensureVisible(destination);
      await tester.pumpAndSettle();
      expect(destination.hitTestable(), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('mission-dialogue-scroll')),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(destination.hitTestable(), findsOneWidget);
      expect(
        find.byKey(const Key('onboarding-close')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('onboarding-list')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('onboarding-list')));
      await tester.pumpAndSettle();
      final first = find.byKey(const Key('onboarding-toggle-first_research'));
      await tester.ensureVisible(first);
      await tester.pumpAndSettle();
      await tester.tap(first);
      await tester.pumpAndSettle();
      final dialogueScroll = tester.widget<SingleChildScrollView>(
        find.byKey(const Key('mission-dialogue-scroll')),
      );
      expect(dialogueScroll.controller!.offset, 0);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('onboarding-close')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets(
    'preserved research opens manual-start status without a second timer',
    (tester) async {
      final controller = GameController(_GuideSave(), now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      final opened = <String>[];
      controller.state.researchPointUnits = 0;
      controller.state.plans.add(
        PlannedTask(id: 'preserved-research', taskId: 'life_support')
          ..requiresManualStart = true
          ..stopReason = '着手待ち：条件を確認して手動で開始',
      );
      await _mount(tester, controller, opened, const Size(844, 390));
      expect(find.textContaining('要着手'), findsOneWidget);
      await tester.tap(find.byKey(const Key('next-goal')));
      expect(opened.last, 'operations:0:lab');
      await tester.tap(find.byKey(const Key('guide-roadmap')));
      await tester.pumpAndSettle();
      expect(find.textContaining('要着手'), findsWidgets);
      final queued = find.byKey(const Key('onboarding-open-first_research'));
      await tester.ensureVisible(queued);
      await tester.pumpAndSettle();
      await tester.tap(queued);
      await tester.pumpAndSettle();
      expect(opened.last, 'operations:0:lab');
      expect(tester.takeException(), isNull);
    },
  );

  for (final (taskId, stepId, facilityId) in [
    ('habitat_kit', 'first_kit', 'factory'),
    ('mars_delivery', 'first_landing', 'launch'),
    ('district_mars_habitat', 'first_habitat', 'mars'),
  ]) {
    testWidgets(
      'current and paused $taskId guide actions preserve the target facility',
      (tester) async {
        final controller = GameController(_GuideSave(), now: () => epoch);
        await controller.initialize(startTimer: false);
        addTearDown(controller.dispose);
        controller.state
          ..money = 100000
          ..earthLevel = 2
          ..research.addAll(['life_support', 'urban_planning'])
          ..achievements.add('first_launch');
        if (taskId != 'habitat_kit') {
          controller.state.achievements.add('mars_route_open');
        }
        if (taskId == 'mars_delivery') controller.state.earthKits = 1;
        if (taskId == 'district_mars_habitat') {
          controller.state
            ..achievements.add('first_landing')
            ..habitatChoice = 'dome'
            ..marsKits = 1;
        }
        await controller.command(
          (engine) => taskId == 'district_mars_habitat'
              ? engine.enqueueDistrict('mars_arcadia', 0, 'mars_habitat')
              : engine.enqueue(taskId),
        );
        final opened = <String>[];
        await _mount(tester, controller, opened, const Size(568, 320));
        final before = jsonEncode(controller.state.toJson());
        final mainAction = find.byKey(const Key('next-goal'));
        await tester.ensureVisible(mainAction);
        await tester.pumpAndSettle();
        await tester.tap(mainAction);
        expect(opened.last, 'operations:0:$facilityId');
        expect(jsonEncode(controller.state.toJson()), before);

        await controller.command(
          (engine) => engine.setFacilityEnabled(facilityId, false),
        );
        await tester.pumpAndSettle();
        expect(find.text('停止理由を確認する'), findsOneWidget);
        await tester.ensureVisible(mainAction);
        await tester.pumpAndSettle();
        await tester.tap(mainAction);
        expect(opened.last, 'operations:0:$facilityId');

        final roadmap = find.byKey(const Key('guide-roadmap'));
        await tester.ensureVisible(roadmap);
        await tester.pumpAndSettle();
        await tester.tap(roadmap);
        await tester.pumpAndSettle();
        final stepAction = find.byKey(Key('onboarding-open-$stepId'));
        await tester.ensureVisible(stepAction);
        await tester.pumpAndSettle();
        await tester.tap(stepAction);
        await tester.pumpAndSettle();
        expect(opened.last, 'operations:0:$facilityId');
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('guide sends an unaffordable next action to funding options', (
    tester,
  ) async {
    final controller = GameController(_GuideSave(), now: () => epoch);
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    controller.state.money = 100;
    controller.state.research.add('life_support');
    controller.state.achievements.addAll(['first_launch', 'mars_route_open']);
    final opened = <String>[];
    await _mount(tester, controller, opened, const Size(844, 390));
    expect(find.textContaining('の資金を準備'), findsOneWidget);
    await tester.tap(find.byKey(const Key('next-goal')));
    expect(opened, ['operations:1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'completed roadmap can be reopened and progress stays accessible',
    (tester) async {
      final controller = GameController(_GuideSave(), now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      controller.state
        ..research.addAll(['life_support', 'urban_planning'])
        ..earthLevel = 2
        ..achievements.add('first_landing')
        ..habitatChoice = 'dome'
        ..marsHabitats = 1;
      await _mount(tester, controller, [], const Size(568, 320));
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('onboarding-progress')),
      );
      expect(bar.value, 1);
      expect(bar.semanticsLabel, contains('9/9達成'));
      for (var visit = 0; visit < 2; visit++) {
        await tester.tap(find.byKey(const Key('guide-roadmap')));
        await tester.pumpAndSettle();
        expect(find.text('宇宙開発の手引き · 9/9達成'), findsOneWidget);
        expect(
          tester.widget<MissionDialogue>(find.byType(MissionDialogue)).text,
          contains('ここからは、あなたの計画です。'),
        );
        await tester.tap(find.byKey(const Key('onboarding-close')));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('remaining time updates do not restart the spoken instructions', (
    tester,
  ) async {
    final controller = GameController(_GuideSave(), now: () => epoch);
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    controller.state.plans.add(
      PlannedTask(id: 'paid-research', taskId: 'life_support')
        ..status = 'running'
        ..remainingMs = 120000
        ..iterationDurationMs = 120000
        ..iterationSpecialists = GameContent.baselineDepartmentStaff,
    );
    await _mount(tester, controller, [], const Size(568, 320));
    await tester.tap(find.byKey(const Key('guide-roadmap')));
    await tester.pumpAndSettle();
    final dialogue = tester.widget<MissionDialogue>(
      find.byType(MissionDialogue),
    );
    final previousTime = controller.state.currentPlanFor('lab')!.remainingMs;
    await controller.command((engine) {
      engine.advanceBy(const Duration(seconds: 1));
      return null;
    });
    await tester.pump(const Duration(milliseconds: 50));
    final updated = tester.widget<MissionDialogue>(
      find.byType(MissionDialogue),
    );
    expect(updated.text, dialogue.text);
    expect(updated.dialogueKey, dialogue.dialogueKey);
    final rendered = tester.widget<Text>(
      find.byKey(const Key('mission-dialogue-text')),
    );
    final span = rendered.textSpan! as TextSpan;
    expect((span.children!.first as TextSpan).text, dialogue.text);
    expect(
      controller.state.currentPlanFor('lab')!.remainingMs,
      previousTime - 1000,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('open roadmap survives a save conflict that clears the engine', (
    tester,
  ) async {
    final store = _GuideSave();
    final controller = GameController(store, now: () => epoch);
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    await _mount(tester, controller, [], const Size(568, 320));
    await tester.tap(find.byKey(const Key('guide-roadmap')));
    await tester.pumpAndSettle();
    store.conflict = true;
    await controller.save();
    await tester.pumpAndSettle();
    expect(controller.engine, isNull);
    expect(find.text('手引きを更新できません'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('onboarding-close')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
