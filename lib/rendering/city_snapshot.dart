import 'package:flutter/foundation.dart';

/// Rendering-only snapshots. Gameplay owns terrain rules, queues and progress.
enum SceneWorkState { none, queued, building }

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
  });

  final int index;
  final String terrain, terrainName;
  final String? districtId, districtName, habitatStyle;
  final int level;
  final SceneWorkState workState;
  final String? workLabel;
  final double workProgress;

  bool get isDeveloped => districtId != null && level > 0;

  String get label =>
      isDeveloped ? '${districtName ?? districtId} Lv.$level' : terrainName;

  bool hasSameModel(ScenePlot other) =>
      index == other.index &&
      terrain == other.terrain &&
      districtId == other.districtId &&
      level == other.level &&
      habitatStyle == other.habitatStyle &&
      workState == other.workState;
}
