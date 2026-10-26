import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 13);
  GameState copy(GameState state) => GameState.fromJson(
    jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
  );
  GameEngine ready() {
    final state = GameState.initial(epoch)..money = 10000000;
    state.research.addAll(['urban_planning', 'life_support']);
    return GameEngine(state);
  }

  test(
    'six finite cities use symmetric six-neighbor hexes without wrapping',
    () {
      expect(
        GameContent.cities.values.where((c) => c.planet == 'earth'),
        hasLength(2),
      );
      expect(
        GameContent.cities.values.where((c) => c.planet == 'mars'),
        hasLength(3),
      );
      expect(
        GameContent.cities.values.where((c) => c.planet == 'moon'),
        hasLength(1),
      );
      for (final city in GameContent.cities.values) {
        expect(city.terrain, hasLength(city.plotCount));
        expect(city.plotCount, 25);
        for (var index = 0; index < city.plotCount; index++) {
          final neighbors = city.adjacentPlots(index);
          expect(neighbors.length, lessThanOrEqualTo(6));
          expect(neighbors.toSet().length, neighbors.length);
          expect(neighbors, isNot(contains(index)));
          for (final neighbor in neighbors) {
            expect(city.adjacentPlots(neighbor), contains(index));
          }
        }
        expect(city.adjacentPlots(0), isNot(contains(4)));
      }
    },
  );

  test(
    'placement preview includes terrain and changes to adjacent districts',
    () {
      final game = ready();
      final coastal = game.state.districtPreview('earth_delta', 0, 'housing');
      final inland = game.state.districtPreview('earth_delta', 2, 'housing');
      expect(coastal.taxDeltaPerMinute, 16);
      expect(inland.taxDeltaPerMinute, 12);
      expect(game.enqueueDistrict('earth_delta', 2, 'housing'), isNull);
      game.advanceBy(Duration(milliseconds: inland.durationMs));
      final campus = game.state.districtPreview('earth_delta', 3, 'campus');
      expect(campus.researchBonusDelta, 5);
      expect(campus.taxDeltaPerMinute, 3);
      final tax = game.state.taxPerMinute;
      final upkeep = game.state.upkeepPerMinute;
      expect(game.enqueueDistrict('earth_delta', 3, 'campus'), isNull);
      game.advanceBy(Duration(milliseconds: campus.durationMs));
      expect(game.state.taxPerMinute - tax, campus.taxDeltaPerMinute);
      expect(game.state.upkeepPerMinute - upkeep, campus.upkeepDeltaPerMinute);
      expect(game.state.researchBonusPercent, campus.researchBonusDelta);
      final solar = game.state.districtPreview('earth_delta', 4, 'solar');
      expect(solar.researchBonusDelta, 3); // High ridge next to campus.
      expect(
        game.state
            .districtPreview('earth_delta', 6, 'industry')
            .taxDeltaPerMinute,
        -3,
      );
      expect(game.state.population, 180);
      expect(
        game.state.earthLevel,
        1,
      ); // New districts never double-count legacy tax.
    },
  );

  test(
    'invalid planet, terrain, locked city and duplicate plot are rejected',
    () {
      final game = ready();
      expect(game.enqueueDistrict('earth_delta', -1, 'housing'), isNotNull);
      expect(game.enqueueDistrict('earth_delta', 25, 'housing'), isNotNull);
      expect(game.enqueueDistrict('earth_delta', 0, 'mars_habitat'), isNotNull);
      expect(
        game.enqueueDistrict('mars_arcadia', 0, 'extractor'),
        contains('火星探査機'),
      );
      game.state.achievements.add('first_landing');
      game.state.research.add('local_resources');
      expect(
        game.enqueueDistrict('mars_arcadia', 2, 'extractor'),
        contains('地形'),
      );
      expect(
        game.enqueueDistrict('mars_hellas', 0, 'mars_habitat'),
        contains('前提研究'),
      );
      expect(game.enqueue('district_housing'), contains('区画'));
      expect(game.enqueueDistrict('earth_delta', 0, 'housing'), isNull);
      expect(game.enqueueDistrict('earth_delta', 0, 'solar'), contains('予約済み'));
      game.advanceBy(const Duration(minutes: 10));
      expect(game.enqueueDistrict('earth_delta', 0, 'solar'), contains('使用中'));
    },
  );

  test(
    'construction requires a free factory and paid work remains protected',
    () {
      final game = ready();
      game.enqueue('factory_contract', repeats: null);
      final paid = game.state.currentPlanFor('factory')!;
      final before = game.state.toJson();
      expect(
        game.enqueueDistrict('earth_delta', 0, 'housing'),
        contains('作業中'),
      );
      expect(game.state.toJson(), before);
      expect(game.cancelQueued(paid.id), isNull);
      game.advanceBy(Duration(milliseconds: paid.remainingMs));
      expect(game.enqueueDistrict('earth_delta', 0, 'solar'), isNull);
      final building = game.state.plans.last;
      expect(building.status, 'running');
      expect(game.cancelQueued(building.id), isNull);
      expect(
        game.enqueueDistrict('earth_delta', 0, 'housing'),
        contains('予約済み'),
      );
      game.advanceBy(Duration(milliseconds: building.remainingMs));
      expect(game.state.districtAt('earth_delta', 0)!.districtId, 'solar');
      expect(game.state.currentPlanFor('factory'), isNull);
    },
  );

  test(
    'housing upgrades unlock early, retain level until completion and persist',
    () {
      var game = ready();
      game.state.research.remove('urban_planning');
      game.enqueueDistrict('earth_delta', 0, 'housing');
      game.advanceBy(const Duration(minutes: 10));
      expect(game.upgradeDistrict('earth_delta', 0), contains('前提研究'));
      game.state.research.add('urban_planning');
      final preview = game.state.districtPreview(
        'earth_delta',
        0,
        'housing',
        upgrade: true,
      );
      expect(preview.cost, 613); // 350 × 175%, rounded up to whole Cr.
      expect(preview.taxDeltaPerMinute, 16);
      expect(game.upgradeDistrict('earth_delta', 0), isNull);
      expect(game.state.districtAt('earth_delta', 0)!.level, 1);
      game = GameEngine(copy(game.state));
      expect(game.upgradeDistrict('earth_delta', 0), contains('予約済み'));
      game.advanceBy(Duration(milliseconds: preview.durationMs));
      expect(game.state.districtAt('earth_delta', 0)!.level, 2);
      expect(game.state.population, 240);
      expect(game.state.earthLevel, 1);
      expect(game.upgradeDistrict('earth_delta', 0), contains('前提研究'));
    },
  );

  test('early housing does not unlock other district upgrades', () {
    final game = ready();
    for (final (plot, district) in [
      (0, 'housing'),
      (1, 'solar'),
      (2, 'industry'),
    ]) {
      expect(game.enqueueDistrict('earth_delta', plot, district), isNull);
      final paid = game.state.currentPlanFor('factory')!;
      game.advanceBy(Duration(milliseconds: paid.remainingMs));
    }
    expect(game.state.research, isNot(contains('automated_fabrication')));
    expect(
      game.state
          .districtPreview('earth_delta', 0, 'housing', upgrade: true)
          .blockedReason,
      isNull,
    );
    expect(game.upgradeDistrict('earth_delta', 1), contains('前提研究'));
    expect(game.upgradeDistrict('earth_delta', 2), contains('前提研究'));
    expect(game.upgradeDistrict('earth_delta', 0), isNull);
    game.state.research.add('automated_fabrication');
    game.advanceBy(
      Duration(milliseconds: game.state.currentPlanFor('factory')!.remainingMs),
    );
    expect(game.upgradeDistrict('earth_delta', 1), isNull);
    game.advanceBy(const Duration(hours: 1));
    expect(game.state.districtAt('earth_delta', 0)!.level, 2);
    expect(game.state.districtAt('earth_delta', 1)!.level, 2);
    expect(game.upgradeDistrict('earth_delta', 0), contains('前提研究'));
  });

  test('new efficiency affects future starts but never changes paid legacy research', () {
    var game = ready();
    game.enqueueDistrict('earth_delta', 4, 'campus');
    game.advanceBy(const Duration(minutes: 9));
    // An already-paid v6 research retains its own timer and committed staff;
    // only new research uses the shared RP bank without an extra timer.
    final snapshot = game.state.toJson()..['contentVersion'] = 'district-6';
    (snapshot['plans'] as List).add({
      'id': 'legacy-paid-research',
      'taskId': 'closed_ecology',
      'remainingRepeats': 1,
      'completedRuns': 0,
      'status': 'running',
      'stopReason': '',
      'remainingMs': const Duration(hours: 3).inMilliseconds,
      'iterationDurationMs': const Duration(hours: 3).inMilliseconds,
      'iterationSpecialists': GameContent.baselineDepartmentStaff,
      'cityId': null,
      'plotIndex': null,
      'targetLevel': null,
    });
    game = GameEngine(GameState.fromJson(snapshot));
    final research = game.state.currentPlanFor('lab')!;
    expect(
      research.iterationDurationMs,
      const Duration(hours: 3).inMilliseconds,
    );
    game.advanceBy(const Duration(minutes: 1));
    expect(game.state.researchBonusPercent, 6);
    expect(
      research.iterationDurationMs,
      const Duration(hours: 3).inMilliseconds,
    );
    expect(
      research.remainingMs,
      const Duration(hours: 2, minutes: 59).inMilliseconds,
    );
    final restored = GameEngine(copy(game.state));
    expect(
      restored.state.currentPlanFor('lab')!.iterationDurationMs,
      research.iterationDurationMs,
    );
    restored.advanceBy(Duration(milliseconds: research.remainingMs));
    expect(restored.state.research, contains('closed_ecology'));
    expect(restored.enqueue('train_specialists'), isNotNull);
    expect(restored.state.currentPlanFor('lab'), isNull);
    expect(
      restored.state.researchPointsPerMinute,
      greaterThan(GameContent.baseResearchPointsPerMinute),
    );
  });

  test('legacy world migration preserves paid time, counts, rewards and queue order', () {
    final game = ready();
    game.state.earthLevel = 7;
    game.state.population = 480;
    game.state.marsHabitats = 4;
    game.state.marsResidents = 48;
    game.state.claimedRewards.add(
      '${game.state.worldId}:achievement:dome_habitat',
    );
    game.enqueue('factory_contract', repeats: 3);
    game.enqueue('habitat_kit');
    game.advanceBy(const Duration(seconds: 30));
    final legacy = game.state.toJson()
      ..['schemaVersion'] = 1
      ..['contentVersion'] = 'prototype-1'
      ..remove('districts');
    for (final plan in legacy['plans'] as List) {
      (plan as Map).remove('iterationDurationMs');
      plan.remove('cityId');
      plan.remove('plotIndex');
      plan.remove('targetLevel');
    }
    final migrated = GameEngine(GameState.fromJson(legacy));
    expect(migrated.state.worldId, game.state.worldId);
    expect(migrated.state.moneyUnits, game.state.moneyUnits);
    expect(migrated.state.population, 480);
    expect(migrated.state.earthLevel, 7);
    expect(migrated.state.marsHabitats, 4);
    expect(migrated.state.marsResidents, 48);
    expect(migrated.state.claimedRewards, game.state.claimedRewards);
    expect(migrated.state.districts, isEmpty);
    expect(
      migrated.state.plans.map((p) => p.id),
      game.state.plans.map((p) => p.id),
    );
    expect(migrated.state.plans.first.remainingMs, 60000);
    expect(migrated.state.plans.first.iterationDurationMs, 90000);
    migrated.advanceBy(const Duration(seconds: 60));
    expect(migrated.state.contractRevenue, 220);
    final snapshot = migrated.state.toJson();
    expect(GameEngine(copy(migrated.state)).state.toJson(), snapshot);
  });

  test('districts, research and cargo stay invariant across save and irregular catch-up', () {
    final one = ready();
    one.state.achievements.add('first_landing');
    one.state.habitatChoice = 'underground';
    one.state.marsKits = 8;
    one.state.research.addAll([
      'closed_ecology',
      'local_resources',
      'automated_fabrication',
      'reusable_launch',
      'orbital_logistics',
      ResearchCatalog.idForCatalog('M01'),
      ResearchCatalog.idForCatalog('M17'),
      ResearchCatalog.idForCatalog('M18'),
    ]);
    for (final (city, plot, district) in [
      ('earth_highland', 0, 'campus'),
      ('earth_highland', 1, 'solar'),
      ('earth_highland', 3, 'industry'),
      ('mars_arcadia', 0, 'extractor'),
      ('mars_arcadia', 1, 'mars_habitat'),
      ('mars_arcadia', 5, 'greenhouse'),
      ('mars_elysium', 3, 'mars_habitat'),
    ]) {
      expect(one.enqueueDistrict(city, plot, district), isNull);
      final plan = one.state.plans.last;
      one.advanceBy(Duration(milliseconds: plan.remainingMs));
    }
    one.state.research.addAll(['industrial_network', 'regional_habitats']);
    one.enqueue('precision_contract');
    one.enqueue('factory_contract', repeats: 3);
    one.enqueue('orbital_contract', repeats: 3);
    var split = GameEngine(copy(one.state));
    const total = Duration(days: 4);
    one.advanceTo(epoch.add(total));
    final random = Random(841);
    var elapsed = 0;
    while (elapsed < total.inMilliseconds) {
      elapsed = min(
        total.inMilliseconds,
        elapsed + random.nextInt(4800000) + 1,
      );
      split.advanceTo(epoch.add(Duration(milliseconds: elapsed)));
      split = GameEngine(copy(split.state));
    }
    expect(split.state.toJson(), one.state.toJson());
    expect(one.state.districts, hasLength(7));
    expect(
      one.state.research,
      containsAll(['industrial_network', 'regional_habitats']),
    );
    expect(one.state.marsHabitats, 2);
    expect(one.state.marsResidents, 48);
    final expectedClaims = {
      '${one.state.worldId}:achievement:first_launch',
      '${one.state.worldId}:achievement:underground_habitat',
    };
    expect(one.state.claimedRewards, expectedClaims);
    final beforeBackwards = split.state.simulatedMs;
    split.advanceTo(epoch.subtract(const Duration(days: 1)));
    expect(split.state.simulatedMs, beforeBackwards);
    split.advanceTo(epoch);
    expect(split.state.marsHabitats, 2);
    expect(split.state.claimedRewards, expectedClaims);
  });

  test('district upkeep suspends with its facility and allows financial rebuilding', () {
    final game = ready();
    for (var i = 0; i < 25; i++) {
      final district = DistrictState(
        cityId: 'earth_delta',
        plotIndex: i,
        districtId: 'campus',
        level: 3,
      );
      game.state.districts[district.key] = district;
    }
    expect(game.state.researchBonusPercent, 30);
    game.state.money = 1;
    game.advanceBy(const Duration(days: 2));
    expect(game.state.facilities['lab'], isFalse);
    expect(game.state.researchBonusPercent, 0);
    expect(game.state.money, greaterThan(0));
    expect(game.state.netPerMinute, greaterThanOrEqualTo(0));
  });

  test('corrupt active target duplication and conflicting occupied plots reject load', () {
    final game = ready();
    game.enqueueDistrict('earth_delta', 0, 'housing');
    final snapshot = game.state.toJson();
    final plans = snapshot['plans'] as List;
    plans.add({
      ...Map<String, dynamic>.from(plans.single as Map),
      'id': 'duplicate',
      'status': 'queued',
      'remainingMs': 0,
    });
    expect(() => GameState.fromJson(snapshot), throwsFormatException);
    final second = game.state.toJson();
    (second['districts'] as List).add(
      DistrictState(
        cityId: 'earth_delta',
        plotIndex: 0,
        districtId: 'solar',
      ).toJson(),
    );
    expect(() => GameState.fromJson(second), throwsFormatException);
  });

  test('branch research has staged unlocks and only explicitly requested work proceeds', () {
    final game = ready();
    final research = GameContent.tasks.values.where((t) => t.unique);
    expect(research, hasLength(98));
    expect(research.map((task) => task.researchBranch).toSet(), {
      for (final field in ResearchField.values) field.label,
    });
    expect(
      research
          .where((task) => GameContent.researchPointCost(task.id) >= 24000)
          .length,
      greaterThanOrEqualTo(3),
    );
    expect(
      GameContent.researchPointCost('regional_habitats'),
      greaterThan(GameContent.researchPointCost('life_support')),
    );
    expect(game.state.discoveredResearchIds.length, lessThan(research.length));
    game.advanceBy(const Duration(days: 10));
    expect(game.state.districts, isEmpty);
    expect(game.state.research, {'urban_planning', 'life_support'});
  });
}
