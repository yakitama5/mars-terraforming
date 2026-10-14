import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/presentation/city_scene_data.dart';
import 'package:mars_terraforming/rendering/city_scene.dart';

void main() {
  final city = GameContent.cities['earth_delta']!;
  GameEngine ready() {
    final state = GameState.initial(DateTime.utc(2026, 10, 14))..money = 100000;
    state.research.addAll(['urban_planning', 'automated_fabrication']);
    return GameEngine(state);
  }

  test(
    'map snapshots use every saved plot and never create preview districts',
    () {
      final engine = ready();
      final before = jsonEncode(engine.state.toJson());
      for (final definition in GameContent.cities.values) {
        final plots = scenePlotsForCity(engine.state, definition);
        expect(plots, hasLength(definition.plotCount));
        for (var i = 0; i < plots.length; i++) {
          expect(plots[i].index, i);
          expect(plots[i].terrain, definition.terrainAt(i));
          expect(plots[i].districtId, isNull);
          expect(plots[i].level, 0);
          expect(plots[i].workState, SceneWorkState.none);
        }
      }
      expect(jsonEncode(engine.state.toJson()), before);
    },
  );

  test('queued, building, paused and completed structures share the reserved position', () {
    final engine = ready();
    engine.enqueue('factory_contract', repeats: null);
    final contract = engine.state.currentPlanFor('factory')!;
    expect(engine.enqueueDistrict(city.id, 0, 'housing'), isNull);
    final plan = engine.state.districtPlanAt(city.id, 0)!;
    final reserved = scenePlotsForCity(engine.state, city)[0];
    expect(reserved.workState, SceneWorkState.queued);
    expect(reserved.districtId, 'housing');
    expect(reserved.level, 0);
    expect(reserved.workLabel, contains('順番待ち'));
    expect(engine.state.districtAt(city.id, 0), isNull);

    engine.reorderPlan(plan.id, relativeToPlanId: contract.id, before: true);
    engine.advanceBy(Duration(milliseconds: contract.remainingMs));
    expect(
      scenePlotsForCity(engine.state, city)[0].workState,
      SceneWorkState.building,
    );
    expect(scenePlotsForCity(engine.state, city)[0].level, 0);
    engine.setFacilityEnabled('factory', false);
    final paused = scenePlotsForCity(engine.state, city)[0];
    expect(paused.workState, SceneWorkState.building);
    expect(paused.workLabel, contains('設備休止'));
    engine.setFacilityEnabled('factory', true);
    engine.advanceBy(Duration(milliseconds: plan.remainingMs));
    final completed = scenePlotsForCity(engine.state, city)[0];
    expect(completed.workState, SceneWorkState.none);
    expect(completed.level, 1);
    expect(completed.districtId, 'housing');
    expect(scenePlotsForCity(engine.state, city)[1].districtId, isNull);
    expect(
      scenePlotsForCity(
        engine.state,
        GameContent.cities['earth_highland']!,
      )[0].districtId,
      isNull,
    );
  });

  test('upgrade retains its old building until completion and survives save reload', () {
    final engine = ready();
    engine.enqueueDistrict(city.id, 12, 'housing');
    engine.advanceBy(
      Duration(
        milliseconds: engine.state.currentPlanFor('factory')!.remainingMs,
      ),
    );
    engine.upgradeDistrict(city.id, 12);
    final upgrade = engine.state.currentPlanFor('factory')!;
    engine.advanceBy(Duration(milliseconds: upgrade.remainingMs ~/ 2));
    var plot = scenePlotsForCity(engine.state, city)[12];
    expect(plot.level, 1);
    expect(plot.workState, SceneWorkState.building);
    final resumed = GameEngine(
      GameState.fromJson(
        jsonDecode(jsonEncode(engine.state.toJson())) as Map<String, dynamic>,
      ),
    );
    plot = scenePlotsForCity(resumed.state, city)[12];
    expect(plot.level, 1);
    expect(plot.workState, SceneWorkState.building);
    resumed.advanceBy(
      Duration(
        milliseconds: resumed.state.currentPlanFor('factory')!.remainingMs,
      ),
    );
    plot = scenePlotsForCity(resumed.state, city)[12];
    expect(plot.level, 2);
    expect(plot.workState, SceneWorkState.none);
    expect(
      scenePlotsForCity(
        resumed.state,
        city,
      ).where((p) => p.level > 0).map((p) => p.index),
      [12],
    );
  });
}
