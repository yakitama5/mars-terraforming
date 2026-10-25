import 'dart:math' as math;

import '../domain/game_content.dart';
import '../domain/game_state.dart';
import '../rendering/title_scene_snapshot.dart';

/// Reflect completed, saved assets rather than research unlocks or previews.
///
/// There are no saved temperature/pressure values yet. The small green and
/// cloud accents are a title-only future impression from local life-support
/// investment. They neither release gases nor declare outdoor habitability.
TitleSceneSnapshot buildTitleSceneSnapshot(GameState state) {
  final marsCities = GameContent.cities.values
      .where((city) => city.planet == 'mars')
      .map((city) => city.id)
      .toSet();
  final districts = state.districts.values
      .where((district) => marsCities.contains(district.cityId))
      .toList();
  final buildings = [
    for (final cityId in marsCities)
      ...state
          .cityBuildings(cityId)
          .where((building) => !building.underConstruction),
  ];
  final districtHabitats = districts
      .where((district) => district.districtId == 'mars_habitat')
      .length;
  final legacyHabitats = math.max(0, state.marsHabitats - districtHabitats);
  final settlements = {
    ...districts.map((district) => district.cityId),
    ...buildings.map((building) => building.cityId),
    if (legacyHabitats > 0 ||
        (state.marsResidents > 0 && districtHabitats == 0))
      'mars_arcadia',
  };
  final infrastructure = districts.length + buildings.length + legacyHabitats;
  final greenhouses =
      districts
          .where((district) => district.districtId == 'greenhouse')
          .length +
      buildings
          .where((building) => building.technologyId == 'orbital_gardens')
          .length;
  final activeBuildings = buildings
      .where((building) => building.operational)
      .length;
  final activeDistricts = state.facilities['mars'] == true
      ? districts.length
      : 0;
  final gasPlants = buildings
      .where((building) => building.technologyId == 'hydrogen_storage')
      .length;
  final waterPlants = buildings
      .where((building) => building.technologyId == 'water_purification')
      .length;
  final lifeSupport = state.marsResidents > 0 ? 1 : 0;

  // These are bounded art-direction weights, deliberately independent from
  // the game's resource rates, unlock rules and undetermined global ending.
  final greenery = (greenhouses / 12).clamp(0.0, .65);
  final atmosphere =
      (lifeSupport * .08 +
              greenhouses * .025 +
              gasPlants * .04 +
              waterPlants * .02)
          .clamp(0.0, .5);
  final clouds =
      (lifeSupport * .02 +
              greenhouses * .012 +
              waterPlants * .018 +
              gasPlants * .01)
          .clamp(0.0, .16);
  return TitleSceneSnapshot(
    settlementCount: settlements.length,
    infrastructureCount: infrastructure,
    greenhouseCount: greenhouses,
    residentCount: state.marsResidents,
    activity:
        (activeDistricts / 12 +
                activeBuildings / 12 +
                state.marsResidents / 600)
            .clamp(0.0, 1.0),
    greenery: greenery,
    atmosphere: atmosphere,
    cloudCoverage: clouds,
    hasExploration: state.planetUnlocked('mars'),
  );
}
