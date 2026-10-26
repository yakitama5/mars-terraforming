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
  GameEngine ready() => GameEngine(
    GameState.initial(epoch)
      ..firstRunTutorial = FirstRunTutorialStep.completed
      ..openingSeen = true
      ..money = 100000,
  );
  void demonstrate(GameState state) {
    state.research.addAll(['urban_planning', 'life_support']);
    for (final (index, id) in [(0, 'housing'), (8, 'industry')]) {
      final district = DistrictState(
        cityId: 'earth_delta',
        plotIndex: index,
        districtId: id,
      );
      state.districts[district.key] = district;
    }
  }

  test('deprecated staff records never alter facility output or duration', () {
    final game = ready();
    final rate = game.state.researchPointsPerMinute;
    final duration = game.state.currentTaskDurationMs('factory_contract');
    game.state.specialistCount = 0;
    game.state.researchers = 0;
    expect(game.state.staffEfficiencyBonus('lab'), 0);
    expect(game.state.staffEfficiencyBonus('factory'), 0);
    expect(game.state.researchPointsPerMinute, rate);
    expect(game.state.currentTaskDurationMs('factory_contract'), duration);
    expect(game.enqueue('factory_contract'), isNull);
    expect(game.state.currentPlanFor('factory')!.iterationSpecialists, 0);
    expect(() => copy(game.state), returnsNormally);
    expect(game.state.population, GameContent.initialPopulation);
    expect(game.state.agencyStatus.friendship, 10);
  });

  test('staffing and training commands are retired without state changes', () {
    final game = ready();
    final before = game.state.toJson();
    expect(game.assignResearchers(0), isNotNull);
    expect(game.assignResearchers(100), isNotNull);
    expect(game.assignDevelopmentResearchers('local_resources', 4), isNotNull);
    expect(game.enqueue('train_specialists'), isNotNull);
    expect(game.enqueue('train_specialists', repeats: null), isNotNull);
    expect(game.state.toJson(), before);
  });

  test('paid old work retains duration and needs no staff after reload', () {
    final game = ready();
    expect(game.enqueue('factory_contract'), isNull);
    final paid = game.state.currentPlanFor('factory')!;
    paid.iterationSpecialists = 12;
    paid.iterationDurationMs = 70000;
    paid.remainingMs = 43000;
    final json = game.state.toJson()
      ..['contentVersion'] = 'district-10'
      ..['specialistCount'] = 0
      ..['researchers'] = 0;
    final restored = GameEngine(GameState.fromJson(json));
    expect(restored.state.currentPlanFor('factory')!.remainingMs, 43000);
    expect(
      restored.state.currentPlanFor('factory')!.iterationDurationMs,
      70000,
    );
    restored.advanceBy(const Duration(milliseconds: 43000));
    expect(restored.state.plans.single.completedRuns, 1);
    expect(restored.state.plans.single.isFinished, isTrue);
    final after = restored.state.toJson();
    final again = GameEngine(copy(restored.state));
    expect(again.state.toJson(), after);
  });

  test(
    'unpaid old training is retired and paid training ends its current run',
    () {
      final state = ready().state;
      final running =
          PlannedTask(
              id: 'plan-1',
              taskId: 'train_specialists',
              remainingRepeats: null,
            )
            ..status = 'running'
            ..remainingMs = 1000
            ..iterationDurationMs = 180000;
      final unpaid = PlannedTask(id: 'plan-2', taskId: 'train_specialists');
      state.plans.addAll([running, unpaid]);
      state.nextPlanId = 3;
      final game = GameEngine(state);
      expect(unpaid.status, 'cancelled');
      expect(running.remainingRepeats, 1);
      final population = state.population;
      game.advanceBy(const Duration(seconds: 1));
      expect(running.completedRuns, 1);
      expect(running.isFinished, isTrue);
      final specialists = state.specialistCount;
      game.advanceBy(const Duration(hours: 2));
      expect(state.specialistCount, specialists);
      expect(state.population, population);
    },
  );

  test('support requires milestones and grants funds once across reload', () {
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
  });

  test(
    'technology partnership preserves paid work and affects future capacity',
    () {
      final game = ready();
      demonstrate(game.state);
      expect(game.enqueue('factory_contract'), isNull);
      final production = game.state.currentPlanFor('factory')!;
      final paidDuration = production.iterationDurationMs;
      final money = game.state.moneyUnits;
      expect(game.choosePartnership('research_exchange', 'technology'), isNull);
      expect(game.state.moneyUnits, money);
      expect(game.state.partnershipEfficiencyBonus('lab'), 4);
      expect(game.state.partnershipEfficiencyBonus('factory'), 2);
      expect(production.iterationDurationMs, paidDuration);
      expect(
        game.state.currentTaskDurationMs('factory_contract'),
        lessThan(paidDuration),
      );
      expect(game.state.agencyStatus.friendship, 16);
    },
  );

  test(
    'friendship and contribution unlock support without repeated offers',
    () {
      final game = ready();
      demonstrate(game.state);
      game.state.achievements.add('first_landing');
      expect(game.state.agencyStatus.spaceContribution, 11);
      expect(
        game.state.partnershipLockReason('orbital_support'),
        contains('友好度'),
      );
      expect(game.choosePartnership('research_exchange', 'funding'), isNull);
      expect(game.state.partnershipLockReason('orbital_support'), isNull);
      expect(game.choosePartnership('orbital_support', 'technology'), isNull);
      expect(game.state.partnershipEfficiencyBonus('launch'), 4);
      expect(game.state.partnershipEfficiencyBonus('lab'), 4);
      expect(game.state.agencyStatus.spaceContribution, 18);
      expect(
        game.state.availablePartnerships.map((p) => p.id),
        isNot(contains('orbital_support')),
      );
    },
  );

  test('unlimited contracts cannot farm fame or milestone support', () {
    final game = ready();
    game.enqueue('factory_contract', repeats: null);
    game.enqueue('launch_contract', repeats: null);
    game.advanceBy(const Duration(seconds: 120));
    expect(game.state.agencyStatus.fame, 8);
    expect(game.state.agencyStatus.spaceContribution, 8);
    game.advanceBy(const Duration(hours: 8));
    expect(game.state.contractRevenue, greaterThan(0));
    expect(game.state.agencyStatus.fame, 8);
    expect(game.state.agencyStatus.technology, 0);
    expect(game.state.agencyStatus.friendship, 10);
    expect(game.state.agencyStatus.spaceContribution, 8);
    expect(game.state.availablePartnerships, isEmpty);
    expect(game.state.claimedRewards, {
      '${game.state.worldId}:achievement:first_launch',
    });
  });

  test(
    'applied knowledge adds only its stated effects without raising stage caps',
    () {
      final game = ready();
      final beforeFactory = game.state.researchEfficiencyBonus('factory');
      final beforeLaunch = game.state.researchEfficiencyBonus('launch');
      final beforeMars = game.state.researchEfficiencyBonus('mars');
      final cap = game.state.facilityBonusCap('factory');
      game.state.research.addAll([
        'process_design',
        'cargo_packaging',
        'habitat_operations',
      ]);
      expect(game.state.researchEfficiencyBonus('factory') - beforeFactory, 3);
      expect(game.state.researchEfficiencyBonus('launch') - beforeLaunch, 3);
      expect(game.state.researchEfficiencyBonus('mars') - beforeMars, 3);
      expect(game.state.facilityBonusCap('factory'), cap);
    },
  );

  test('choices, capped reserves and work match irregular save/catch-up', () {
    final one = ready();
    demonstrate(one.state);
    one.choosePartnership('research_exchange', 'technology');
    one.state.researchPointUnits = 48 * GameState.researchPointScale;
    expect(one.unlockResearch('orbital_gardens'), isNull);
    expect(one.unlockResearch('local_resources'), isNull);
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
    expect(
      one.state.research,
      containsAll(['orbital_gardens', 'local_resources']),
    );
    expect(one.state.partnershipChoices, {'research_exchange': 'technology'});
  });

  test('same-clock and backwards-clock reloads preserve capped reserves and rewards', () {
    var game = ready();
    demonstrate(game.state);
    expect(game.choosePartnership('research_exchange', 'funding'), isNull);
    game.state.researchPointUnits = 0;
    game.enqueue('factory_contract');
    final completedAt = epoch.add(const Duration(days: 2));
    game.advanceTo(completedAt);
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
    final expected = GameEngine(copy(game.state))
      ..advanceBy(const Duration(minutes: 4));
    game.advanceTo(backwards.add(const Duration(minutes: 4)));
    expect(game.state.toJson(), {
      ...expected.state.toJson(),
      'lastWallClockMs': backwards
          .add(const Duration(minutes: 4))
          .millisecondsSinceEpoch,
    });
    expect(
      game.choosePartnership('research_exchange', 'funding'),
      contains('選択済み'),
    );
    expect(game.state.research, isNot(contains('orbital_gardens')));
    expect(game.state.claimedRewards, hasLength(1));
  });

  test(
    'forecast keeps source immutable and never selects support or research',
    () {
      final game = ready();
      demonstrate(game.state);
      game.enqueue('factory_contract');
      final before = jsonEncode(game.state.toJson());
      final result = forecastPlans(game.state, const Duration(minutes: 30));
      expect(result.completions.single.taskId, 'factory_contract');
      final actual = GameEngine(copy(game.state))
        ..advanceBy(const Duration(minutes: 30));
      expect(result.moneyUnits, actual.state.moneyUnits);
      expect(actual.state.partnershipChoices, isEmpty);
      expect(actual.state.research, isNot(contains('orbital_gardens')));
      expect(jsonEncode(game.state.toJson()), before);
      expect(game.state.claimedRewards, isEmpty);
    },
  );

  test(
    'current save rejects negative legacy staff and unrecorded support payouts',
    () {
      final game = ready();
      final invalid = game.state.toJson()..['researchers'] = -1;
      expect(() => GameState.fromJson(invalid), throwsFormatException);
      final fake = game.state.toJson()
        ..['partnershipChoices'] = {'research_exchange': 'funding'};
      expect(() => GameState.fromJson(fake), throwsFormatException);
    },
  );
}
