import 'package:flutter/foundation.dart';

/// Rendering-only snapshots. Gameplay owns terrain rules, queues and progress.
enum SceneWorkState { none, queued, building }

/// A physical installation supplied by presentation, without gameplay logic.
@immutable
class SceneBuilding {
  const SceneBuilding({
    required this.id,
    required this.catalogId,
    required this.name,
    required this.slotIndex,
    this.operational = false,
    this.vehiclePresent = true,
    this.occupiesWholePlot = false,
    this.workState = SceneWorkState.none,
    this.workProgress = 0,
    this.workLabel,
  });

  final String id, catalogId, name;
  final int slotIndex;
  final bool operational, vehiclePresent, occupiesWholePlot;
  final SceneWorkState workState;
  final double workProgress;
  final String? workLabel;
  bool get isBuilt => workState == SceneWorkState.none;
  int get constructionStage => (workProgress.clamp(0, .999) * 3).floor();

  bool hasSameModel(SceneBuilding other) =>
      id == other.id &&
      catalogId == other.catalogId &&
      slotIndex == other.slotIndex &&
      operational == other.operational &&
      vehiclePresent == other.vehiclePresent &&
      occupiesWholePlot == other.occupiesWholePlot &&
      workState == other.workState &&
      constructionStage == other.constructionStage;
}

@immutable
class ScenePlot {
  const ScenePlot({
    required this.index,
    required this.terrain,
    required this.terrainName,
    this.districtId,
    this.districtName,
    this.habitatStyle,
    this.level = 0,
    this.workState = SceneWorkState.none,
    this.workLabel,
    this.workProgress = 0,
    this.buildings = const [],
  });

  final List<SceneBuilding> buildings;
  final int index;
  final String terrain, terrainName;
  final String? districtId, districtName, habitatStyle;
  final int level;
  final SceneWorkState workState;
  final String? workLabel;
  final double workProgress;

  bool get isDeveloped => districtId != null && level > 0;

  String get label => [
    if (isDeveloped) '${districtName ?? districtId} Lv.$level',
    for (final building in buildings) building.name,
    if (!isDeveloped && buildings.isEmpty) terrainName,
  ].join('・');

  bool hasSameModel(ScenePlot other) =>
      index == other.index &&
      terrain == other.terrain &&
      districtId == other.districtId &&
      level == other.level &&
      habitatStyle == other.habitatStyle &&
      workState == other.workState &&
      buildings.length == other.buildings.length &&
      buildings.asMap().entries.every(
        (entry) => entry.value.hasSameModel(other.buildings[entry.key]),
      );
}
