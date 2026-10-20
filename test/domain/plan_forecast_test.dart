import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/plan_forecast.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 13);
  GameEngine ready() => GameEngine(GameState.initial(epoch)..money = 1000000);
  GameState clone(GameState state) => GameState.fromJson(
    jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
  );
  ForecastFacility facility(PlanForecast result, String id) =>
      result.facilities.singleWhere((item) => item.facilityId == id);

  test('a forecast never alters the world, clock, reservations or rewards', () {
    final game = GameEngine(GameState.initial(epoch));
    game.enqueue('factory_contract', repeats: 3);
    final before = jsonEncode(game.state.toJson());
    final result = forecastPlans(game.state, const Duration(minutes: 30));
    expect(jsonEncode(game.state.toJson()), before);
    expect(game.state.lastWallClockMs, epoch.millisecondsSinceEpoch);
    expect(result.completedRuns, 3);
    expect(result.completions.single.taskId, 'factory_contract');
    expect(
      result.money,
      1080,
    ); // Three 180 Cr margins, minus 30 minutes upkeep.
    expect(result.moneyDelta, 220); // First 40 Cr had already been paid.
    expect(result.completedResearch, isEmpty);
    expect(result.districtDelta, 0);
    expect(facility(result, 'factory').status, ForecastFacilityStatus.idle);
    expect(facility(result, 'factory').stopReason, '予約した作業が完了');
    expect(facility(result, 'factory').completedRuns, 3);
    expect(facility(result, 'factory').queuedPlans, 0);
  });

  test('an empty queue never researches, builds, selects branches or resumes equipment', () {
    final game = GameEngine(GameState.initial(epoch));
    final result = forecastPlans(game.state, const Duration(hours: 8));
    expect(result.completedRuns, 0);
    expect(result.completedResearch, isEmpty);
    expect(result.newAchievements, isEmpty);
    expect(result.districtCount, 0);
    expect(result.population, GameContent.initialPopulation);
    expect(result.marsResidents, 0);
    expect(result.money, greaterThanOrEqualTo(0));
    expect(facility(result, 'launch').status, ForecastFacilityStatus.paused);
    expect(facility(result, 'launch').stopReason, contains('手動で再開'));
    expect(game.state.habitatChoice, isNull);
    expect(game.state.facilities.values.every((enabled) => enabled), isTrue);
  });

  test(
    'queued dependencies proceed to the unselected habitat branch and stop',
    () {
      final game = ready();
      game.state.researchPointUnits = 0;
      expect(game.enqueue('life_support'), isNull);
      game.enqueue('habitat_kit');
      game.enqueue('mars_delivery');
      game.enqueue('build_habitat', repeats: null);
      final result = forecastPlans(game.state, const Duration(hours: 8));
      expect(result.completedResearch, {'life_support'});
      expect(result.newAchievements, {'first_landing'});
      expect(result.completedRuns, 3);
      expect(result.earthKits, 0);
      expect(result.marsKits, 1);
      expect(result.marsResidents, 0);
      expect(facility(result, 'mars').status, ForecastFacilityStatus.waiting);
      expect(facility(result, 'mars').taskId, 'build_habitat');
      expect(facility(result, 'mars').stopReason, contains('分岐待ち'));
      expect(game.state.research, isEmpty);
      expect(game.state.habitatChoice, isNull);
    },
  );

  test('RP, knowledge prerequisites, resources and paused equipment remain distinct', () {
    final game = ready();
    game.state.research.add(ResearchCatalog.idForCatalog('E01'));
    game.state.researchPointUnits = 0;
    expect(game.enqueue('urban_planning'), isNull);
    // A reservation retained from the old tree remains inspectable while its
    // new knowledge prerequisite is missing. New hidden nodes cannot be queued.
    game.state.plans.add(
      PlannedTask(
        id: 'plan-${game.state.nextPlanId++}',
        taskId: 'automated_fabrication',
      ),
    );
    game.enqueue('mars_delivery');
    game.setFacilityEnabled('factory', false);
    game.enqueueDistrict('earth_delta', 0, 'housing');
    final result = forecastPlans(game.state, const Duration(hours: 8));
    expect(result.completedResearch, {'urban_planning'});
    expect(facility(result, 'lab').status, ForecastFacilityStatus.waiting);
    expect(facility(result, 'lab').stopReason, contains('前提研究待ち'));
    expect(facility(result, 'launch').status, ForecastFacilityStatus.waiting);
    expect(facility(result, 'launch').stopReason, contains('資源不足'));
    expect(facility(result, 'factory').status, ForecastFacilityStatus.paused);
    expect(facility(result, 'factory').taskId, 'district_housing');
    expect(result.districtDelta, 0);
  });

  test(
    'insufficient funds wait and reserved work starts when income recovers',
    () {
      final game = GameEngine(GameState.initial(epoch)..money = 0);
      game.enqueueDistrict('earth_delta', 0, 'housing');
      final near = forecastPlans(game.state, const Duration(minutes: 30));
      expect(near.districtDelta, 0);
      expect(facility(near, 'factory').status, ForecastFacilityStatus.waiting);
      expect(facility(near, 'factory').stopReason, contains('資金不足'));
      final later = forecastPlans(game.state, const Duration(hours: 8));
      expect(later.districtDelta, 1);
      expect(later.districtLevelDelta, 1);
      expect(later.populationDelta, 60);
      expect(later.completedRuns, 1);
      expect(later.money, greaterThanOrEqualTo(0));
      expect(facility(later, 'launch').enabled, isFalse);
      expect(game.state.money, 0);
      expect(game.state.districts, isEmpty);
    },
  );

  test(
    'eight-hour projection matches irregular advances and saved resumes',
    () {
      final game = ready();
      game.state.research.addAll([
        'urban_planning',
        'life_support',
        'orbital_gardens',
      ]);
      final pendingResearch = ResearchCatalog.idForCatalog('B05');
      game.state.researchPointUnits = 0;
      game.state.achievements.add('first_landing');
      game.chooseHabitat('dome');
      game.state.marsKits = 3;
      game.enqueueDistrict('earth_highland', 0, 'campus');
      game.enqueueDistrict('earth_highland', 1, 'solar');
      game.enqueue('factory_contract', repeats: null);
      game.enqueue(
        'urban_planning',
      ); // Already researched: rejected, never duplicated.
      game.enqueueDistrict('mars_arcadia', 2, 'mars_habitat');
      expect(game.enqueue(pendingResearch), isNull);
      game.enqueue('launch_contract', repeats: 3);
      final before = jsonEncode(game.state.toJson());
      final result = forecastPlans(game.state, const Duration(hours: 8));
      var actual = GameEngine(clone(game.state));
      var remaining = const Duration(hours: 8).inMilliseconds;
      while (remaining > 0) {
        final step = remaining.clamp(0, 370013);
        actual.advanceBy(Duration(milliseconds: step));
        actual = GameEngine(clone(actual.state));
        remaining -= step;
      }
      expect(result.moneyUnits, actual.state.moneyUnits);
      expect(result.netPerMinute, actual.state.netPerMinute);
      expect(result.districtCount, actual.state.districts.length);
      expect(result.population, actual.state.population);
      expect(result.marsResidents, actual.state.marsResidents);
      expect(
        result.completedResearch,
        actual.state.research.difference(game.state.research),
      );
      expect(
        result.newAchievements,
        actual.state.achievements.difference(game.state.achievements),
      );
      expect(
        result.completedRuns,
        actual.state.plans.fold(0, (sum, p) => sum + p.completedRuns) -
            game.state.plans.fold(0, (sum, p) => sum + p.completedRuns),
      );
      expect(result.marsResidentsDelta, 24);
      expect(result.districtDelta, 3);
      expect(result.completedResearch, contains(pendingResearch));
      for (final item in result.facilities) {
        expect(item.enabled, actual.state.facilities[item.facilityId]);
        expect(
          item.remainingMs,
          actual.state.currentPlanFor(item.facilityId)?.remainingMs ?? 0,
        );
      }
      expect(actual.state.lastWallClockMs, game.state.lastWallClockMs);
      expect(jsonEncode(game.state.toJson()), before);
    },
  );

  test('legacy paid duration is frozen and forecast rewards never enter the real save', () {
    final game = ready();
    game.state.research.addAll(['urban_planning', 'automated_fabrication']);
    const campus = DistrictState(
      cityId: 'earth_highland',
      plotIndex: 0,
      districtId: 'campus',
    );
    game.state.districts[campus.key] = campus;
    game.upgradeDistrict('earth_highland', 0);
    final json = game.state.toJson()..['contentVersion'] = 'district-2';
    final oldPlan = (json['plans'] as List).single as Map;
    oldPlan['iterationDurationMs'] = const Duration(hours: 4).inMilliseconds;
    oldPlan['remainingMs'] = const Duration(hours: 2).inMilliseconds;
    final old = GameState.fromJson(json);
    final near = forecastPlans(old, const Duration(hours: 1));
    expect(near.districtLevelDelta, 0);
    expect(
      facility(near, 'factory').remainingMs,
      const Duration(hours: 1).inMilliseconds,
    );
    final later = forecastPlans(old, const Duration(hours: 8));
    expect(later.districtLevelDelta, 1);
    expect(later.districtDelta, 0);
    expect(later.completedRuns, 1);
    expect(
      old.plans.single.remainingMs,
      const Duration(hours: 2).inMilliseconds,
    );

    final reward = ready();
    reward.state.achievements.add('first_landing');
    reward.state.marsKits = 1;
    reward.chooseHabitat('dome');
    reward.enqueue('build_habitat');
    final before = jsonEncode(reward.state.toJson());
    final first = forecastPlans(reward.state, const Duration(minutes: 30));
    final second = forecastPlans(reward.state, const Duration(minutes: 30));
    expect(first.newAchievements, {'dome_habitat'});
    expect(first.moneyUnits, second.moneyUnits);
    final actual = GameEngine(clone(reward.state))
      ..advanceBy(const Duration(minutes: 30));
    expect(first.moneyUnits, actual.state.moneyUnits);
    expect(first.marsResidentsDelta, 12);
    expect(actual.state.claimedRewards, hasLength(1));
    expect(jsonEncode(reward.state.toJson()), before);
  });

  test('completion deltas ignore old history and survive finished-history trimming', () {
    final game = ready();
    for (var i = 0; i < GameContent.maxFinishedPlans; i++) {
      game.enqueue('factory_contract');
      game.advanceBy(const Duration(seconds: 90));
    }
    expect(game.state.plans, hasLength(GameContent.maxFinishedPlans));
    game.enqueue('factory_contract', repeats: 3);
    game.enqueue('launch_contract', repeats: 2);
    final result = forecastPlans(game.state, const Duration(minutes: 30));
    expect(result.completedRuns, 5);
    expect(result.completions, hasLength(2));
    expect(facility(result, 'factory').completedRuns, 3);
    expect(facility(result, 'launch').completedRuns, 2);
  });

  test('reordering a build ahead of unlimited work changes the forecast without interrupting the paid run', () {
    final game = ready();
    game.enqueue('factory_contract', repeats: null);
    final contract = game.state.currentPlanFor('factory')!;
    game.enqueueDistrict('earth_delta', 0, 'housing');
    final house = game.state.plans.last;
    final blocked = forecastPlans(game.state, const Duration(minutes: 30));
    expect(blocked.districtDelta, 0);
    expect(blocked.completions.any((c) => c.planId == house.id), isFalse);
    expect(
      game.reorderPlan(house.id, relativeToPlanId: contract.id, before: true),
      isNull,
    );
    expect(game.state.currentPlanFor('factory'), same(contract));
    expect(contract.completedRuns, 0);
    final before = jsonEncode(game.state.toJson());
    final prioritized = forecastPlans(game.state, const Duration(minutes: 30));
    expect(prioritized.districtDelta, 1);
    expect(prioritized.populationDelta, 60);
    expect(
      prioritized.completions.singleWhere((c) => c.planId == house.id).runs,
      1,
    );
    expect(prioritized.money, lessThan(blocked.money));
    expect(jsonEncode(game.state.toJson()), before);
    game.advanceBy(const Duration(minutes: 30));
    expect(game.state.moneyUnits, prioritized.moneyUnits);
    expect(game.state.districts.length, prioritized.districtCount);
  });

  test('unlimited work is counted accurately for eight hours without reserving more', () {
    final game = ready();
    game.enqueue('factory_contract', repeats: null);
    game.enqueue('launch_contract', repeats: null);
    final result = forecastPlans(game.state, const Duration(hours: 8));
    expect(facility(result, 'factory').completedRuns, 320);
    expect(facility(result, 'launch').completedRuns, 240);
    expect(result.completedRuns, 560);
    expect(result.completions, hasLength(2));
    expect(facility(result, 'factory').status, ForecastFacilityStatus.running);
    expect(facility(result, 'factory').queuedPlans, 1);
    expect(game.state.plans, hasLength(2));
    expect(game.state.plans.every((plan) => plan.completedRuns == 0), isTrue);
  });

  test('RP forecast unlocks exactly at the affordable boundary without mutating its bank', () {
    final game = ready();
    game.state.researchPointUnits = 0;
    expect(game.enqueue('life_support'), isNull);
    final wait = game.state.researchWaitMs('life_support')!;
    final before = jsonEncode(game.state.toJson());
    final near = forecastPlans(game.state, Duration(milliseconds: wait - 1));
    expect(near.completedResearch, isEmpty);
    expect(facility(near, 'lab').status, ForecastFacilityStatus.waiting);
    expect(facility(near, 'lab').stopReason, contains('研究ポイント待ち'));
    final readyAtBoundary = forecastPlans(
      game.state,
      Duration(milliseconds: wait),
    );
    expect(readyAtBoundary.completedResearch, {'life_support'});
    expect(readyAtBoundary.completedRuns, 1);
    expect(
      facility(readyAtBoundary, 'lab').status,
      ForecastFacilityStatus.idle,
    );
    expect(jsonEncode(game.state.toJson()), before);
    expect(game.state.researchPointUnits, 0);
  });

  test(
    'negative horizons are rejected and result collections are immutable',
    () {
      final game = ready();
      expect(
        () => forecastPlans(game.state, const Duration(seconds: -1)),
        throwsArgumentError,
      );
      final result = forecastPlans(game.state, Duration.zero);
      expect(
        () => result.completedResearch.add('life_support'),
        throwsUnsupportedError,
      );
      expect(
        () => result.newAchievements.add('first_landing'),
        throwsUnsupportedError,
      );
      expect(() => result.facilities.clear(), throwsUnsupportedError);
      expect(() => result.completions.clear(), throwsUnsupportedError);
    },
  );
}
