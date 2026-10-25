import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/main.dart';
import 'package:mars_terraforming/presentation/mission_opening.dart';
import 'package:mars_terraforming/presentation/title_screen.dart';

class _StartupSave implements SaveRepository {
  Map<String, dynamic>? data;
  Completer<void>? saving;
  Object? loadFailure;
  Object? saveFailure;
  int saves = 0;

  @override
  Future<SaveLoadResult> load() async {
    if (loadFailure case final failure?) throw failure;
    return SaveLoadResult(data: data, recovered: false, generation: 1);
  }

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    saves++;
    if (saving case final pending?) await pending.future;
    if (saveFailure case final failure?) throw failure;
    data = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  }
}

void main() {
  final epoch = DateTime.utc(2026, 10, 25);

  Future<void> mount(WidgetTester tester, GameController controller) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MarsApp(controller: controller, renderScene: false),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('title-start')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  testWidgets('new worlds show the title before any opening or budget use', (
    tester,
  ) async {
    var now = epoch;
    final store = _StartupSave();
    final controller = GameController(store, now: () => now);
    addTearDown(controller.dispose);
    await controller.initialize(startTimer: false);
    final initialMoney = controller.state.moneyUnits;
    await mount(tester, controller);
    expect(find.byType(TitleScreen), findsOneWidget);
    expect(find.byType(MissionOpening), findsNothing);
    expect(controller.state.openingStarted, isFalse);

    now = epoch.add(const Duration(hours: 8));
    await controller.resume();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.state.moneyUnits, initialMoney);
    expect(controller.state.simulatedMs, 0);
    expect(controller.state.openingSeen, isFalse);
    expect(controller.state.openingStarted, isFalse);

    await start(tester);
    expect(find.byType(TitleScreen), findsNothing);
    expect(find.byType(MissionOpening), findsOneWidget);
    expect(controller.state.openingStarted, isTrue);
    expect(controller.state.openingSeen, isFalse);
    expect(controller.state.moneyUnits, initialMoney);
    expect(controller.state.simulatedMs, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.save();
  });

  testWidgets(
    'saved worlds catch up once, continue after the title and show it on next cold launch',
    (tester) async {
      var now = epoch.add(const Duration(minutes: 10));
      final initial = GameState.initial(epoch)
        ..openingSeen = true
        ..openingStarted = true
        ..firstRunTutorial = FirstRunTutorialStep.completed;
      final expected = GameEngine(GameState.fromJson(initial.toJson()))
        ..advanceTo(now);
      final store = _StartupSave()..data = initial.toJson();
      final controller = GameController(store, now: () => now);
      addTearDown(controller.dispose);
      await controller.initialize(startTimer: false);
      await mount(tester, controller);
      expect(find.byType(TitleScreen), findsOneWidget);
      expect(controller.state.toJson(), expected.state.toJson());
      final savesBeforeStart = store.saves;
      await start(tester);
      expect(find.byType(TitleScreen), findsNothing);
      expect(find.byType(MissionOpening), findsNothing);
      expect(find.byKey(const Key('navigation-1')), findsOneWidget);
      expect(controller.state.toJson(), expected.state.toJson());
      expect(store.saves, savesBeforeStart);

      now = now.add(const Duration(minutes: 2));
      expected.advanceTo(now);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(TitleScreen), findsNothing);
      expect(controller.state.toJson(), expected.state.toJson());

      await tester.pumpWidget(const SizedBox.shrink());
      await controller.save();
      final resumed = GameController(store, now: () => now);
      addTearDown(resumed.dispose);
      await resumed.initialize(startTimer: false);
      await mount(tester, resumed);
      expect(find.byType(TitleScreen), findsOneWidget);
      expect(resumed.state.toJson(), expected.state.toJson());
      await start(tester);
      expect(find.byKey(const Key('navigation-1')), findsOneWidget);
      expect(resumed.state.toJson(), expected.state.toJson());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('the initial save must finish before the title is actionable', (
    tester,
  ) async {
    final gate = Completer<void>();
    final store = _StartupSave()..saving = gate;
    final controller = GameController(store, now: () => epoch);
    addTearDown(controller.dispose);
    final loading = controller.initialize(startTimer: false);
    await mount(tester, controller);
    expect(find.byType(TitleScreen), findsNothing);
    expect(find.byKey(const Key('title-start')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    gate.complete();
    await loading;
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TitleScreen), findsOneWidget);
    expect(store.data, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final failure in ['corrupt', 'locked', 'save']) {
    testWidgets('$failure storage cannot expose the title or opening', (
      tester,
    ) async {
      final store = _StartupSave();
      if (failure == 'locked') {
        store.loadFailure = const SaveConflictException('別のタブで使用中');
      } else if (failure == 'corrupt') {
        store.loadFailure = const FormatException('保存データが壊れています');
      } else {
        store.saveFailure = StateError('空き容量がありません');
      }
      final controller = GameController(store, now: () => epoch);
      addTearDown(controller.dispose);
      await controller.initialize(startTimer: false);
      await mount(tester, controller);
      expect(find.byType(TitleScreen), findsNothing);
      expect(find.byType(MissionOpening), findsNothing);
      expect(find.textContaining('開始せずに停止'), findsOneWidget);
      expect(store.data, isNull);
      expect(store.saves, failure == 'save' ? 1 : 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
