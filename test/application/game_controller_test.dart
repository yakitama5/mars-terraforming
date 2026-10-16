import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 13);

  test(
    'development advancement persists without changing the device clock anchor',
    () async {
      final store = _Repository();
      var now = epoch;
      final controller = GameController(store, now: () => now, devTools: true);
      await controller.initialize(startTimer: false);
      controller.state.firstRunTutorial = FirstRunTutorialStep.completed;
      await controller.advanceForDevelopment(duration: const Duration(days: 1));
      expect(
        controller.state.simulatedMs,
        const Duration(days: 1).inMilliseconds,
      );
      expect(controller.state.lastWallClockMs, epoch.millisecondsSinceEpoch);
      expect(controller.notice, contains('1日'));
      expect(store.data, controller.state.toJson());
      final money = controller.state.moneyUnits;
      controller.dispose();
      final resumed = GameController(store, now: () => now, devTools: true);
      addTearDown(resumed.dispose);
      await resumed.initialize(startTimer: false);
      expect(resumed.state.moneyUnits, money);
      expect(resumed.state.simulatedMs, const Duration(days: 1).inMilliseconds);
      now = epoch.add(const Duration(minutes: 1));
      await resumed.resume();
      expect(
        resumed.state.simulatedMs,
        const Duration(days: 1, minutes: 1).inMilliseconds,
      );
    },
  );

  test(
    'normal mode and nonpositive development steps never skip time or save',
    () async {
      for (final development in [false, true]) {
        final store = _Repository();
        final controller = GameController(
          store,
          now: () => epoch,
          devTools: development,
        );
        addTearDown(controller.dispose);
        await controller.initialize(startTimer: false);
        final before = controller.state.toJson();
        if (!development) {
          await controller.advanceForDevelopment(
            duration: const Duration(days: 1),
          );
        }
        await controller.advanceForDevelopment(duration: Duration.zero);
        await controller.advanceForDevelopment(
          duration: const Duration(minutes: -5),
        );
        expect(controller.state.toJson(), before);
        expect(store.saveAttempts, 1);
      }
    },
  );

  testWidgets(
    'command notices expire once without saving or replacing the final notice',
    (tester) async {
      final store = _Repository();
      final controller = GameController(store, now: () => epoch);
      try {
        await controller.initialize(startTimer: false);
        expect(controller.commandNotice, isNull);
        var notifications = 0;
        controller.addListener(() => notifications++);
        await controller.command((_) => '資金が不足しています');
        expect(controller.commandNotice, '資金が不足しています');
        expect(controller.notice, '資金が不足しています');
        final commandNotifications = notifications;
        final saved = _copy(store.data!);
        final saveAttempts = store.saveAttempts;

        await tester.pump(const Duration(seconds: 7));
        expect(controller.commandNotice, '資金が不足しています');
        expect(notifications, commandNotifications);
        await tester.pump(const Duration(seconds: 1));
        expect(controller.commandNotice, isNull);
        expect(controller.notice, '資金が不足しています');
        expect(notifications, commandNotifications + 1);
        await tester.pump(const Duration(minutes: 1));
        expect(notifications, commandNotifications + 1);
        expect(store.saveAttempts, saveAttempts);
        expect(store.data, saved);
      } finally {
        controller.dispose();
      }
    },
  );

  testWidgets('repeating the same command notice restarts its full duration', (
    tester,
  ) async {
    final controller = GameController(_Repository(), now: () => epoch);
    try {
      await controller.initialize(startTimer: false);
      await controller.command((_) => '予約が上限に達しています');
      await tester.pump(const Duration(seconds: 6));
      await controller.command((_) => '予約が上限に達しています');
      await tester.pump(const Duration(seconds: 2));
      expect(controller.commandNotice, '予約が上限に達しています');
      await tester.pump(const Duration(milliseconds: 5999));
      expect(controller.commandNotice, '予約が上限に達しています');
      await tester.pump(const Duration(milliseconds: 1));
      expect(controller.commandNotice, isNull);
    } finally {
      controller.dispose();
    }
  });

  testWidgets(
    'a newer message replaces the old timer and a silent command does not extend it',
    (tester) async {
      final controller = GameController(_Repository(), now: () => epoch);
      try {
        await controller.initialize(startTimer: false);
        await controller.command((_) => '最初の操作結果');
        await tester.pump(const Duration(seconds: 6));
        await controller.command((_) => '次の操作結果');
        await tester.pump(const Duration(seconds: 2));
        expect(controller.commandNotice, '次の操作結果');
        await controller.command((_) => null);
        expect(controller.commandNotice, '次の操作結果');
        await tester.pump(const Duration(seconds: 6));
        expect(controller.commandNotice, isNull);
        expect(controller.notice, '次の操作結果');
      } finally {
        controller.dispose();
      }
    },
  );

  testWidgets(
    'a command result is visible during saving and disposal cancels its timer',
    (tester) async {
      final store = _Repository();
      final controller = GameController(store, now: () => epoch);
      final committing = Completer<void>();
      var disposed = false;
      Future<void>? pending;
      try {
        await controller.initialize(startTimer: false);
        final observed = <String?>[];
        controller.addListener(() => observed.add(controller.commandNotice));
        store.beforeSave = (_) => committing.future;
        pending = controller.command((_) => '設備の再開には資金が必要です');
        await tester.pump();
        expect(controller.busy, isTrue);
        expect(observed, ['設備の再開には資金が必要です']);
        expect(controller.commandNotice, '設備の再開には資金が必要です');

        controller.dispose();
        disposed = true;
        await tester.pump(const Duration(seconds: 9));
        // The cancelled callback must neither clear the result nor notify.
        expect(controller.commandNotice, '設備の再開には資金が必要です');
        expect(observed, ['設備の再開には資金が必要です']);
        committing.complete();
        await pending;
        var commandRan = false;
        await controller.command((_) {
          commandRan = true;
          return '破棄後の操作';
        });
        expect(commandRan, isFalse);
        expect(store.saveAttempts, 2);
        expect(observed, ['設備の再開には資金が必要です']);
        expect(tester.takeException(), isNull);
      } finally {
        if (!committing.isCompleted) committing.complete();
        await pending;
        if (!disposed) controller.dispose();
      }
    },
  );

  testWidgets(
    'failed first save cannot expose a playable world or start the clock',
    (tester) async {
      final store = _Repository()..saveFailure = StateError('quota exceeded');
      var now = epoch;
      final controller = GameController(store, now: () => now, devTools: true);
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.engine, isNull);
      expect(controller.error, contains('開始せずに停止'));
      expect(controller.error, contains('quota exceeded'));
      expect(store.data, isNull);
      expect(store.saveAttempts, 1);
      now = epoch.add(const Duration(minutes: 10));
      await tester.pump(const Duration(seconds: 10));
      await controller.advanceForDevelopment();
      await controller.resume();
      expect(controller.engine, isNull);
      expect(store.saveAttempts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'failed initial catch-up save leaves the previous saved world intact',
    () async {
      final saved = (GameState.initial(
        epoch,
      )..firstRunTutorial = FirstRunTutorialStep.completed).toJson();
      final store = _Repository()
        ..data = _copy(saved)
        ..saveFailure = StateError('storage unavailable');
      final controller = GameController(
        store,
        now: () => epoch.add(const Duration(minutes: 10)),
      );
      addTearDown(controller.dispose);
      await controller.initialize(startTimer: false);
      expect(controller.engine, isNull);
      expect(store.data, saved);
      expect(controller.error, contains('開始せずに停止'));
    },
  );

  test(
    'the world becomes playable only after the initial commit completes',
    () async {
      final committing = Completer<void>();
      final store = _Repository()..beforeSave = (_) => committing.future;
      final controller = GameController(store, now: () => epoch);
      addTearDown(controller.dispose);
      final initializing = controller.initialize(startTimer: false);
      await Future<void>.delayed(Duration.zero);
      expect(store.saveAttempts, 1);
      expect(controller.engine, isNull);
      committing.complete();
      await initializing;
      expect(controller.engine, isNotNull);
      expect(store.data, controller.state.toJson());
      expect(controller.error, isNull);
    },
  );

  testWidgets(
    'a save conflict stops the timer, commands, resume and queued writes',
    (tester) async {
      final store = _Repository();
      var now = epoch;
      final controller = GameController(store, now: () => now, devTools: true);
      addTearDown(controller.dispose);
      await controller.initialize();
      final saved = _copy(store.data!);
      final conflicting = Completer<void>();
      store.beforeSave = (_) => conflicting.future;
      final first = controller.save();
      final queued = controller.save();
      // Let the first write reach the repository before injecting contention.
      await tester.pump();
      expect(store.saveAttempts, 2);
      conflicting.completeError(const SaveConflictException('別のタブで保存が更新されました'));
      await Future.wait([first, queued]);
      expect(controller.engine, isNull);
      expect(controller.error, contains('競合'));
      expect(store.data, saved);
      expect(store.saveAttempts, 2);
      var commandRan = false;
      await controller.command((game) {
        commandRan = true;
        return null;
      });
      now = epoch.add(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 10));
      await controller.resume();
      await controller.advanceForDevelopment();
      await controller.save();
      expect(commandRan, isFalse);
      expect(store.saveAttempts, 2);
      expect(controller.error, contains('競合'));
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'ordinary storage failures show an error and a later save can recover',
    () async {
      final store = _Repository();
      final controller = GameController(store, now: () => epoch);
      addTearDown(controller.dispose);
      await controller.initialize(startTimer: false);
      store.saveFailure = StateError('quota exceeded');
      await controller.command((game) => game.enqueue('factory_contract'));
      expect(controller.engine, isNotNull);
      expect(controller.state.plans, hasLength(1));
      expect(controller.error, contains('自動保存に失敗'));
      expect((store.data!['plans'] as List), isEmpty);
      store.saveFailure = null;
      await controller.save();
      expect(controller.error, isNull);
      expect(store.data, controller.state.toJson());
    },
  );

  test(
    'a second-tab load conflict never attempts a save or constructs a world',
    () async {
      final store = _Repository()
        ..loadFailure = const SaveConflictException('この保存枠は別のタブで使用中です');
      final controller = GameController(store, now: () => epoch);
      addTearDown(controller.dispose);
      await controller.initialize(startTimer: false);
      expect(controller.engine, isNull);
      expect(controller.error, contains('別のタブ'));
      expect(store.saveAttempts, 0);
    },
  );
}

Map<String, dynamic> _copy(Map<String, dynamic> snapshot) =>
    jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;

class _Repository implements SaveRepository {
  Map<String, dynamic>? data;
  Object? saveFailure;
  Object? loadFailure;
  int saveAttempts = 0;
  Future<void> Function(Map<String, dynamic>)? beforeSave;

  @override
  Future<SaveLoadResult> load() async {
    if (loadFailure != null) throw loadFailure!;
    return SaveLoadResult(
      data: data == null ? null : _copy(data!),
      recovered: false,
      generation: data == null ? 0 : 1,
    );
  }

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    saveAttempts++;
    final captured = _copy(snapshot);
    if (saveFailure != null) throw saveFailure!;
    await beforeSave?.call(captured);
    data = captured;
  }
}
