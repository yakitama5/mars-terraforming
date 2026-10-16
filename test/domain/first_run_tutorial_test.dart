import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 16);

  GameEngine copy(GameEngine game) => GameEngine(
    GameState.fromJson(
      jsonDecode(jsonEncode(game.state.toJson())) as Map<String, dynamic>,
    ),
  );

  test('only new worlds require the hands-on tutorial', () {
    final state = GameState.initial(epoch);
    expect(state.firstRunTutorial, FirstRunTutorialStep.placeHousing);
    expect(state.introductionPausesClock, isTrue);
    final legacy = state.toJson()
      ..remove('firstRunTutorial')
      ..remove('firstRunTutorialPlanId')
      ..['openingSeen'] = true;
    final restored = GameState.fromJson(legacy);
    expect(restored.firstRunTutorial, FirstRunTutorialStep.completed);
    expect(restored.introductionPausesClock, isFalse);
    expect(restored.worldId, state.worldId);
    expect(restored.moneyUnits, state.moneyUnits);
    expect(restored.claimedRewards, state.claimedRewards);
    for (final name in [
      'prototype_v1',
      'district_v2',
      'district_v3',
      'district_v4',
    ]) {
      final snapshot = jsonDecode(
        File('test/fixtures/$name.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final migrated = GameState.fromJson(snapshot);
      expect(migrated.firstRunTutorial, FirstRunTutorialStep.completed);
      expect(migrated.claimedRewards, snapshot['claimedRewards']);
      expect(migrated.worldId, snapshot['worldId']);
    }
  });

  test(
    'a saved unknown tutorial phase is rejected instead of resetting it',
    () {
      final saved = GameState.initial(epoch).toJson()
        ..['firstRunTutorial'] = 'futureStep';
      expect(() => GameState.fromJson(saved), throwsFormatException);
    },
  );

  test('invalid construction references stop loading while valid pending phases survive', () {
    final game = GameEngine(GameState.initial(epoch));
    game.enqueueDistrict('earth_delta', 0, 'housing');
    final saved = game.state.toJson();
    for (final id in [null, '', 'missing-plan']) {
      final invalid = Map<String, dynamic>.of(saved)
        ..['firstRunTutorialPlanId'] = id;
      expect(() => GameState.fromJson(invalid), throwsFormatException);
    }
    game.enqueue('life_support');
    final unrelated = game.state.toJson()
      ..['firstRunTutorialPlanId'] = game.state.currentPlanFor('lab')!.id;
    expect(() => GameState.fromJson(unrelated), throwsFormatException);
    expect(
      copy(game).state.firstRunTutorial,
      FirstRunTutorialStep.finishConstruction,
    );
    final queued = GameEngine(GameState.initial(epoch));
    queued.state.facilities['factory'] = false;
    queued.enqueueDistrict('earth_delta', 0, 'housing');
    expect(copy(queued).state.plans.single.status, 'queued');
    game.advanceBy(const Duration(minutes: 5));
    expect(copy(game).state.firstRunTutorial, FirstRunTutorialStep.income);
    final finishedReference = game.state.toJson()
      ..['firstRunTutorial'] = 'finishConstruction';
    expect(() => GameState.fromJson(finishedReference), throwsFormatException);
  });

  test('construction help uses the paid completion once without advancing anything else', () {
    final game = GameEngine(GameState.initial(epoch)..money = 10000);
    expect(game.enqueue('life_support'), isNull);
    expect(game.enqueue('launch_contract', repeats: 3), isNull);
    final price = game.state.districtPreview('earth_delta', 0, 'housing').cost;
    final beforeCost = game.state.moneyUnits;
    final beforePopulation = game.state.population;
    final beforeTax = game.state.taxPerMinute;
    expect(game.enqueueDistrict('earth_delta', 0, 'housing'), isNull);
    expect(game.state.moneyUnits, beforeCost - price * GameState.moneyScale);
    expect(
      game.state.firstRunTutorial,
      FirstRunTutorialStep.finishConstruction,
    );
    final otherPlans = game.state.plans
        .where((plan) => plan.id != game.state.firstRunTutorialPlanId)
        .map((plan) => plan.toJson())
        .toList();
    final money = game.state.moneyUnits;
    final elapsed = game.state.simulatedMs;
    final anchor = game.state.lastWallClockMs;
    expect(game.completeTutorialConstruction(), isNull);
    expect(game.state.firstRunTutorial, FirstRunTutorialStep.income);
    expect(game.state.moneyUnits, money);
    expect(game.state.simulatedMs, elapsed);
    expect(game.state.lastWallClockMs, anchor);
    expect(game.state.population, beforePopulation + 60);
    expect(game.state.taxPerMinute, beforeTax + 16);
    expect(game.state.districtAt('earth_delta', 0)?.level, 1);
    expect(game.state.completionNotices, hasLength(1));
    expect(game.state.completionNotices.single.simulatedMs, elapsed);
    expect(game.state.research, isEmpty);
    expect(game.state.claimedRewards, isEmpty);
    expect(
      game.state.plans
          .where((plan) => plan.id != game.state.firstRunTutorialPlanId)
          .map((plan) => plan.toJson())
          .toList(),
      otherPlans,
    );
    final restarted = copy(game);
    final completed = restarted.state.toJson();
    expect(restarted.completeTutorialConstruction(), isNotNull);
    expect(restarted.state.toJson(), completed);
  });

  test('help cannot finish an unpaid queued house or an unrelated plan', () {
    final game = GameEngine(GameState.initial(epoch)..money = 10000);
    game.state.facilities['factory'] = false;
    expect(game.enqueueDistrict('earth_delta', 0, 'housing'), isNull);
    expect(game.state.plans.single.status, 'queued');
    final queued = game.state.toJson();
    expect(game.completeTutorialConstruction(), isNotNull);
    expect(game.state.toJson(), queued);
    expect(game.cancelQueued(game.state.firstRunTutorialPlanId!), isNull);
    expect(game.state.firstRunTutorial, FirstRunTutorialStep.placeHousing);
    expect(game.state.firstRunTutorialPlanId, isNull);
    expect(game.enqueue('life_support'), isNull);
    game.state.firstRunTutorial = FirstRunTutorialStep.finishConstruction;
    game.state.firstRunTutorialPlanId = game.state.plans.last.id;
    final unrelated = game.state.toJson();
    expect(game.completeTutorialConstruction(), isNotNull);
    expect(game.state.toJson(), unrelated);
  });

  test('old worlds and later houses cannot receive tutorial help', () {
    final state = GameState.initial(epoch)
      ..firstRunTutorial = FirstRunTutorialStep.completed
      ..money = 10000;
    final game = GameEngine(state);
    expect(game.enqueueDistrict('earth_delta', 0, 'housing'), isNull);
    final before = state.toJson();
    expect(game.completeTutorialConstruction(), isNotNull);
    expect(state.toJson(), before);
    expect(state.firstRunTutorialPlanId, isNull);
  });

  test(
    'each persisted step resumes and research keeps its normal paid duration',
    () {
      var game = GameEngine(GameState.initial(epoch));
      expect(game.continueFirstRunTutorial(), isNotNull);
      game.enqueueDistrict('earth_delta', 0, 'housing');
      game = copy(game);
      expect(
        game.state.firstRunTutorial,
        FirstRunTutorialStep.finishConstruction,
      );
      game.completeTutorialConstruction();
      game = copy(game);
      expect(game.state.firstRunTutorial, FirstRunTutorialStep.income);
      final money = game.state.moneyUnits;
      expect(game.continueFirstRunTutorial(), isNull);
      expect(game.state.moneyUnits, money);
      game = copy(game);
      expect(game.state.firstRunTutorial, FirstRunTutorialStep.startResearch);
      expect(game.continueFirstRunTutorial(), isNotNull);
      expect(game.enqueue('life_support'), isNull);
      game = copy(game);
      expect(game.state.firstRunTutorial, FirstRunTutorialStep.researchStarted);
      final research = game.state.currentPlanFor('lab')!;
      expect(
        research.remainingMs,
        GameContent.tasks['life_support']!.durationMs,
      );
      expect(game.state.research, isEmpty);
      expect(game.state.moneyUnits, money - 180 * GameState.moneyScale);
      expect(game.continueFirstRunTutorial(), isNull);
      game = copy(game);
      expect(game.state.firstRunTutorial, FirstRunTutorialStep.completed);
      expect(game.state.simulatedMs, 0);
      expect(game.state.currentPlanFor('lab')!.remainingMs, 120000);
      final finished = game.state.toJson();
      expect(game.continueFirstRunTutorial(), isNotNull);
      expect(game.state.toJson(), finished);
    },
  );

  test(
    'a normally completed first house cannot receive the help a second time',
    () {
      final game = GameEngine(GameState.initial(epoch));
      game.enqueueDistrict('earth_delta', 0, 'housing');
      final house = game.state.currentPlanFor('factory')!;
      game.advanceBy(Duration(milliseconds: house.remainingMs));
      expect(game.state.firstRunTutorial, FirstRunTutorialStep.income);
      final before = game.state.toJson();
      expect(game.completeTutorialConstruction(), isNotNull);
      expect(game.state.toJson(), before);
    },
  );

  test(
    'free play after help is identical for bulk, split and restarted time',
    () {
      final game = GameEngine(GameState.initial(epoch));
      game.enqueueDistrict('earth_delta', 0, 'housing');
      game.completeTutorialConstruction();
      game.continueFirstRunTutorial();
      game.enqueue('life_support');
      game.continueFirstRunTutorial();
      game.enqueue('factory_contract', repeats: 3);
      final bulk = copy(game);
      var split = copy(game);
      bulk.advanceBy(const Duration(minutes: 10));
      for (var index = 0; index < 20; index++) {
        split.advanceBy(const Duration(seconds: 30));
        split = copy(split);
      }
      expect(split.state.toJson(), bulk.state.toJson());
      expect(bulk.state.research, contains('life_support'));
      expect(bulk.state.districts, hasLength(1));
    },
  );
}
