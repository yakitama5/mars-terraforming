import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/presentation/early_development_guide.dart';

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
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
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
                        onOperations: (id) => opened.add('operations:$id'),
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
      final before = jsonEncode(controller.state.toJson());
      await tester.tap(find.byKey(const Key('guide-roadmap')));
      await tester.pumpAndSettle();
      expect(find.textContaining('順番や期限の制限はなく'), findsOneWidget);
      final city = find.byKey(const Key('onboarding-open-first_district'));
      await tester.ensureVisible(city);
      await tester.pumpAndSettle();
      await tester.tap(city);
      await tester.pumpAndSettle();
      expect(opened, ['city:earth_delta']);
      expect(find.byType(AlertDialog), findsNothing);
      expect(jsonEncode(controller.state.toJson()), before);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('running and ordinarily queued research open equipment status', (
    tester,
  ) async {
    final controller = GameController(_GuideSave(), now: () => epoch);
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    final opened = <String>[];
    await controller.command((engine) {
      engine.enqueue('urban_planning');
      return engine.enqueue('life_support');
    });
    await _mount(tester, controller, opened, const Size(844, 390));
    expect(find.textContaining('予約済み · 共用設備の順番待ち'), findsOneWidget);
    await tester.tap(find.byKey(const Key('next-goal')));
    expect(opened.last, 'operations:0');
    await tester.tap(find.byKey(const Key('guide-roadmap')));
    await tester.pumpAndSettle();
    expect(find.text('予約済み · 設備の順番待ち'), findsOneWidget);
    final queued = find.byKey(const Key('onboarding-open-first_research'));
    await tester.ensureVisible(queued);
    await tester.pumpAndSettle();
    await tester.tap(queued);
    await tester.pumpAndSettle();
    expect(opened.last, 'operations:0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('guide sends an unaffordable next action to funding options', (
    tester,
  ) async {
    final controller = GameController(_GuideSave(), now: () => epoch);
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    controller.state.money = 100;
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
      expect(bar.semanticsLabel, contains('6/6達成'));
      for (var visit = 0; visit < 2; visit++) {
        await tester.tap(find.byKey(const Key('guide-roadmap')));
        await tester.pumpAndSettle();
        expect(find.text('最初の1時間の手引き · 6/6達成'), findsOneWidget);
        await tester.tap(find.byKey(const Key('onboarding-close')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

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
