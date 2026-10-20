import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 16);

  Future<GameController> start(
    _TutorialRepository store, {
    DateTime Function()? now,
  }) async {
    final controller = GameController(store, now: now ?? () => epoch);
    addTearDown(controller.dispose);
    await controller.initialize(startTimer: false);
    await controller.skipOpening();
    return controller;
  }

  Future<void> placeHouse(GameController controller) async {
    await controller.command(
      (game) => game.enqueueDistrict('earth_delta', 0, 'housing'),
    );
    expect(
      controller.state.firstRunTutorial,
      FirstRunTutorialStep.finishConstruction,
    );
  }

  Future<void> startResearch(GameController controller) async {
    await placeHouse(controller);
    expect(await controller.completeTutorialConstruction(), isTrue);
    expect(await controller.continueFirstRunTutorial(), isTrue);
    await controller.command((game) => game.enqueue('life_support'));
    expect(
      controller.state.firstRunTutorial,
      FirstRunTutorialStep.researchStarted,
    );
  }

  test(
    'an interrupted first launch before the OP callback retains its budget',
    () async {
      var now = epoch;
      final store = _TutorialRepository();
      final first = GameController(store, now: () => now);
      await first.initialize(startTimer: false);
      expect(first.state.openingStarted, isFalse);
      first.dispose();
      now = epoch.add(const Duration(days: 20));
      final restored = GameController(store, now: () => now);
      addTearDown(restored.dispose);
      await restored.initialize(startTimer: false);
      expect(restored.state.simulatedMs, 0);
      expect(restored.state.money, 900);
      expect(
        restored.state.firstRunTutorial,
        FirstRunTutorialStep.placeHousing,
      );
      expect(restored.state.lastWallClockMs, now.millisecondsSinceEpoch);
    },
  );

  test(
    'an existing save never receives the tutorial or a frozen economy',
    () async {
      final old = GameState.initial(epoch).toJson()
        ..remove('firstRunTutorial')
        ..remove('firstRunTutorialPlanId')
        ..['openingSeen'] = true;
      final store = _TutorialRepository()..data = old;
      final controller = GameController(
        store,
        now: () => epoch.add(const Duration(minutes: 1)),
      );
      addTearDown(controller.dispose);
      await controller.initialize(startTimer: false);
      expect(controller.state.firstRunTutorial, FirstRunTutorialStep.completed);
      expect(controller.state.simulatedMs, 60000);
      expect(controller.state.money, 888);
      await controller.command(
        (game) => game.enqueueDistrict('earth_delta', 0, 'housing'),
      );
      expect(await controller.completeTutorialConstruction(), isFalse);
      expect(controller.state.districts, isEmpty);
      expect(controller.state.plans.single.status, 'running');
    },
  );

  test(
    'failed placement leaves the original money, plan and phase for retry',
    () async {
      final store = _TutorialRepository();
      final controller = await start(store);
      final before = controller.state.toJson();
      store.failure = StateError('disk full');
      await controller.command(
        (game) => game.enqueueDistrict('earth_delta', 0, 'housing'),
      );
      expect(controller.error, contains('自動保存に失敗'));
      expect(controller.state.toJson(), before);
      expect(store.data, before);
      store.failure = null;
      final restarted = await start(store);
      await placeHouse(restarted);
      expect(restarted.state.plans, hasLength(1));
      expect(restarted.state.money, 550);
      expect(store.data, restarted.state.toJson());
    },
  );

  test(
    'delayed help publishes only after commit and joins duplicate saves',
    () async {
      final store = _TutorialRepository();
      final controller = await start(store);
      await placeHouse(controller);
      final before = controller.state.toJson();
      final attempts = store.saveAttempts;
      final gate = Completer<void>();
      store.beforeSave = (_) => gate.future;
      final helping = controller.completeTutorialConstruction();
      await Future<void>.delayed(Duration.zero);
      expect(controller.busy, isTrue);
      expect(controller.state.toJson(), before);
      expect(await controller.completeTutorialConstruction(), isFalse);
      final concurrentSave = controller.save();
      gate.complete();
      expect(await helping, isTrue);
      await concurrentSave;
      expect(controller.busy, isFalse);
      expect(store.saveAttempts, attempts + 1);
      expect(controller.state.firstRunTutorial, FirstRunTutorialStep.income);
      expect(controller.state.completionNotices, hasLength(1));
      expect(controller.state.population, 180);
      expect(controller.state.simulatedMs, 0);
      expect(store.data, controller.state.toJson());
    },
  );

  test(
    'failed instant completion survives restart and grants its effects once',
    () async {
      final store = _TutorialRepository();
      final controller = await start(store);
      await placeHouse(controller);
      final paid = controller.state.toJson();
      store.failure = StateError('storage unavailable');
      expect(await controller.completeTutorialConstruction(), isFalse);
      expect(controller.state.toJson(), paid);
      expect(store.data, paid);
      expect(controller.state.districts, isEmpty);
      store.failure = null;
      final restarted = await start(store);
      expect(await restarted.completeTutorialConstruction(), isTrue);
      final completed = restarted.state.toJson();
      expect(await restarted.completeTutorialConstruction(), isFalse);
      expect(restarted.state.toJson(), completed);
      expect(restarted.state.money, 550);
      expect(restarted.state.population, 180);
      expect(restarted.state.completionNotices, hasLength(1));
      expect(restarted.state.claimedRewards, isEmpty);
    },
  );

  test('a write acknowledged as failure after commit still restarts without duplicate completion', () async {
    final store = _TutorialRepository();
    final controller = await start(store);
    await placeHouse(controller);
    store.failAfterCommit = true;
    expect(await controller.completeTutorialConstruction(), isFalse);
    expect(
      controller.state.firstRunTutorial,
      FirstRunTutorialStep.finishConstruction,
    );
    expect(store.data!['firstRunTutorial'], 'income');
    store.failAfterCommit = false;
    final restarted = await start(store);
    expect(restarted.state.firstRunTutorial, FirstRunTutorialStep.income);
    expect(await restarted.completeTutorialConstruction(), isFalse);
    expect(restarted.state.population, 180);
    expect(restarted.state.completionNotices, hasLength(1));
    expect(restarted.state.money, 550);
  });

  test(
    'failed research unlock does not consume RP or advance its required step',
    () async {
      final store = _TutorialRepository();
      final controller = await start(store);
      await placeHouse(controller);
      await controller.completeTutorialConstruction();
      await controller.continueFirstRunTutorial();
      final before = controller.state.toJson();
      store.failure = StateError('disk full');
      await controller.command((game) => game.enqueue('life_support'));
      expect(controller.state.toJson(), before);
      expect(store.data, before);
      store.failure = null;
      await controller.command((game) => game.enqueue('life_support'));
      expect(
        controller.state.firstRunTutorial,
        FirstRunTutorialStep.researchStarted,
      );
      expect(controller.state.money, 550);
      expect(controller.state.currentPlanFor('lab'), isNull);
      expect(controller.state.researchPoints, 0);
      expect(controller.state.research, contains('life_support'));
    },
  );

  test('failed exit, forward/back clocks and restart preserve unlocked research and RP', () async {
    var now = epoch;
    final store = _TutorialRepository();
    final controller = await start(store, now: () => now);
    await startResearch(controller);
    final money = controller.state.moneyUnits;
    final points = controller.state.researchPointUnits;
    store.failure = StateError('disk full');
    expect(await controller.continueFirstRunTutorial(), isFalse);
    expect(
      controller.state.firstRunTutorial,
      FirstRunTutorialStep.researchStarted,
    );
    now = epoch.add(const Duration(days: 10));
    await controller.resume();
    now = epoch.subtract(const Duration(days: 5));
    await controller.resume();
    expect(controller.state.simulatedMs, 0);
    expect(controller.state.moneyUnits, money);
    expect(controller.state.currentPlanFor('lab'), isNull);
    expect(controller.state.researchPointUnits, points);
    expect(controller.state.research, contains('life_support'));
    store.failure = null;
    final restarted = await start(store, now: () => now);
    expect(restarted.state.simulatedMs, 0);
    expect(restarted.state.moneyUnits, money);
    expect(restarted.state.researchPointUnits, points);
    expect(await restarted.continueFirstRunTutorial(), isTrue);
    expect(restarted.state.firstRunTutorial, FirstRunTutorialStep.completed);
    await restarted.resume();
    expect(restarted.state.simulatedMs, 0);
    now = now.add(const Duration(minutes: 1));
    await restarted.resume();
    expect(restarted.state.simulatedMs, 60000);
    expect(restarted.state.currentPlanFor('lab'), isNull);
    expect(
      restarted.state.researchPointUnits,
      points + restarted.state.researchPointUnitsPerMs * 60000,
    );
    expect(
      restarted.state.moneyUnits,
      money + restarted.state.netPerMinute * GameState.moneyScale,
    );
    final once = restarted.state.toJson();
    final sameTime = await start(store, now: () => now);
    expect(sameTime.state.toJson(), once);
  });

  test(
    'free-play controller catch-up is equal in one batch and across restarts',
    () async {
      final store = _TutorialRepository();
      final setup = await start(store);
      await startResearch(setup);
      await setup.continueFirstRunTutorial();
      final saved = _copy(store.data!);
      final bulkStore = _TutorialRepository()..data = _copy(saved);
      final splitStore = _TutorialRepository()..data = _copy(saved);
      final bulk = await start(
        bulkStore,
        now: () => epoch.add(const Duration(minutes: 10)),
      );
      GameController? split;
      for (var minute = 1; minute <= 10; minute++) {
        split?.dispose();
        final current = epoch.add(Duration(minutes: minute));
        split = GameController(splitStore, now: () => current);
        await split.initialize(startTimer: false);
      }
      addTearDown(split!.dispose);
      expect(split.state.toJson(), bulk.state.toJson());
      expect(split.state.research, contains('life_support'));
      expect(split.state.completionNotices, hasLength(2));
    },
  );

  test(
    'a conflict during help stops the world and never publishes its candidate',
    () async {
      final store = _TutorialRepository();
      final controller = await start(store);
      await placeHouse(controller);
      final paid = _copy(store.data!);
      store.failure = const SaveConflictException('別のタブで更新');
      expect(await controller.completeTutorialConstruction(), isFalse);
      expect(controller.engine, isNull);
      expect(controller.error, contains('競合'));
      expect(store.data, paid);
      final attempts = store.saveAttempts;
      await controller.completeTutorialConstruction();
      await controller.continueFirstRunTutorial();
      await controller.save();
      expect(store.saveAttempts, attempts);
    },
  );

  test('a broken saved construction reference stops before publishing or overwriting the world', () async {
    final store = _TutorialRepository();
    final original = await start(store);
    await placeHouse(original);
    store.data!['firstRunTutorialPlanId'] = 'missing-plan';
    final broken = _copy(store.data!);
    final attempts = store.saveAttempts;
    final restored = GameController(store, now: () => epoch);
    addTearDown(restored.dispose);
    await restored.initialize(startTimer: false);
    expect(restored.engine, isNull);
    expect(restored.error, contains('初回チュートリアルの建設予約が不正'));
    expect(store.saveAttempts, attempts);
    expect(store.data, broken);
  });
}

Map<String, dynamic> _copy(Map<String, dynamic> snapshot) =>
    jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;

class _TutorialRepository implements SaveRepository {
  Map<String, dynamic>? data;
  Object? failure;
  bool failAfterCommit = false;
  int saveAttempts = 0;
  Future<void> Function(Map<String, dynamic>)? beforeSave;

  @override
  Future<SaveLoadResult> load() async => SaveLoadResult(
    data: data == null ? null : _copy(data!),
    recovered: false,
    generation: data == null ? 0 : 1,
  );

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    saveAttempts++;
    final captured = _copy(snapshot);
    if (failure != null) throw failure!;
    await beforeSave?.call(captured);
    data = captured;
    if (failAfterCommit) throw StateError('write response interrupted');
  }
}
