import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/research_frontiers.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 16);
  const frontierIds = [
    'oxygen_pilot',
    'radiation_shelters',
    'electric_tugs',
    'surface_fission',
    'orbital_gardens',
    'regolith_printing',
  ];
  GameState copy(GameState state) => GameState.fromJson(
    jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
  );
  GameState developed() {
    final state = GameState.initial(epoch)
      ..money = 10000000
      ..population = 600
      ..researchPointUnits = 100000 * GameState.researchPointScale
      ..marsHabitats = 1
      ..habitatChoice = 'dome';
    state.achievements.addAll(['first_landing', 'dome_habitat']);
    state.research.addAll([
      'life_support',
      'urban_planning',
      'reusable_launch',
      'orbital_logistics',
      'closed_ecology',
      'local_resources',
      'automated_fabrication',
      // Earlier, inexpensive knowledge exposes the chosen optional roots.
      'autonomous_rovers', 'low_gravity_mobility',
      'cargo_packaging', 'methalox_surface_transport', 'lunar_shuttles',
      'relay_communications',
      'deployable_solar_arrays', 'battery_banks', 'hydrogen_storage',
      'habitat_insulation',
      'subsurface_ice_mapping', 'ground_penetrating_radar', 'in_situ_sampling',
      'thermal_water_extraction',
      'water_purification',
      'atmospheric_collection',
      'geopolymer_fabrication', 'process_design',
    ]);
    for (final (city, index, id) in [
      ('earth_delta', 0, 'spaceport'),
      ('earth_delta', 1, 'industry'),
      ('earth_delta', 2, 'housing'),
      ('earth_delta', 3, 'solar'),
      ('earth_delta', 4, 'solar'),
      ('earth_delta', 5, 'solar'),
      ('mars_arcadia', 0, 'greenhouse'),
      ('mars_arcadia', 1, 'mars_lab'),
      ('mars_arcadia', 8, 'extractor'),
    ]) {
      final district = DistrictState(
        cityId: city,
        plotIndex: index,
        districtId: id,
      );
      state.districts[district.key] = district;
    }
    for (final id in [
      'local_resources',
      'atmospheric_collection',
      'urban_planning',
    ]) {
      state.developments.add(id);
      final cityId = GameContent.developmentPlanet(id) == 'mars'
          ? 'mars_arcadia'
          : 'earth_delta';
      state.developmentCityIds[id] = cityId;
      state.developmentEnabled[id] = true;
      if (GameContent.mapBuildingDefinitions.containsKey(id)) {
        state.buildingLocations[id] = BuildingLocation(
          cityId: cityId,
          plotIndex: -1,
          legacySite: true,
        );
      }
    }
    state.connectedGridCities.add('earth_delta');
    state.surveyedSites.addAll(['earth_delta:1', 'earth_delta:2']);
    return state;
  }

  test('optional research graph is acyclic and all effects have playable prerequisites', () {
    final seen = <String>{};
    final active = <String>{};
    void visit(String id) {
      expect(active, isNot(contains(id)), reason: '循環する前提研究: $id');
      if (!seen.add(id)) return;
      active.add(id);
      final task = GameContent.tasks[id];
      expect(task, isNotNull, reason: id);
      expect(task!.unique, isTrue);
      for (final parent in task.prerequisiteIds) {
        visit(parent);
      }
      active.remove(id);
    }

    for (final task in GameContent.tasks.values.where((task) => task.unique)) {
      visit(task.id);
    }
    expect(seen, hasLength(ResearchCatalog.purchasableTechnologies.length));
    for (final id in frontierIds) {
      final task = GameContent.tasks[id]!;
      expect(GameContent.researchTechnologies[id]!.sourceIds, isNotEmpty);
      expect(task.researchPromise, isNotEmpty);
      expect(task.science, contains('成立条件・限界：'));
      expect(task.science, contains('ゲーム上の仮定'));
      expect(GameContent.researchEfficiencyBonuses[id], isNotEmpty);
    }
    // The established path remains viable without buying every side branch.
    for (final id in [
      'regional_habitats',
      'intercity_logistics',
      'industrial_network',
    ]) {
      expect(
        GameContent.tasks[id]!.prerequisiteIds.any(frontierIds.contains),
        isFalse,
      );
    }
  });

  test('six immediate optional unlocks survive split progress and reload without duplicate completion', () {
    final whole = GameEngine(developed());
    for (final id in frontierIds) {
      expect(whole.researchRequirementReasons(id), isEmpty, reason: id);
      expect(whole.enqueue(id), isNull, reason: id);
    }
    var split = GameEngine(copy(whole.state));
    whole.advanceBy(const Duration(days: 3));
    for (final hours in [1, 2, 5, 10, 18, 36]) {
      split.advanceBy(Duration(hours: hours));
      split = GameEngine(copy(split.state));
    }
    expect(split.state.toJson(), whole.state.toJson());
    for (final id in frontierIds) {
      expect(whole.state.research, contains(id));
      expect(whole.enqueue(id), isNotNull);
      expect(
        whole.state.plans.where((plan) => plan.taskId == id),
        hasLength(1),
      );
    }
    final saved = whole.state.toJson();
    final loaded = GameEngine(copy(whole.state));
    loaded.advanceTo(epoch);
    expect(loaded.state.toJson(), saved);
  });

  test(
    'new research keeps paid work fixed and accelerates only the next job',
    () {
      final state = developed();
      final engine = GameEngine(state);
      engine.enqueue('orbital_contract', repeats: 3);
      final launch = state.currentPlanFor('launch')!;
      final paidDuration = launch.remainingMs;
      final before = state.currentTaskDurationMs('orbital_contract');
      state.researchPointUnits =
          GameContent.researchPointCost('electric_tugs') *
          GameState.researchPointScale;
      final money = state.moneyUnits;
      expect(engine.unlockResearch('electric_tugs'), isNull);
      expect(state.research, contains('electric_tugs'));
      expect(launch.remainingMs, paidDuration);
      expect(state.moneyUnits, money);
      expect(state.researchPointUnits, 0);
      expect(launch.iterationDurationMs, paidDuration);
      expect(state.currentTaskDurationMs('orbital_contract'), lessThan(before));
      engine.advanceBy(Duration(milliseconds: launch.remainingMs));
      expect(
        state.currentPlanFor('launch')!.remainingMs,
        state.currentTaskDurationMs('orbital_contract'),
      );
    },
  );

  test('research uses discovered knowledge and RP while retained effects stay within their caps', () {
    final fresh = GameEngine(GameState.initial(epoch));
    expect(fresh.enqueue('electric_tugs'), contains('手掛かり'));
    expect(fresh.enqueue('orbital_gardens'), isNull);
    expect(fresh.state.research, contains('orbital_gardens'));
    expect(fresh.state.marsHabitats, 0);
    expect(fresh.state.developments, isEmpty);
    final state = developed()..research.addAll(frontierIds);
    for (final facility in GameContent.facilities.keys) {
      expect(
        state.facilityBonusPercent(facility),
        lessThanOrEqualTo(state.facilityBonusCap(facility)),
      );
    }
    expect(state.facilityBonusCap('mars'), 45);
    expect(state.facilityBonusCap('launch'), 45);
    expect(state.facilityBonusCap('factory'), 45);
  });

  test(
    'future stories reference playable research with a scientific boundary',
    () {
      expect(ResearchFrontiers.destinations, hasLength(3));
      for (final frontier in ResearchFrontiers.destinations) {
        for (final id in frontier.researchIds) {
          expect(GameContent.tasks[id]?.unique, isTrue, reason: id);
        }
        expect(frontier.scientificBoundary, isNotEmpty);
      }
    },
  );
}
