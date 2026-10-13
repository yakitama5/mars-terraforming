import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 13);
  GameEngine ready() {
    final state = GameState.initial(epoch)..money = 1000000;
    state.research.addAll(['urban_planning', 'automated_fabrication']);
    return GameEngine(state);
  }

  void place(
    GameState state,
    String city,
    int plot,
    String id, {
    int level = 1,
  }) {
    final district = DistrictState(
      cityId: city,
      plotIndex: plot,
      districtId: id,
      level: level,
    );
    state.districts[district.key] = district;
  }

  GameEngine restore(GameEngine game) => GameEngine(
    GameState.fromJson(
      jsonDecode(jsonEncode(game.state.toJson())) as Map<String, dynamic>,
    ),
  );

  test(
    'quotes separate level investment, developed land and new city setup',
    () {
      final game = ready();
      final initial = game.state.districtPreview('earth_delta', 0, 'housing');
      expect(initial.baseCost, 350);
      expect(initial.developmentCost, 0);
      expect(initial.setupCost, 0);
      expect(initial.durationMs, const Duration(minutes: 5).inMilliseconds);
      expect(initial.additionalPlots, 1);
      final expansion = game.state.districtPreview(
        'earth_highland',
        2,
        'housing',
      );
      expect(expansion.baseCost, 350);
      expect(expansion.setupCost, 1200);
      expect(
        expansion.setupDurationMs,
        const Duration(minutes: 15).inMilliseconds,
      );
      expect(expansion.cost, 1550);
      expect(expansion.durationMs, const Duration(minutes: 20).inMilliseconds);
      place(game.state, 'earth_delta', 0, 'housing');
      place(game.state, 'earth_delta', 1, 'campus');
      final build = game.state.districtPreview('earth_delta', 20, 'housing');
      expect(build.developmentPercent, 124);
      expect(build.developmentCost, 84);
      expect(
        build.developmentDurationMs,
        const Duration(seconds: 72).inMilliseconds,
      );
      final upgrade = game.state.districtPreview(
        'earth_delta',
        0,
        'housing',
        upgrade: true,
      );
      expect(upgrade.baseCost, 613); // Round upward, never fractional credits.
      expect(upgrade.cost, upgrade.baseCost);
      expect(upgrade.developmentCost, 0);
      expect(upgrade.setupCost, 0);
      expect(upgrade.additionalPlots, 0);
      expect(upgrade.durationMs, const Duration(minutes: 4).inMilliseconds);
    },
  );

  test('cluster upgrade buys time and adjacency; an empty plot buys cheaper income', () {
    final game = ready();
    place(game.state, 'earth_delta', 0, 'housing');
    place(game.state, 'earth_delta', 1, 'campus');
    final upgrade = game.state.districtPreview(
      'earth_delta',
      0,
      'housing',
      upgrade: true,
    );
    final build = game.state.districtPreview('earth_delta', 20, 'housing');
    const budget = 700;
    expect(upgrade.cost, lessThanOrEqualTo(budget));
    expect(build.cost, lessThanOrEqualTo(budget));
    expect(upgrade.netDeltaPerMinute, 17);
    expect(upgrade.researchBonusDelta, 1);
    expect(build.netDeltaPerMinute, 14);
    expect(upgrade.durationMs, lessThan(build.durationMs));
    expect(
      build.cost / build.netDeltaPerMinute,
      lessThan(upgrade.cost / upgrade.netDeltaPerMinute),
    );
    final isolated = game.state.districtPreview(
      'earth_delta',
      1,
      'campus',
      upgrade: true,
    );
    expect(isolated.cost, greaterThan(GameContent.districts['campus']!.cost));
  });

  test(
    'a new city repays setup across several plots instead of always losing',
    () {
      final state = ready().state;
      for (var i = 0; i < 12; i++) {
        place(state, 'earth_delta', i, 'housing');
      }
      var existingCost = 0, newCityCost = 0;
      var existingTime = 0, newCityTime = 0;
      for (var i = 0; i < 4; i++) {
        final existing = state.districtPreview('earth_delta', 12 + i, 'campus');
        final expansion = state.districtPreview('earth_highland', i, 'campus');
        existingCost += existing.cost;
        existingTime += existing.durationMs;
        newCityCost += expansion.cost;
        newCityTime += expansion.durationMs;
        place(state, 'earth_delta', 12 + i, 'campus');
        place(state, 'earth_highland', i, 'campus');
      }
      expect(newCityCost, lessThan(existingCost));
      expect(newCityTime, lessThan(existingTime));
      expect(newCityCost, 6864); // One setup, then density for plots 2–4.
      expect(existingCost, 12576);
    },
  );

  test('Mars cluster upgrade and mineral expansion have distinct benefits', () {
    final state = ready().state;
    state.research.addAll([
      'life_support',
      'closed_ecology',
      'local_resources',
      'orbital_logistics',
    ]);
    state.achievements.add('first_landing');
    state.habitatChoice = 'dome';
    place(state, 'mars_arcadia', 6, 'mars_habitat');
    place(state, 'mars_arcadia', 5, 'greenhouse');
    place(state, 'mars_arcadia', 1, 'extractor');
    place(state, 'mars_arcadia', 11, 'mars_lab');
    final upgrade = state.districtPreview(
      'mars_arcadia',
      6,
      'mars_habitat',
      upgrade: true,
    );
    final expand = state.districtPreview('mars_elysium', 3, 'mars_habitat');
    expect(upgrade.netDeltaPerMinute, 14);
    expect(upgrade.researchBonusDelta, 1);
    expect(upgrade.marsBonusDelta, 2);
    expect(expand.netDeltaPerMinute, 8);
    expect(upgrade.cost, 1225);
    expect(expand.cost, 2300);
    expect(upgrade.durationMs, lessThan(expand.durationMs));
    expect(
      state.districtPreview('mars_arcadia', 6, 'extractor').isValid,
      isFalse,
    );
    expect(
      state.districtPreview('mars_elysium', 2, 'extractor').isValid,
      isTrue,
    );
  });

  test(
    'reordering chooses the first setup payer; preview and paid work agree',
    () {
      final game = ready();
      game.setFacilityEnabled('factory', false);
      expect(game.enqueueDistrict('earth_highland', 2, 'housing'), isNull);
      final housing = game.state.plans.last;
      expect(game.enqueueDistrict('earth_highland', 0, 'solar'), isNull);
      final solar = game.state.plans.last;
      expect(
        game.reorderPlan(solar.id, relativeToPlanId: housing.id, before: true),
        isNull,
      );
      expect(game.state.cityDevelopment('earth_highland').reservedPlots, 2);
      expect(game.state.cityDevelopment('earth_highland').availablePlots, 23);
      final before = game.state.moneyUnits;
      final solarQuote = game.state.plannedCost(solar);
      final solarDuration = game.state.plannedDurationMs(solar);
      game.setFacilityEnabled('factory', true);
      expect(game.state.moneyUnits, before - solarQuote * GameState.moneyScale);
      expect(solar.iterationDurationMs, solarDuration);
      final net = game.state.netPerMinute;
      game.advanceBy(Duration(milliseconds: solarDuration));
      expect(housing.status, 'running');
      expect(game.state.plannedCost(housing), 392);
      expect(
        game.state.moneyUnits,
        before -
            (solarQuote + 392) * GameState.moneyScale +
            net * solarDuration,
      );
      expect(game.state.cityDevelopment('earth_highland').completedPlots, 1);
      expect(game.state.cityDevelopment('earth_highland').reservedPlots, 1);
      expect(
        housing.iterationDurationMs,
        const Duration(seconds: 336).inMilliseconds,
      );
    },
  );

  test(
    'setup, density and cargo match over split time and repeated saved resumes',
    () {
      final one = ready();
      one.state.research.addAll(['life_support', 'orbital_logistics']);
      one.state.achievements.add('first_landing');
      one.state.habitatChoice = 'dome';
      one.state.marsKits = 3;
      one.enqueueDistrict('earth_highland', 0, 'solar');
      one.enqueueDistrict('earth_highland', 2, 'housing');
      one.enqueueDistrict('mars_elysium', 3, 'mars_habitat');
      one.enqueueDistrict('mars_elysium', 6, 'mars_habitat');
      var split = restore(one);
      const total = Duration(hours: 2);
      one.advanceBy(total);
      var elapsed = 0;
      while (elapsed < total.inMilliseconds) {
        final step = (total.inMilliseconds - elapsed).clamp(0, 97013);
        split.advanceBy(Duration(milliseconds: step));
        split = restore(split);
        elapsed += step;
      }
      expect(split.state.toJson(), one.state.toJson());
      expect(one.state.districts, hasLength(4));
      expect(one.state.marsKits, 1);
      expect(one.state.marsResidents, 48);
      expect(one.state.claimedRewards, hasLength(1));
    },
  );

  test(
    'district-2 paid work retains its old cost and duration across retuning',
    () {
      final old = ready();
      old.enqueueDistrict('earth_highland', 0, 'campus');
      final snapshot = old.state.toJson()..['contentVersion'] = 'district-2';
      snapshot['moneyUnits'] =
          8800 * GameState.moneyScale; // Old 1200 Cr payment.
      final plan = (snapshot['plans'] as List).single as Map;
      plan['iterationDurationMs'] = const Duration(hours: 1).inMilliseconds;
      plan['remainingMs'] = const Duration(minutes: 30).inMilliseconds;
      final game = GameEngine(GameState.fromJson(snapshot));
      expect(game.state.money, 8800);
      expect(
        game.state.plans.single.iterationDurationMs,
        const Duration(hours: 1).inMilliseconds,
      );
      final again = restore(game);
      expect(again.state.moneyUnits, game.state.moneyUnits);
      expect(
        again.state.plans.single.remainingMs,
        const Duration(minutes: 30).inMilliseconds,
      );
      again.advanceBy(const Duration(minutes: 30));
      expect(again.state.districts, hasLength(1));
      expect(
        again.state.money,
        8440,
      ); // Existing upkeep only; no new setup charge.
      final next = again.state.districtPreview('earth_highland', 1, 'solar');
      expect(next.setupCost, 0);
      expect(next.developmentCost, 78);
      expect(again.state.toJson()['contentVersion'], 'district-3');
    },
  );

  test('preview distinguishes potential adjacency from an efficiency cap', () {
    final state = ready().state;
    state.research.remove('automated_fabrication');
    for (final index in [0, 1, 5, 9, 12]) {
      place(state, 'earth_highland', index, 'campus');
    }
    expect(state.researchBonusPercent, 30);
    final preview = state.districtPreview('earth_highland', 15, 'campus');
    expect(preview.rawResearchBonusDelta, 6);
    expect(preview.researchBonusDelta, 0);
    expect(preview.rawFactoryBonusDelta, 0);
  });

  test('city milestones count finished levels, not reservations, and grant no rewards', () {
    final game = ready();
    var city = game.state.cityDevelopment('earth_delta');
    expect(city.stageName, '候補地');
    expect(city.nextStageAtTotalLevels, 1);
    game.enqueueDistrict('earth_delta', 0, 'housing');
    expect(game.state.cityDevelopment('earth_delta').totalLevels, 0);
    game.advanceBy(const Duration(minutes: 5));
    city = game.state.cityDevelopment('earth_delta');
    expect(city.stageName, '拠点');
    expect(city.totalLevels, 1);
    expect(city.nextStageAtTotalLevels, 8);
    place(game.state, 'earth_delta', 0, 'housing', level: 3);
    place(game.state, 'earth_delta', 1, 'campus', level: 3);
    place(game.state, 'earth_delta', 2, 'housing', level: 2);
    city = game.state.cityDevelopment('earth_delta');
    expect(city.stageName, '成長都市');
    expect(city.completedPlots, 3);
    expect(city.totalLevels, 8);
    expect(city.nextStageAtTotalLevels, 20);
    expect(game.state.claimedRewards, isEmpty);
  });
}
