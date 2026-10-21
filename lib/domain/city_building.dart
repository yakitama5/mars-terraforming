/// Placement metadata references the existing Development asset. It owns no
/// second production, staffing, income or research state.
class BuildingLocation {
  const BuildingLocation({
    required this.cityId,
    required this.plotIndex,
    this.slotIndex = 0,
    this.legacySite = false,
  });
  final String cityId;
  final int plotIndex, slotIndex;
  final bool legacySite;
  Map<String, dynamic> toJson() => {
    'cityId': cityId,
    'plotIndex': plotIndex,
    'slotIndex': slotIndex,
    'legacySite': legacySite,
  };
  factory BuildingLocation.fromJson(Map<String, dynamic> json) =>
      BuildingLocation(
        cityId: json['cityId'] as String,
        plotIndex: json['plotIndex'] as int,
        slotIndex: json['slotIndex'] as int,
        legacySite: json['legacySite'] as bool? ?? false,
      );
}

class MapBuildingDefinition {
  const MapBuildingDefinition({
    required this.id,
    required this.name,
    required this.catalogId,
    required this.description,
    this.allowedPlanets = const ['earth', 'moon', 'mars'],
    this.allowedTerrain = const [],
    this.occupiesWholePlot = false,
    this.workTaskIds = const [],
    this.isBaseLab = false,
  });
  final String id, name, catalogId, description;
  final List<String> allowedPlanets, allowedTerrain, workTaskIds;
  final bool occupiesWholePlot, isBaseLab;
}

class BuildingPreview {
  const BuildingPreview({
    required this.cost,
    required this.durationMs,
    required this.upkeepPerMinute,
    this.blockedReason,
    this.resourceId,
    this.requiredKits = 0,
    this.availableKits = 0,
  });
  final int cost, durationMs, upkeepPerMinute;
  final String? resourceId;
  final int requiredKits, availableKits;
  final String? blockedReason;
  bool get isValid => blockedReason == null;
}

class CityBuildingSnapshot {
  const CityBuildingSnapshot({
    required this.id,
    required this.technologyId,
    required this.catalogId,
    required this.name,
    required this.cityId,
    required this.plotIndex,
    required this.slotIndex,
    required this.legacySite,
    required this.operational,
    required this.occupiesWholePlot,
    this.workState = 'none',
    this.workProgress = 0,
    this.workLabel = '',
    this.vehiclePresent = true,
    this.underConstruction = false,
  });
  final String id, technologyId, catalogId, name, cityId, workState, workLabel;
  final int plotIndex, slotIndex;
  final bool legacySite,
      operational,
      occupiesWholePlot,
      vehiclePresent,
      underConstruction;
  final double workProgress;
}
