import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 21);
  GameEngine fresh() => GameEngine(GameState.initial(epoch)..money = 1000000);
  GameState roundTrip(GameState state) => GameState.fromJson(
    jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
  );
  void district(GameState state, String id, int plot) {
    final definition = GameContent.districts[id]!;
    final city = definition.planet == 'moon'
        ? 'moon_south_pole'
        : 'earth_delta';
    final built = DistrictState(cityId: city, plotIndex: plot, districtId: id);
    state.districts[built.key] = built;
  }

  test(
    'a completed launch opens only the Moon and records its reward once',
    () {
      final game = fresh();
      expect(game.state.planetUnlocked('earth'), isTrue);
      expect(game.state.planetUnlocked('moon'), isFalse);
      expect(game.state.planetUnlocked('mars'), isFalse);
      expect(game.enqueue('launch_contract', repeats: 3), isNull);
      expect(game.state.planetUnlocked('moon'), isFalse);
      game.advanceBy(const Duration(seconds: 119));
      expect(game.state.planetUnlocked('moon'), isFalse);
      game.advanceBy(const Duration(seconds: 1));
      expect(game.state.planetUnlocked('moon'), isTrue);
      expect(game.state.cityUnlocked('moon_south_pole'), isTrue);
      expect(game.state.planetUnlocked('mars'), isFalse);
      game.advanceBy(const Duration(seconds: 240));
      expect(
        game.state.claimedRewards.where((key) => key.endsWith(':first_launch')),
        hasLength(1),
      );
      expect(roundTrip(game.state).planetUnlocked('moon'), isTrue);
    },
  );

  test(
    'Moon cargo waits for a real launch without charging or consuming kits',
    () {
      final game = fresh();
      game.state.earthKits = 2;
      final money = game.state.money;
      expect(game.enqueue('moon_delivery'), isNull);
      expect(game.state.plans.single.status, 'queued');
      expect(game.state.plans.single.stopReason, contains('ロケット打ち上げ'));
      expect(game.state.money, money);
      expect(game.state.earthKits, 2);
      expect(game.state.moonKits, 0);
    },
  );

  test(
    'public commands connect Earth, lunar construction, a probe and Mars',
    () {
      final game = fresh();
      game.state.research.add('life_support');
      expect(game.enqueue('launch_contract'), isNull);
      game.advanceBy(const Duration(seconds: 120));
      expect(game.enqueue('habitat_kit', repeats: 3), isNull);
      game.advanceBy(const Duration(seconds: 540));
      expect(game.enqueue('moon_delivery', repeats: 2), isNull);
      game.advanceBy(const Duration(seconds: 300));
      expect(game.state.moonKits, 2);
      expect(
        game.enqueueDistrict('moon_south_pole', 12, 'moon_spaceport'),
        contains('月面基地'),
      );
      expect(
        game.enqueueDistrict('moon_south_pole', 12, 'moon_outpost'),
        isNull,
      );
      final base = game.state.plans.last;
      game.advanceBy(Duration(milliseconds: base.remainingMs));
      expect(game.state.moonKits, 1);
      expect(
        game.state.spaceTaskLockReason(GameContent.tasks['mars_probe']!),
        contains('打ち上げ基地'),
      );
      expect(
        game.enqueueDistrict('moon_south_pole', 13, 'moon_spaceport'),
        isNull,
      );
      final spaceport = game.state.plans.last;
      game.advanceBy(Duration(milliseconds: spaceport.remainingMs));
      expect(game.state.moonKits, 0);
      expect(game.state.launchCostReductionPercent, 15);
      expect(game.state.planetUnlocked('mars'), isFalse);
      expect(game.enqueue('mars_probe', repeats: null), isNotNull);
      expect(game.enqueue('mars_probe', repeats: 3), isNotNull);
      expect(game.enqueue('mars_probe'), isNull);
      expect(game.enqueue('mars_probe'), isNotNull);
      final probe = game.state.plans.last;
      game.advanceBy(Duration(milliseconds: probe.remainingMs));
      expect(game.state.planetUnlocked('mars'), isTrue);
      expect(game.state.cityUnlocked('mars_arcadia'), isFalse);
      expect(game.enqueue('mars_probe'), isNotNull);
      expect(game.enqueue('mars_delivery'), isNull);
      game.advanceBy(const Duration(seconds: 180));
      expect(game.state.marsKits, 1);
      expect(game.state.cityUnlocked('mars_arcadia'), isTrue);
      expect(
        game.state.achievements,
        containsAll([
          'first_launch',
          'moon_landing',
          'mars_route_open',
          'first_landing',
        ]),
      );
    },
  );

  test(
    'all Mars cargo paths share the exploration gate, including vehicles',
    () {
      for (final task in GameContent.tasks.values.where(
        (task) =>
            task.inputResource == 'earthKits' &&
            task.outputResource == 'marsKits',
      )) {
        final game = fresh();
        game.state.earthKits = 50;
        game.state.research.addAll(GameContent.researchTechnologies.keys);
        if (task.requiredDevelopmentId case final String id) {
          game.state.developments.add(id);
          game.state.developmentEnabled[id] = true;
          game.state.developmentCityIds[id] = 'earth_delta';
        }
        final money = game.state.money;
        if (task.buildingTechnologyId != null) {
          expect(
            game.state.spaceTaskLockReason(task),
            contains('火星探査機'),
            reason: task.id,
          );
          expect(game.enqueue(task.id), contains('都市の施設'), reason: task.id);
          expect(game.state.earthKits, 50);
          expect(game.state.money, money);
          continue;
        }
        expect(game.enqueue(task.id), isNull, reason: task.id);
        expect(game.state.plans.single.status, 'queued', reason: task.id);
        expect(
          game.state.plans.single.stopReason,
          contains('火星探査機'),
          reason: task.id,
        );
        expect(game.state.earthKits, 50, reason: task.id);
        expect(game.state.money, money, reason: task.id);
      }
    },
  );

  test(
    'probe completion and cargo catch-up match irregular partition and restart',
    () {
      final one = fresh();
      one.state.achievements.add('first_launch');
      one.state.earthKits = 3;
      district(one.state, 'moon_outpost', 12);
      district(one.state, 'moon_spaceport', 13);
      expect(one.enqueue('mars_probe'), isNull);
      expect(one.enqueue('mars_delivery', repeats: 3), isNull);
      final split = GameEngine(roundTrip(one.state));
      one.advanceBy(const Duration(seconds: 1000));
      for (final milliseconds in [
        1,
        239998,
        1,
        12345,
        45678,
        111111,
        350000,
        240866,
      ]) {
        split.advanceBy(Duration(milliseconds: milliseconds));
        final restarted = roundTrip(split.state);
        expect(restarted.toJson(), split.state.toJson());
      }
      expect(split.state.toJson(), one.state.toJson());
      expect(one.state.marsKits, 3);
      expect(
        one.state.claimedRewards.where(
          (key) => key.endsWith(':mars_route_open'),
        ),
        hasLength(1),
      );
      final again = GameEngine(roundTrip(one.state));
      again.advanceBy(Duration.zero);
      expect(again.state.toJson(), one.state.toJson());
    },
  );

  test(
    'lunar supply and elevator discounts require completed operating assets',
    () {
      final state = fresh().state;
      state.research.addAll(['orbital_assembly', 'composite_shielding']);
      expect(state.launchCostReductionPercent, 0);
      district(state, 'moon_outpost', 12);
      district(state, 'moon_spaceport', 13);
      expect(state.launchCostReductionPercent, 15);
      district(state, 'moon_solar', 2);
      expect(state.launchCostReductionPercent, 15);
      district(state, 'moon_extractor', 1);
      expect(state.launchCostReductionPercent, 25);
      district(state, 'space_elevator', 4);
      expect(state.launchCostReductionPercent, 60);
      expect(state.taskCost(GameContent.tasks['launch_contract']!), 32);
      expect(state.taskCost(GameContent.tasks['mars_delivery']!), 88);
      expect(state.taskCost(GameContent.tasks['habitat_kit']!), 260);
      state.facilities['moon'] = false;
      expect(state.launchCostReductionPercent, 35);
      state.facilities['launch'] = false;
      expect(state.launchCostReductionPercent, 0);
    },
  );

  test(
    'discounts change the next payment without changing a paid iteration',
    () {
      final game = fresh();
      expect(game.enqueue('launch_contract', repeats: 2), isNull);
      final plan = game.state.plans.single;
      final paidMoney = game.state.moneyUnits;
      final paidDuration = plan.iterationDurationMs;
      district(game.state, 'space_elevator', 4);
      game.advanceBy(Duration.zero);
      expect(game.state.moneyUnits, paidMoney);
      expect(plan.iterationDurationMs, paidDuration);
      expect(plan.remainingMs, paidDuration);
      final resumed = GameEngine(roundTrip(game.state));
      resumed.advanceBy(Duration(milliseconds: paidDuration));
      final expected =
          paidMoney +
          game.state.netPerMinute * paidDuration +
          52 * -GameState.moneyScale; // Existing balance exceeds its new cap; the reward cannot accumulate.
      expect(resumed.state.moneyUnits, expected);
      expect(resumed.state.plans.single.completedRuns, 1);
      expect(resumed.state.plans.single.status, 'running');
      expect(resumed.state.plans.single.iterationDurationMs, paidDuration);
      final secondRestart = GameEngine(roundTrip(resumed.state));
      secondRestart.advanceBy(Duration.zero);
      expect(secondRestart.state.toJson(), resumed.state.toJson());
    },
  );

  test('space elevator is an optional, researched single construction', () {
    final game = fresh();
    expect(
      game.enqueueDistrict('earth_delta', 4, 'space_elevator'),
      contains('前提研究'),
    );
    game.state.research.add('orbital_assembly');
    expect(
      game.enqueueDistrict('earth_delta', 4, 'space_elevator'),
      contains('前提研究'),
    );
    game.state.research.add('composite_shielding');
    expect(game.enqueueDistrict('earth_delta', 4, 'space_elevator'), isNull);
    expect(game.state.launchCostReductionPercent, 0);
    expect(
      game.enqueueDistrict('earth_delta', 9, 'space_elevator'),
      contains('1基'),
    );
    final plan = game.state.plans.single;
    expect(game.state.plannedCost(plan), 240000);
    game.advanceBy(Duration(milliseconds: plan.remainingMs));
    expect(game.state.launchCostReductionPercent, 35);
    expect(game.upgradeDistrict('earth_delta', 4), contains('最大レベル'));
  });
}
