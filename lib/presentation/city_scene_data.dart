import '../domain/game_content.dart';
import '../domain/game_state.dart';
import '../rendering/city_scene.dart';
import 'strategy_widgets.dart';

/// Only completed districts and explicitly reserved work enter the map.
/// Camera movement and plot previews never materialize buildings or rewards.
List<ScenePlot> scenePlotsForCity(GameState game, CityDefinition city) => [
  for (var index = 0; index < city.plotCount; index++)
    _scenePlot(game, city, index),
];

ScenePlot _scenePlot(GameState game, CityDefinition city, int index) {
  final district = game.districtAt(city.id, index);
  final plan = game.districtPlanAt(city.id, index);
  final districtId = district?.districtId ?? plan?.definition.districtId;
  return ScenePlot(
    index: index,
    terrain: city.terrainAt(index),
    terrainName: GameContent.terrainNames[city.terrainAt(index)]!,
    districtId: districtId,
    districtName: GameContent.districts[districtId]?.name,
    habitatStyle: districtId == 'mars_habitat' ? game.habitatChoice : null,
    level: district?.level ?? 0,
    workProgress: plan?.progress ?? 0,
    workState: plan == null
        ? SceneWorkState.none
        : plan.status == 'running'
        ? SceneWorkState.building
        : SceneWorkState.queued,
    workLabel: plan == null
        ? null
        : plan.stopReason.isNotEmpty
        ? plan.stopReason
        : plan.status == 'running'
        ? '残り ${gameDuration(plan.remainingMs)}'
        : '建設予約',
  );
}
