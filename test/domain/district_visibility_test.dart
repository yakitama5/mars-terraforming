import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

void main() {
  GameState fresh() => GameState.initial(DateTime.utc(2026, 10, 21));

  test('research-free construction is visible before space exploration', () {
    final state = fresh();
    for (final district in GameContent.districts.values) {
      expect(
        state.districtResearchUnlocked(district.id),
        district.requiredResearch == null && district.prerequisites.isEmpty,
        reason: district.id,
      );
    }
    expect(state.planetUnlocked('moon'), isFalse);
    expect(state.districtResearchUnlocked('moon_solar'), isTrue);
    expect(state.districtResearchUnlocked('moon_spaceport'), isTrue);
  });

  test('discovery and research reservation do not unlock construction', () {
    final game = GameEngine(fresh());
    game.state.research.add('deployable_solar_arrays');
    expect(game.state.isResearchDiscovered('urban_planning'), isTrue);
    expect(game.state.districtResearchUnlocked('campus'), isFalse);
    expect(game.state.districtResearchUnlocked('industry'), isFalse);
    game.state.plans.add(
      PlannedTask(id: 'old-research', taskId: 'urban_planning')
        ..requiresManualStart = true,
    );
    expect(game.state.plans.last.status, 'queued');
    expect(game.state.districtResearchUnlocked('campus'), isFalse);
    game.state.researchPointUnits =
        GameContent.researchPointCost('urban_planning') *
        GameState.researchPointScale;
    game.state.population = 180;
    game.state.districts['earth_delta:1'] = const DistrictState(
      cityId: 'earth_delta',
      plotIndex: 1,
      districtId: 'solar',
    );
    game.advanceBy(Duration.zero);
    expect(game.state.research, isNot(contains('urban_planning')));
    expect(game.startPlan('old-research'), isNull);
    expect(game.state.research, contains('urban_planning'));
    expect(game.state.districtResearchUnlocked('campus'), isTrue);
    expect(game.state.districtResearchUnlocked('industry'), isTrue);
  });

  for (final first in ['orbital_assembly', 'composite_shielding']) {
    test('space elevator requires both technologies when $first is first', () {
      final state = fresh();
      state.research.add(first);
      expect(state.districtResearchUnlocked('space_elevator'), isFalse);
      state.research.addAll(['orbital_assembly', 'composite_shielding']);
      expect(state.districtResearchUnlocked('space_elevator'), isTrue);
    });
  }

  test('research visibility ignores cash, terrain, buildings and operating conditions', () {
    final state = fresh()
      ..money = 0
      ..research.addAll(['urban_planning', 'life_support', 'local_resources']);
    for (final facility in state.facilities.keys) {
      state.facilities[facility] = false;
    }
    for (
      var plot = 0;
      plot < GameContent.cities['earth_delta']!.plotCount;
      plot++
    ) {
      final district = DistrictState(
        cityId: 'earth_delta',
        plotIndex: plot,
        districtId: 'housing',
      );
      state.districts[district.key] = district;
    }
    expect(state.cityDevelopment('earth_delta').availablePlots, 0);
    expect(state.cityUnlocked('mars_arcadia'), isFalse);
    expect(state.habitatChoice, isNull);
    expect(state.districtResearchUnlocked('campus'), isTrue);
    expect(state.districtResearchUnlocked('moon_outpost'), isTrue);
    expect(state.districtResearchUnlocked('moon_extractor'), isTrue);
    expect(state.districtResearchUnlocked('mars_habitat'), isTrue);
    expect(state.districtResearchUnlocked('extractor'), isTrue);
    expect(state.districtResearchUnlocked('greenhouse'), isFalse);
  });

  test(
    'built and reserved districts do not substitute for completed research',
    () {
      final state = fresh();
      state.districts['earth_delta:7'] = const DistrictState(
        cityId: 'earth_delta',
        plotIndex: 7,
        districtId: 'campus',
      );
      state.plans.add(
        PlannedTask(
          id: 'old-industry',
          taskId: 'district_industry',
          cityId: 'earth_delta',
          plotIndex: 8,
          targetLevel: 1,
        ),
      );
      expect(state.districtResearchUnlocked('campus'), isFalse);
      expect(state.districtResearchUnlocked('industry'), isFalse);
      expect(state.districtAt('earth_delta', 7)?.districtId, 'campus');
      expect(
        state.districtPlanAt('earth_delta', 8)?.definition.districtId,
        'industry',
      );
    },
  );
}
