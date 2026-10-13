import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 13);

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
      final saved = GameState.initial(epoch).toJson();
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
