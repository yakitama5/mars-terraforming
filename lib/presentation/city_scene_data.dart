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
    buildings: [
      for (final building in game.cityBuildings(city.id))
        if (building.plotIndex == index && !building.legacySite)
          _sceneBuilding(building),
    ],
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

List<SceneBuilding> sceneLegacyBuildingsForCity(
  GameState game,
  CityDefinition city,
) => [
  for (final building in game.cityBuildings(city.id))
    if (building.legacySite || building.plotIndex < 0) _sceneBuilding(building),
];

SceneBuilding _sceneBuilding(CityBuildingSnapshot building) => SceneBuilding(
  id: building.id,
  catalogId: building.catalogId,
  name: building.name,
  slotIndex: building.slotIndex,
  operational: building.operational,
  vehiclePresent: building.vehiclePresent,
  occupiesWholePlot: building.occupiesWholePlot,
  workState: !building.underConstruction
      ? SceneWorkState.none
      : switch (building.workState) {
          'running' => SceneWorkState.building,
          'queued' => SceneWorkState.queued,
          _ => SceneWorkState.none,
        },
  workProgress: building.workProgress,
  workLabel: building.workLabel.isEmpty ? null : building.workLabel,
);
