import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

import '../../tools/verify_progression.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 13);
  GameState copy(GameState state) => GameState.fromJson(
    jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
  );

  test('science stage caps and capped placement deltas use the same rule', () {
    final state = GameState.initial(epoch)..money = 10000000;
    state.research.add('urban_planning');
    for (final index in [0, 1, 5, 9, 12]) {
      final district = DistrictState(
        cityId: 'earth_highland',
        plotIndex: index,
        districtId: 'campus',
      );
      state.districts[district.key] = district;
    }
    final game = GameEngine(state);
    expect(state.researchBonusPercent, 30);
    expect(
      state.districtPreview('earth_highland', 15, 'campus').researchBonusDelta,
      0,
    );
    expect(game.facilityBonusCap('lab'), 30);
    state.research.add('automated_fabrication');
    expect(game.facilityBonusCap('lab'), 45);
    expect(game.facilityBonusCap('factory'), 45);
    expect(game.facilityBonusCap('launch'), 30);
    expect(game.facilityBonusCap('mars'), 30);
    expect(
      state.districtPreview('earth_highland', 15, 'campus').researchBonusDelta,
      6,
    );
    state.research.add('intercity_logistics');
    expect(game.facilityBonusCap('lab'), 60);
    expect(game.facilityBonusCap('launch'), 60);
    expect(game.facilityBonusCap('factory'), 45);
  });

  test('a discovered RP reservation and habitat construction survive split progress and reload', () {
    final state = GameState.initial(epoch)
      ..money = 10000000
      ..marsKits = 1
      ..habitatChoice = 'dome';
    state.research.addAll([
      'life_support',
      'orbital_gardens',
      'nitrifying_biofilters',
      'nutrient_solution_recycling',
    ]);
    state.researchPointUnits =
        (GameContent.researchPointCost('closed_ecology') - 120) *
        GameState.researchPointScale;
    state.achievements.add('first_landing');
    final one = GameEngine(state);
    expect(one.researchRequirementReasons('closed_ecology'), isEmpty);
    expect(one.enqueue('closed_ecology'), isNull);
    final waiting = state.plans.single;
    expect(waiting.status, 'queued');
    expect(waiting.stopReason, contains('研究ポイント待ち'));
    expect(one.enqueueDistrict('mars_arcadia', 2, 'mars_habitat'), isNull);
    final before = state.moneyUnits;
    var split = GameEngine(copy(state));
    one.advanceBy(const Duration(hours: 1));
    for (final seconds in [1, 97, 333, 569, 800, 1800]) {
      split.advanceBy(Duration(seconds: seconds));
      split = GameEngine(copy(split.state));
    }
    expect(split.state.toJson(), one.state.toJson());
    expect(waiting.status, 'completed');
    expect(waiting.completedRuns, 1);
    expect(waiting.iterationDurationMs, 0);
    expect(waiting.remainingMs, 0);
    expect(state.marsHabitats, 1);
    expect(state.research, contains('closed_ecology'));
    expect(state.moneyUnits, lessThan(before));
    expect(one.enqueue('closed_ecology'), isNotNull);
    expect(
      one.researchRequirements('closed_ecology').every((r) => r.isMet),
      isTrue,
    );
  });

  test('legacy habitats count toward city development without adding research demonstration gates', () {
    final state = GameState.initial(epoch)
      ..money = 10000000
      ..marsKits = 2
      ..marsHabitats = 2;
    state.research.addAll([
      'life_support',
      'closed_ecology',
      'local_resources',
      'orbital_logistics',
      'nitrifying_biofilters',
      'nutrient_solution_recycling',
    ]);
    state.achievements.add('first_landing');
    final game = GameEngine(state);
    expect(game.researchRequirementReasons('closed_ecology'), isEmpty);
    expect(game.researchRequirementReasons('regional_habitats'), isEmpty);
    expect(state.developedMarsCityIds, {'mars_arcadia'});
    expect(game.enqueueDistrict('mars_arcadia', 0, 'extractor'), isNull);
    expect(game.enqueueDistrict('mars_elysium', 2, 'extractor'), isNull);
    game.advanceBy(const Duration(hours: 3));
    expect(state.developedMarsCityIds, {'mars_arcadia'});
    game.advanceBy(const Duration(hours: 4));
    expect(state.developedMarsCityIds, {'mars_arcadia', 'mars_elysium'});
    expect(state.marsHabitats, 2);
    expect(state.research, isNot(contains('regional_habitats')));
  });

  test(
    'older completed research remains valid without newly added demonstrations',
    () {
      final state = GameState.initial(epoch)
        ..research.addAll([
          'life_support',
          'closed_ecology',
          'local_resources',
          'regional_habitats',
        ]);
      final loaded = GameEngine(copy(state));
      expect(loaded.state.research, state.research);
      expect(loaded.state.facilityBonusCap('mars'), 60);
      expect(loaded.enqueue('regional_habitats'), isNotNull);
      expect(loaded.state.marsHabitats, 0);
    },
  );

  test(
    'starter work keeps its economics while research uses RP instead of money',
    () {
      final expected = {
        'factory_contract': [90, 40, 220],
        'launch_contract': [120, 80, 360],
        'life_support': [120, 0, 0],
        'habitat_kit': [180, 260, 0],
        'mars_delivery': [180, 220, 0],
        'build_habitat': [120, 200, 0],
        'earth_expansion': [120, 300, 0],
      };
      for (final entry in expected.entries) {
        final task = GameContent.tasks[entry.key]!;
        expect([task.durationSeconds, task.cost, task.reward], entry.value);
      }
    },
  );

  test('a normal funded route reaches all branches through construction and superior contracts', () {
    final result = runProgressionVerification();
    expect(
      result.state.research,
      containsAll([
        'life_support',
        'urban_planning',
        'process_design',
        'cargo_packaging',
        'habitat_operations',
        'automated_fabrication',
        'reusable_launch',
        'orbital_logistics',
        'closed_ecology',
        'local_resources',
        'intercity_logistics',
        'industrial_network',
        'regional_habitats',
      ]),
    );
    expect(result.state.research.length, lessThan(98));
    expect(result.state.developedMarsCityIds, hasLength(2));
    expect(result.state.marsKits, 3);
    expect(result.toJson()['status'], 'passed');
    expect(
      result.milestones.any((item) => item['step'] == 'regional_habitats'),
      isTrue,
    );
  });

  test('public commands fund all six frontiers without changing the established route', () {
    final established = runProgressionVerification();
    final extended = runProgressionVerification(includeFrontiers: true);
    expect(
      extended.milestones.take(established.milestones.length).toList(),
      established.milestones,
    );
    expect(
      extended.state.research,
      containsAll(GameContent.optionalFrontierResearchIds),
    );
    expect(
      extended.state.research.length,
      greaterThan(established.state.research.length),
    );
    expect(extended.state.research.length, lessThan(98));
    expect(extended.state.developedMarsCityIds, hasLength(2));
    expect(extended.state.marsHabitats, 2);
    expect(extended.state.districtCount('mars_lab'), 1);
    expect(extended.state.marsKits, 2);
    expect(
      extended.milestones.any((item) => item['step'] == 'regolith_printing'),
      isTrue,
    );
    expect(extended.toJson()['optionalResearchIncluded'], isTrue);
    expect(
      extended.state.simulatedMs,
      greaterThan(established.state.simulatedMs),
    );
  });
}
