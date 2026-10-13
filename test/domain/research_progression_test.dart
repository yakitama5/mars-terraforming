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

  test('queued research begins automatically after actual habitat completion and survives reload', () {
    final state = GameState.initial(epoch)
      ..money = 10000000
      ..marsKits = 1
      ..habitatChoice = 'dome';
    state.research.add('life_support');
    state.achievements.add('first_landing');
    final one = GameEngine(state);
    expect(
      one.researchRequirementReasons('closed_ecology').single,
      contains('0/1'),
    );
    one.enqueue('closed_ecology');
    final waiting = state.plans.single;
    expect(waiting.status, 'queued');
    expect(waiting.stopReason, contains('実証待ち'));
    one.enqueueDistrict('mars_arcadia', 2, 'mars_habitat');
    final constructionTime = state.currentPlanFor('mars')!.remainingMs;
    final before = state.moneyUnits;
    var split = GameEngine(copy(state));
    one.advanceBy(const Duration(hours: 1));
    for (final seconds in [1, 97, 333, 569, 800, 1800]) {
      split.advanceBy(Duration(seconds: seconds));
      split = GameEngine(copy(split.state));
    }
    expect(split.state.toJson(), one.state.toJson());
    expect(waiting.status, 'running');
    expect(
      waiting.remainingMs,
      GameContent.tasks['closed_ecology']!.durationMs -
          (const Duration(hours: 1).inMilliseconds - constructionTime),
    );
    expect(one.researchRequirementReasons('closed_ecology'), isEmpty);
    expect(state.moneyUnits, lessThan(before));
    expect(
      one.researchRequirements('closed_ecology').every((r) => r.isMet),
      isTrue,
    );
  });

  test('legacy habitats satisfy first settlement but the regional branch still needs another city', () {
    final state = GameState.initial(epoch)
      ..money = 10000000
      ..marsKits = 2
      ..marsHabitats = 2;
    state.research.addAll([
      'life_support',
      'closed_ecology',
      'local_resources',
      'orbital_logistics',
    ]);
    state.achievements.add('first_landing');
    final game = GameEngine(state);
    expect(game.researchRequirementReasons('closed_ecology'), isEmpty);
    expect(state.developedMarsCityIds, {'mars_arcadia'});
    expect(game.researchRequirementReasons('regional_habitats'), hasLength(2));
    game.enqueue('regional_habitats');
    game.enqueueDistrict('mars_arcadia', 0, 'extractor');
    game.enqueueDistrict('mars_elysium', 2, 'extractor');
    game.advanceBy(const Duration(hours: 3));
    expect(
      game.researchRequirementReasons('regional_habitats').single,
      contains('1/2'),
    );
    game.advanceBy(const Duration(hours: 4));
    expect(game.researchRequirementReasons('regional_habitats'), isEmpty);
    expect(state.currentPlanFor('lab')!.taskId, 'regional_habitats');
    expect(state.developedMarsCityIds, {'mars_arcadia', 'mars_elysium'});
    expect(state.marsHabitats, 2);
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

  test('new investments preserve the seven starter definitions', () {
    final expected = {
      'factory_contract': [90, 40, 220],
      'launch_contract': [120, 80, 360],
      'life_support': [120, 180, 0],
      'habitat_kit': [180, 260, 0],
      'mars_delivery': [180, 220, 0],
      'build_habitat': [120, 200, 0],
      'earth_expansion': [120, 300, 0],
    };
    for (final entry in expected.entries) {
      final task = GameContent.tasks[entry.key]!;
      expect([task.durationSeconds, task.cost, task.reward], entry.value);
    }
  });

  test('a normal funded route reaches all branches through construction and superior contracts', () {
    final result = runProgressionVerification();
    expect(result.state.research, hasLength(10));
    expect(result.state.developedMarsCityIds, hasLength(2));
    expect(result.state.marsKits, 3);
    expect(result.toJson()['status'], 'passed');
    expect(result.milestones.last['step'], 'regional_habitats');
  });
}
