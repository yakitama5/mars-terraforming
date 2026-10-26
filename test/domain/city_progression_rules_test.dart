import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 26);
  GameState copy(GameState state) => GameState.fromJson(
    jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
  );
  GameState fresh() => GameState.initial(epoch)
    ..firstRunTutorial = FirstRunTutorialStep.completed
    ..openingSeen = true;
  void positiveBudget(GameState state) {
    for (final id in state.facilities.keys) {
      state.facilities[id] = id == 'lab';
    }
  }

  test(
    'reserve capacities use actual Earth and Mars population with base space',
    () {
      final state = fresh()
        ..population = 300
        ..marsResidents = 48;
      expect(state.totalPopulation, 348);
      expect(
        state.moneyCapacity,
        GameContent.moneyBaseCapacity +
            348 * GameContent.moneyCapacityPerResident,
      );
      expect(
        state.researchPointCapacity,
        GameContent.researchPointBaseCapacity +
            348 * GameContent.researchPointCapacityPerResident,
      );
      state.population = 0;
      state.marsResidents = 0;
      expect(state.moneyCapacity, GameContent.moneyBaseCapacity);
      expect(
        state.researchPointCapacity,
        GameContent.researchPointBaseCapacity,
      );
    },
  );

  test('long idle reaches both caps without selecting investments', () {
    final state = fresh();
    positiveBudget(state);
    final game = GameEngine(state);
    game.advanceBy(const Duration(days: 100));
    expect(state.money, state.moneyCapacity);
    expect(state.researchPoints, state.researchPointCapacity);
    expect(state.isMoneyAtCapacity, isTrue);
    expect(state.isResearchAtCapacity, isTrue);
    expect(state.researchPointsPerHour, greaterThan(0));
    expect(state.research, isEmpty);
    expect(state.plans, isEmpty);
  });

  test(
    'cap clipping matches irregular partitions including repeated reload',
    () {
      final state = fresh();
      positiveBudget(state);
      state.moneyUnits = state.moneyCapacity * GameState.moneyScale - 7;
      state.researchPointUnits =
          state.researchPointCapacity * GameState.researchPointScale - 19;
      final one = GameEngine(state);
      var split = GameEngine(copy(state));
      one.advanceBy(const Duration(days: 3));
      var remaining = const Duration(days: 3).inMilliseconds;
      while (remaining > 0) {
        final step = remaining.clamp(0, 719999);
        split.advanceBy(Duration(milliseconds: step));
        split = GameEngine(copy(split.state));
        remaining -= step;
      }
      expect(split.state.toJson(), one.state.toJson());
    },
  );

  test(
    'population decrease and old excess balances are preserved without growth',
    () {
      final state = fresh()..population = 1000;
      positiveBudget(state);
      state.money = state.moneyCapacity;
      state.researchPointUnits =
          state.researchPointCapacity * GameState.researchPointScale;
      state.population = 120;
      final oldMoney = state.moneyUnits;
      final oldPoints = state.researchPointUnits;
      final json = state.toJson()..['contentVersion'] = 'district-10';
      final restored = GameEngine(GameState.fromJson(json));
      restored.advanceBy(const Duration(days: 7));
      expect(restored.state.moneyUnits, oldMoney);
      expect(restored.state.researchPointUnits, oldPoints);
      expect(restored.state.isMoneyAtCapacity, isTrue);
      expect(restored.state.isResearchAtCapacity, isTrue);
      expect(() => copy(restored.state), returnsNormally);
    },
  );

  test(
    'maintenance continues to consume balances above the population cap',
    () {
      final state = fresh();
      state.money = state.moneyCapacity + 500;
      final game = GameEngine(state);
      expect(state.netPerMinute, lessThan(0));
      final before = state.moneyUnits;
      final net = state.netPerMinute;
      game.advanceBy(const Duration(minutes: 1));
      expect(state.moneyUnits, before + net * 60000);
    },
  );

  test(
    'spending below capacity resumes accumulation without a collection step',
    () {
      final state = fresh();
      positiveBudget(state);
      state.money = state.moneyCapacity;
      state.researchPointUnits =
          state.researchPointCapacity * GameState.researchPointScale;
      final game = GameEngine(state);
      expect(game.unlockResearch('life_support'), isNull);
      final after = state.researchPointUnits;
      game.advanceBy(const Duration(seconds: 1));
      expect(state.researchPointUnits, greaterThan(after));
      state.moneyUnits -= 100 * GameState.moneyScale;
      final spent = state.moneyUnits;
      game.advanceBy(const Duration(seconds: 1));
      expect(state.moneyUnits, greaterThan(spent));
    },
  );

  test('rejected construction changes no state when funds or factory time are missing', () {
    final state = fresh()..money = 10000;
    final game = GameEngine(state);
    expect(game.enqueue('factory_contract'), isNull);
    final before = state.toJson();
    expect(game.enqueueDistrict('earth_delta', 0, 'housing'), contains('作業中'));
    expect(state.toJson(), before);
    game.advanceBy(
      Duration(milliseconds: state.currentPlanFor('factory')!.remainingMs),
    );
    state.money = 0;
    final broke = state.toJson();
    expect(game.enqueueDistrict('earth_delta', 0, 'housing'), contains('資金不足'));
    expect(state.toJson(), broke);
  });

  test(
    'construction starts immediately and cannot create follow-up reservations',
    () {
      final state = fresh()..money = 10000;
      final game = GameEngine(state);
      expect(game.enqueueDistrict('earth_delta', 0, 'housing'), isNull);
      final construction = state.currentPlanFor('factory')!;
      expect(construction.requiresManualStart, isFalse);
      expect(construction.status, 'running');
      final before = state.toJson();
      expect(game.enqueueDistrict('earth_delta', 1, 'housing'), isNotNull);
      expect(state.toJson(), before);
      final restored = GameEngine(copy(state));
      restored.advanceBy(Duration(milliseconds: construction.remainingMs));
      expect(restored.state.districtAt('earth_delta', 0), isNotNull);
      expect(restored.state.districtAt('earth_delta', 1), isNull);
      expect(restored.state.population, state.population + 60);
    },
  );

  test('unpaid legacy construction waits for explicit start and does not block contracts', () {
    final state = fresh()..money = 10000;
    final waiting = PlannedTask(
      id: 'plan-1',
      taskId: GameContent.districts['housing']!.taskId(),
      cityId: 'earth_delta',
      plotIndex: 0,
      targetLevel: 1,
    );
    state.plans.add(waiting);
    state.nextPlanId = 2;
    final json = state.toJson()..['contentVersion'] = 'district-10';
    final game = GameEngine(GameState.fromJson(json));
    final retained = game.state.plans.single;
    expect(retained.requiresManualStart, isTrue);
    expect(game.enqueue('factory_contract'), isNull);
    game.advanceBy(const Duration(hours: 1));
    expect(retained.status, 'queued');
    expect(retained.completedRuns, 0);
    expect(game.state.districtAt('earth_delta', 0), isNull);
    expect(game.startPlan(retained.id), isNull);
    final paid = game.state.moneyUnits;
    expect(retained.status, 'running');
    expect(game.startPlan(retained.id), isNotNull);
    expect(game.state.moneyUnits, paid);
    game.advanceBy(Duration(milliseconds: retained.remainingMs));
    expect(retained.completedRuns, 1);
    expect(game.state.districtAt('earth_delta', 0), isNotNull);
  });

  test('legacy RP reservation never auto-unlocks and spends once on explicit start', () {
    final state = fresh();
    positiveBudget(state);
    state.researchPointUnits = 0;
    state.plans.add(PlannedTask(id: 'plan-1', taskId: 'life_support'));
    state.nextPlanId = 2;
    final game = GameEngine(copy(state));
    game.advanceBy(const Duration(days: 1));
    expect(game.state.research, isEmpty);
    expect(game.state.plans.single.requiresManualStart, isTrue);
    final points = game.state.researchPointUnits;
    expect(game.startPlan('plan-1'), isNull);
    expect(game.state.research, contains('life_support'));
    expect(
      game.state.researchPointUnits,
      points -
          GameContent.researchPointCost('life_support') *
              GameState.researchPointScale,
    );
    final after = game.state.toJson();
    final restored = GameEngine(copy(game.state));
    expect(restored.state.toJson(), after);
    expect(restored.startPlan('plan-1'), isNotNull);
  });

  test(
    'same clock and clock rollback do not bypass limits or replay completions',
    () {
      final state = fresh();
      positiveBudget(state);
      final game = GameEngine(state);
      final later = epoch.add(const Duration(days: 10));
      game.advanceTo(later);
      final before = state.toJson();
      game.advanceTo(later);
      expect(state.toJson(), before);
      game.advanceTo(epoch);
      expect(state.money, state.moneyCapacity);
      expect(state.researchPoints, state.researchPointCapacity);
      game.advanceTo(epoch.add(const Duration(hours: 1)));
      expect(state.money, state.moneyCapacity);
      expect(state.researchPoints, state.researchPointCapacity);
      expect(state.plans, isEmpty);
    },
  );

  test('contract payouts and one-time support respect money capacity', () {
    final state = fresh();
    state.money = state.moneyCapacity;
    final game = GameEngine(state);
    expect(game.enqueue('factory_contract'), isNull);
    final contract = state.plans.single;
    game.advanceBy(Duration(milliseconds: contract.remainingMs));
    expect(state.money, state.moneyCapacity);
    expect(
      state.contractRevenue,
      GameContent.tasks['factory_contract']!.reward,
    );
    expect(state.log.last, contains('保有上限'));
    expect(state.log.last, isNot(contains('（+220ドル）')));
    state.research.addAll(['urban_planning', 'life_support']);
    for (final (plot, id) in [(0, 'housing'), (8, 'industry')]) {
      final district = DistrictState(
        cityId: 'earth_delta',
        plotIndex: plot,
        districtId: id,
      );
      state.districts[district.key] = district;
    }
    final balance = state.moneyUnits;
    expect(game.choosePartnership('research_exchange', 'funding'), isNull);
    expect(state.moneyUnits, balance);
    expect(state.log.last, contains('保有上限のため蓄積なし'));
    expect(
      state.claimedRewards,
      contains('${state.worldId}:partnership:research_exchange'),
    );
    final restored = GameEngine(copy(state));
    expect(
      restored.choosePartnership('research_exchange', 'funding'),
      isNotNull,
    );
    expect(restored.state.moneyUnits, balance);
  });

  test('a capped geological survey still records its one-time result', () {
    final state = fresh()..money = 10000;
    state.research.add('local_resources');
    final game = GameEngine(state);
    expect(
      game.enqueueDevelopment('local_resources', cityId: 'earth_delta'),
      isNull,
    );
    game.advanceBy(Duration(milliseconds: state.plans.last.remainingMs));
    expect(game.setDevelopmentEnabled('local_resources', true), isNull);
    state.researchPointUnits =
        state.researchPointCapacity * GameState.researchPointScale;
    expect(
      game.enqueueBuildingWork(
        'local_resources',
        'building_survey',
        targetPlotIndex: 0,
      ),
      isNull,
    );
    final survey = state.plans.last;
    game.advanceBy(Duration(milliseconds: survey.remainingMs));
    expect(state.researchPoints, state.researchPointCapacity);
    expect(state.isSiteSurveyed('earth_delta', 0), isTrue);
    expect(state.log.any((entry) => entry.contains('RP報酬は保有上限まで')), isTrue);
    expect(state.log.any((entry) => entry.contains('区画調査の成果：+')), isFalse);
    final restored = GameEngine(copy(state));
    expect(
      restored.enqueueBuildingWork(
        'local_resources',
        'building_survey',
        targetPlotIndex: 0,
      ),
      contains('完了'),
    );
    expect(restored.state.researchPointUnits, state.researchPointUnits);
    expect(restored.state.surveyedSites, state.surveyedSites);
  });

  test(
    'partially received support never advertises the nominal full amount',
    () {
      final state = fresh();
      state.research.addAll(['urban_planning', 'life_support']);
      for (final (plot, id) in [(0, 'housing'), (8, 'industry')]) {
        final district = DistrictState(
          cityId: 'earth_delta',
          plotIndex: plot,
          districtId: id,
        );
        state.districts[district.key] = district;
      }
      state.money = state.moneyCapacity - 100;
      final game = GameEngine(state);
      expect(game.choosePartnership('research_exchange', 'funding'), isNull);
      expect(state.money, state.moneyCapacity);
      expect(state.log.last, contains('保有上限まで加算'));
      expect(state.log.last, isNot(contains('（+1200ドル）')));
    },
  );

  test('cancelling a legacy manual investment persists a terminal state', () {
    final state = fresh();
    state.plans.add(PlannedTask(id: 'plan-1', taskId: 'life_support'));
    state.nextPlanId = 2;
    final game = GameEngine(copy(state));
    expect(game.state.plans.single.requiresManualStart, isTrue);
    final money = game.state.moneyUnits;
    final points = game.state.researchPointUnits;
    expect(game.cancelQueued('plan-1'), isNull);
    expect(game.state.plans.single.status, 'cancelled');
    expect(game.state.plans.single.requiresManualStart, isFalse);
    expect(game.state.moneyUnits, money);
    expect(game.state.researchPointUnits, points);
    final restored = GameEngine(copy(game.state));
    expect(restored.state.toJson(), game.state.toJson());
    expect(restored.state.research, isEmpty);
  });
}
