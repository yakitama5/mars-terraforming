import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/plan_forecast.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 14);
  GameState copy(GameState state) => GameState.fromJson(
    jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
  );
  GameEngine ready() => GameEngine(GameState.initial(epoch)..money = 100000);
  void demonstrate(GameState state) {
    state.research.addAll(['urban_planning', 'life_support']);
    for (final (index, id) in [(0, 'housing'), (8, 'industry')]) {
      final d = DistrictState(
        cityId: 'earth_delta',
        plotIndex: index,
        districtId: id,
      );
      state.districts[d.key] = d;
    }
  }

  test('default staffing preserves old efficiency and is distinct from city population', () {
    final game = ready();
    expect(game.state.specialistCount, 12);
    expect(game.state.researchers, 6);
    expect(game.state.industrialWorkers, 6);
    expect(game.state.staffEfficiencyBonus('lab'), 0);
    expect(game.state.staffEfficiencyBonus('factory'), 0);
    expect(game.state.factoryBonusPercent, 0);
    expect(game.state.currentTaskDurationMs('life_support'), 120000);
    expect(game.state.population, GameContent.initialPopulation);
    expect(game.state.agencyStatus.fame, 0);
    expect(game.state.agencyStatus.friendship, 10);
  });

  test(
    'allocation affects only future starts and cannot double-assign paid staff',
    () {
      final game = ready();
      expect(game.assignResearchers(10), isNull);
      expect(game.state.staffEfficiencyBonus('lab'), 8);
      expect(game.state.staffEfficiencyBonus('factory'), -8);
      game.enqueue('train_specialists');
      final research = game.state.currentPlanFor('lab')!;
      expect(research.iterationSpecialists, 10);
      expect(
        research.iterationDurationMs,
        lessThan(GameContent.tasks['train_specialists']!.durationMs),
      );
      final paid = research.iterationDurationMs;
      expect(game.assignResearchers(0), contains('確保中'));
      game.setFacilityEnabled('lab', false);
      expect(game.assignResearchers(0), contains('確保中'));
      game.enqueue('factory_contract');
      expect(game.state.reservedIndustrialWorkers, 2);
      expect(game.assignResearchers(11), contains('確保中'));
      expect(game.state.researchers, 10);
      expect(research.iterationDurationMs, paid);
      final resumed = GameEngine(copy(game.state));
      expect(resumed.state.reservedResearchers, 10);
      expect(resumed.state.reservedIndustrialWorkers, 2);
      expect(resumed.assignResearchers(6), isNotNull);
    },
  );

  test(
    'zero staff prevents new starts and allocation releases the waiting job',
    () {
      final game = ready();
      expect(game.assignResearchers(0), isNull);
      game.enqueue('train_specialists');
      expect(game.state.plans.single.status, 'queued');
      expect(game.state.plans.single.stopReason, contains('人員待ち'));
      final money = game.state.moneyUnits;
      expect(game.assignResearchers(6), isNull);
      expect(game.state.plans.single.status, 'running');
      expect(
        game.state.moneyUnits,
        money -
            GameContent.tasks['train_specialists']!.cost * GameState.moneyScale,
      );
      expect(game.assignResearchers(-1), isNotNull);
      expect(game.assignResearchers(13), isNotNull);
    },
  );

  test(
    'training is explicit, finite, preserves population and stops at its cap',
    () {
      final game = ready();
      game.enqueue('train_specialists', repeats: 2);
      game.advanceBy(const Duration(minutes: 6));
      expect(game.state.specialistCount, 16);
      expect(game.state.researchers, 6);
      expect(game.state.industrialWorkers, 10);
      expect(game.state.population, GameContent.initialPopulation);
      expect(game.state.plans.single.completedRuns, 2);
      game.advanceBy(const Duration(days: 1));
      expect(game.state.specialistCount, 16);
      final capped = ready();
      capped.state.specialistCount = GameContent.maxSpecialists - 2;
      capped.enqueue('train_specialists', repeats: null);
      capped.advanceBy(const Duration(hours: 1));
      expect(capped.state.specialistCount, GameContent.maxSpecialists);
      expect(capped.state.plans.single.completedRuns, 1);
      expect(capped.state.plans.single.stopReason, contains('上限'));
      final after = capped.state.moneyUnits;
      capped.advanceBy(const Duration(minutes: 1));
      expect(
        capped.state.moneyUnits,
        after + capped.state.netPerMinute * 60000,
      );
    },
  );

  test('training at insufficient funds waits without creating specialists', () {
    final game = GameEngine(GameState.initial(epoch)..money = 0);
    game.enqueue('train_specialists');
    game.advanceBy(const Duration(minutes: 10));
    expect(game.state.specialistCount, 12);
    expect(game.state.plans.single.stopReason, contains('資金不足'));
    expect(game.state.plans.single.completedRuns, 0);
  });

  test(
    'support requires real milestones and grants funds exactly once after save',
    () {
      var game = ready();
      final before = game.state.moneyUnits;
      expect(game.choosePartnership('research_exchange', 'funding'), isNotNull);
      expect(game.state.moneyUnits, before);
      demonstrate(game.state);
      expect(
        game.state.availablePartnerships.map((e) => e.id),
        contains('research_exchange'),
      );
      expect(
        game.choosePartnership('research_exchange', 'not-a-choice'),
        isNotNull,
      );
      expect(game.choosePartnership('research_exchange', 'funding'), isNull);
      expect(game.state.moneyUnits, before + 1200 * GameState.moneyScale);
      expect(game.state.agencyStatus.friendship, 13);
      expect(game.state.partnershipChoices['research_exchange'], 'funding');
      game = GameEngine(copy(game.state));
      final paid = game.state.moneyUnits;
      expect(
        game.choosePartnership('research_exchange', 'technology'),
        contains('選択済み'),
      );
      expect(
        game.choosePartnership('research_exchange', 'funding'),
        contains('選択済み'),
      );
      expect(game.state.moneyUnits, paid);
      expect(game.state.claimedRewards, hasLength(1));
    },
  );

  test('technology partnership preserves paid work and adds only its stated future bonus', () {
    final game = ready();
    demonstrate(game.state);
    game.enqueue('train_specialists');
    game.enqueue('factory_contract');
    final research = game.state.currentPlanFor('lab')!;
    final production = game.state.currentPlanFor('factory')!;
    final paidResearch = research.iterationDurationMs;
    final paidProduction = production.iterationDurationMs;
    final money = game.state.moneyUnits;
    expect(game.choosePartnership('research_exchange', 'technology'), isNull);
    expect(game.state.moneyUnits, money);
    expect(game.state.partnershipEfficiencyBonus('lab'), 4);
    expect(game.state.partnershipEfficiencyBonus('factory'), 2);
    expect(research.iterationDurationMs, paidResearch);
    expect(production.iterationDurationMs, paidProduction);
    expect(
      game.state.currentTaskDurationMs('train_specialists'),
      lessThan(paidResearch),
    );
    expect(game.state.agencyStatus.friendship, 16);
  });

  test('friendship and contribution unlock orbital support without random or repeated offers', () {
    final game = ready();
    demonstrate(game.state);
    game.state.achievements.add('first_landing');
    expect(game.state.agencyStatus.spaceContribution, 11);
    expect(
      game.state.partnershipLockReason('orbital_support'),
      contains('友好度'),
    );
    game.choosePartnership('research_exchange', 'funding');
    expect(game.state.partnershipLockReason('orbital_support'), isNull);
    expect(game.choosePartnership('orbital_support', 'technology'), isNull);
    expect(game.state.partnershipEfficiencyBonus('launch'), 4);
    expect(game.state.partnershipEfficiencyBonus('lab'), 4);
    expect(game.state.agencyStatus.spaceContribution, 18);
    expect(
      game.state.availablePartnerships.map((p) => p.id),
      isNot(contains('orbital_support')),
    );
  });

  test(
    'unlimited contracts cannot farm fame, friendship or milestone support',
    () {
      final game = ready();
      game.enqueue('factory_contract', repeats: null);
      game.enqueue('launch_contract', repeats: null);
      game.advanceBy(const Duration(hours: 8));
      expect(game.state.contractRevenue, greaterThan(0));
      expect(game.state.agencyStatus.fame, 0);
      expect(game.state.agencyStatus.technology, 0);
      expect(game.state.agencyStatus.friendship, 10);
      expect(game.state.agencyStatus.spaceContribution, 0);
      expect(game.state.availablePartnerships, isEmpty);
      expect(game.state.claimedRewards, isEmpty);
    },
  );

  test(
    'three optional applied studies add effects without raising stage caps',
    () {
      final game = ready();
      game.state.research.addAll([
        'urban_planning',
        'life_support',
        'low_gravity_mobility',
        'subsurface_access',
        'local_resources',
        'subsurface_ice_mapping',
        'ground_penetrating_radar',
        'in_situ_sampling',
        'thermal_water_extraction',
        'water_purification',
        'atmospheric_collection',
        'geopolymer_fabrication',
      ]);
      game.state.researchPointUnits = 100000 * GameState.researchPointScale;
      final beforeFactory = game.state.researchEfficiencyBonus('factory');
      final beforeLaunch = game.state.researchEfficiencyBonus('launch');
      final beforeMars = game.state.researchEfficiencyBonus('mars');
      for (final id in [
        'process_design',
        'cargo_packaging',
        'habitat_operations',
      ]) {
        expect(game.enqueue(id), isNull);
      }
      final cap = game.state.facilityBonusCap('factory');
      game.advanceBy(const Duration(minutes: 12));
      expect(
        game.state.research,
        containsAll([
          'process_design',
          'cargo_packaging',
          'habitat_operations',
        ]),
      );
      expect(game.state.researchEfficiencyBonus('factory') - beforeFactory, 3);
      expect(game.state.researchEfficiencyBonus('launch') - beforeLaunch, 3);
      expect(game.state.researchEfficiencyBonus('mars') - beforeMars, 3);
      expect(game.state.facilityBonusCap('factory'), cap);
    },
  );

  test('staff, choices, rewards and new tasks match across irregular save/catch-up', () {
    final one = ready();
    demonstrate(one.state);
    one.choosePartnership('research_exchange', 'technology');
    one.assignResearchers(8);
    one.enqueue('train_specialists', repeats: 2);
    expect(one.enqueue('orbital_gardens'), isNull);
    expect(one.enqueue('local_resources'), isNull);
    one.enqueue('factory_contract', repeats: 9);
    one.enqueue('launch_contract', repeats: 9);
    var split = GameEngine(copy(one.state));
    one.advanceBy(const Duration(hours: 1));
    var elapsed = 0;
    while (elapsed < 3600000) {
      final step = (3600000 - elapsed).clamp(0, 127031);
      split.advanceBy(Duration(milliseconds: step));
      split = GameEngine(copy(split.state));
      elapsed += step;
    }
    expect(split.state.toJson(), one.state.toJson());
    expect(one.state.specialistCount, 16);
    expect(
      one.state.research,
      containsAll(['orbital_gardens', 'local_resources']),
    );
    expect(one.state.partnershipChoices, {'research_exchange': 'technology'});
  });

  test(
    'same-clock and backwards-clock resumes preserve trained staff and support',
    () {
      var game = ready();
      demonstrate(game.state);
      expect(game.choosePartnership('research_exchange', 'funding'), isNull);
      game.state.researchPointUnits = 0;
      game.enqueue('train_specialists');
      game.enqueue('orbital_gardens');
      final completedAt = epoch.add(const Duration(minutes: 3));
      game.advanceTo(completedAt);
      expect(game.state.specialistCount, 14);
      expect(game.state.plans.first.completedRuns, 1);
      expect(game.state.currentPlanFor('lab'), isNull);
      expect(game.state.plans.last.taskId, 'orbital_gardens');
      expect(game.state.plans.last.stopReason, contains('研究ポイント待ち'));
      final saved = game.state.toJson();
      game = GameEngine(copy(game.state));
      game.advanceTo(completedAt);
      game.advanceTo(completedAt);
      expect(game.state.toJson(), saved);

      final backwards = epoch.subtract(const Duration(days: 1));
      game.advanceTo(backwards);
      expect(game.state.toJson(), {
        ...saved,
        'lastWallClockMs': backwards.millisecondsSinceEpoch,
      });
      game = GameEngine(copy(game.state));
      game.advanceTo(backwards);
      final money = game.state.moneyUnits;
      expect(
        game.choosePartnership('research_exchange', 'funding'),
        contains('選択済み'),
      );
      expect(game.state.moneyUnits, money);
      final expected = GameEngine(copy(game.state))
        ..advanceBy(const Duration(minutes: 4));
      game.advanceTo(backwards.add(const Duration(minutes: 1)));
      expect(game.state.specialistCount, 14);
      expect(game.state.currentPlanFor('lab'), isNull);
      expect(game.state.researchPoints, greaterThan(0));
      expect(game.state.research, isNot(contains('orbital_gardens')));
      game = GameEngine(copy(game.state));
      game.advanceTo(backwards.add(const Duration(minutes: 4)));
      expect(game.state.toJson(), {
        ...expected.state.toJson(),
        'lastWallClockMs': backwards
            .add(const Duration(minutes: 4))
            .millisecondsSinceEpoch,
      });
      expect(game.state.research, contains('orbital_gardens'));
      expect(game.state.specialistCount, 14);
      expect(game.state.plans.first.completedRuns, 1);
      expect(game.state.claimedRewards, hasLength(1));
      expect(game.state.partnershipChoices, {'research_exchange': 'funding'});
    },
  );

  test('forecast cannot consume training or automatically select partnership rewards', () {
    final game = ready();
    demonstrate(game.state);
    game.enqueue('train_specialists');
    final before = jsonEncode(game.state.toJson());
    final result = forecastPlans(game.state, const Duration(minutes: 30));
    expect(result.completions.single.taskId, 'train_specialists');
    final actual = GameEngine(copy(game.state))
      ..advanceBy(const Duration(minutes: 30));
    expect(result.moneyUnits, actual.state.moneyUnits);
    expect(actual.state.specialistCount, 14);
    expect(actual.state.partnershipChoices, isEmpty);
    expect(jsonEncode(game.state.toJson()), before);
    expect(game.state.specialistCount, 12);
    expect(game.state.claimedRewards, isEmpty);
  });

  test('current save rejects impossible staffing and unrecorded partnership payouts', () {
    final game = ready();
    game.enqueue('train_specialists');
    final invalid = game.state.toJson()..['researchers'] = 0;
    expect(() => GameState.fromJson(invalid), throwsFormatException);
    final fake = game.state.toJson()
      ..['partnershipChoices'] = {'research_exchange': 'funding'};
    expect(() => GameState.fromJson(fake), throwsFormatException);
  });
}
