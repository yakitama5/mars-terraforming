import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 15);
  GameEngine prepared() {
    final game = GameEngine(GameState.initial(epoch));
    game.state.moneyUnits = 100000 * GameState.moneyScale;
    game.enqueue('factory_contract', repeats: null);
    game.enqueue('life_support');
    return game;
  }

  test(
    'completion receipts agree across bulk, split and restart progression',
    () {
      final bulk = prepared()..advanceBy(const Duration(hours: 1));
      var split = prepared();
      for (var i = 0; i < 60; i++) {
        split.advanceBy(const Duration(minutes: 1));
        split = GameEngine(GameState.fromJson(split.state.toJson()));
      }
      expect(split.state.toJson(), bulk.state.toJson());
      expect(bulk.state.completionNotices, hasLength(2));
      final contracts = bulk.state.completionNotices.singleWhere(
        (n) => n.taskId == 'factory_contract',
      );
      expect(contracts.count, greaterThan(1));
      expect(bulk.state.unreadCompletionNotices, hasLength(2));
    },
  );

  test('read watermark persists and later repeats become unread without rewards on read', () {
    final game = prepared()..advanceBy(const Duration(minutes: 5));
    final money = game.state.moneyUnits;
    game.state.markCompletionsRead(game.state.nextCompletionNoticeId - 1);
    final restored = GameEngine(GameState.fromJson(game.state.toJson()));
    expect(restored.state.unreadCompletionNotices, isEmpty);
    expect(restored.state.moneyUnits, money);
    restored.advanceBy(const Duration(minutes: 2));
    expect(restored.state.unreadCompletionNotices, hasLength(1));
    expect(
      restored.state.unreadCompletionNotices.single.taskId,
      'factory_contract',
    );
  });

  test('acknowledging a visible snapshot keeps a concurrently completed run unread', () {
    final game = prepared()..advanceBy(const Duration(seconds: 179));
    final visibleLastId = game.state.nextCompletionNoticeId - 1;
    game.advanceBy(const Duration(seconds: 1));
    game.state.markCompletionsRead(visibleLastId);
    expect(game.state.unreadCompletionNotices, hasLength(1));
    expect(
      game.state.unreadCompletionNotices.single.taskId,
      'factory_contract',
    );
    expect(
      game.state.unreadCompletionNotices.single.id,
      greaterThan(visibleLastId),
    );
    final saved = GameState.fromJson(game.state.toJson());
    expect(saved.unreadCompletionNotices, hasLength(1));
  });

  test(
    'clock rollback and repeated resume do not replay completion receipts',
    () {
      final game = prepared()..advanceTo(epoch.add(const Duration(minutes: 5)));
      final notices = game.state.completionNotices
          .map((n) => n.toJson())
          .toList();
      game.advanceTo(epoch);
      game.advanceTo(epoch);
      final restored = GameEngine(GameState.fromJson(game.state.toJson()))
        ..advanceTo(epoch);
      expect(
        restored.state.completionNotices.map((n) => n.toJson()).toList(),
        notices,
      );
    },
  );

  test(
    'legacy saves do not turn existing completions into new notifications',
    () {
      final game = prepared()..advanceBy(const Duration(minutes: 5));
      final json = game.state.toJson()
        ..remove('completionNotices')
        ..remove('nextCompletionNoticeId')
        ..remove('readCompletionNoticeId')
        ..remove('guidancePreferences');
      final restored = GameEngine(GameState.fromJson(json));
      expect(restored.state.completionNotices, isEmpty);
      expect(restored.state.research, contains('life_support'));
      expect(restored.state.tipsEnabled, isTrue);
    },
  );

  test('completion history is bounded and malformed watermark is rejected', () {
    final game = prepared();
    for (var i = 0; i < 100; i++) {
      game.advanceBy(const Duration(minutes: 2));
      game.state.markCompletionsRead(game.state.nextCompletionNoticeId - 1);
    }
    expect(game.state.completionNotices.length, GameState.maxCompletionNotices);
    expect(() => GameState.fromJson(game.state.toJson()), returnsNormally);
    final invalid = game.state.toJson()
      ..['readCompletionNoticeId'] = game.state.nextCompletionNoticeId;
    expect(() => GameState.fromJson(invalid), throwsFormatException);
  });
}
