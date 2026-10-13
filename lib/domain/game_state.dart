import 'dart:math' as math;

import 'game_content.dart';
import 'district_state.dart';
export 'district_state.dart';

class PlannedTask {
  PlannedTask({
    required this.id,
    required this.taskId,
    this.remainingRepeats = 1,
    this.cityId,
    this.plotIndex,
    this.targetLevel,
  });
  final String id;
  final String taskId;
  final String? cityId;
  final int? plotIndex;
  final int? targetLevel;

  /// Frozen when an iteration pays, including legacy iterations on migration.
  int iterationDurationMs = 0;

  /// Null means an explicitly selected unlimited repeat. Zero means finished.
  int? remainingRepeats;
  int completedRuns = 0;
  String status = 'queued';
  String stopReason = '';
  int remainingMs = 0;
  bool get isFinished => status == 'completed' || status == 'cancelled';

  /// A running single iteration is already paid and has no future queue slot.
  bool get hasFutureRuns =>
      !isFinished &&
      (status != 'running' ||
          remainingRepeats == null ||
          remainingRepeats! > 1);
  TaskDefinition get definition => GameContent.tasks[taskId]!;
  double get progress => status == 'completed'
      ? 1
      : status == 'running'
      ? 1 -
            remainingMs /
                (iterationDurationMs == 0
                    ? definition.durationMs
                    : iterationDurationMs)
      : 0;
  String get repeatLabel =>
      remainingRepeats == null ? '無期限・条件で停止' : '残り$remainingRepeats回';

  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'remainingRepeats': remainingRepeats,
    'completedRuns': completedRuns,
    'status': status,
    'stopReason': stopReason,
    'remainingMs': remainingMs,
    'iterationDurationMs': iterationDurationMs,
    'cityId': cityId,
    'plotIndex': plotIndex,
    'targetLevel': targetLevel,
  };
  factory PlannedTask.fromJson(Map<String, dynamic> json) {
    final taskId = json['taskId'] as String;
    if (!GameContent.tasks.containsKey(taskId)) {
      throw FormatException('未対応の作業: $taskId');
    }
    final plan = PlannedTask(
      id: json['id'] as String,
      taskId: taskId,
      remainingRepeats: json['remainingRepeats'] as int?,
      cityId: json['cityId'] as String?,
      plotIndex: json['plotIndex'] as int?,
      targetLevel: json['targetLevel'] as int?,
    );
    plan.completedRuns = json['completedRuns'] as int;
    plan.status = json['status'] as String;
    plan.stopReason = json['stopReason'] as String;
    plan.remainingMs = json['remainingMs'] as int;
    plan.iterationDurationMs =
        json['iterationDurationMs'] as int? ??
        (plan.status == 'running' ? plan.definition.durationMs : 0);
    if (![
          'queued',
          'running',
          'completed',
          'cancelled',
        ].contains(plan.status) ||
        plan.completedRuns < 0 ||
        plan.remainingMs < 0 ||
        plan.iterationDurationMs < 0 ||
        (plan.status == 'running' &&
            plan.remainingMs > plan.iterationDurationMs) ||
        (plan.remainingRepeats != null && plan.remainingRepeats! < 0) ||
        (!plan.isFinished && plan.remainingRepeats == 0) ||
        (plan.status == 'running' && plan.remainingMs == 0)) {
      throw const FormatException('不正な作業状態');
    }
    if (plan.definition.districtId != null) {
      final city = GameContent.cities[plan.cityId];
      final district = GameContent.districts[plan.definition.districtId]!;
      if (city == null ||
          city.planet != district.planet ||
          plan.plotIndex == null ||
          plan.plotIndex! < 0 ||
          plan.plotIndex! >= city.plotCount ||
          (district.allowedTerrain.isNotEmpty &&
              !district.allowedTerrain.contains(
                city.terrainAt(plan.plotIndex!),
              )) ||
          plan.targetLevel == null ||
          plan.targetLevel! < 1 ||
          plan.targetLevel! > district.maxLevel ||
          plan.remainingRepeats != (plan.status == 'completed' ? 0 : 1) ||
          (plan.definition.isDistrictUpgrade
              ? plan.targetLevel == 1
              : plan.targetLevel != 1)) {
        throw const FormatException('不正な建設先です');
      }
    } else if (plan.cityId != null ||
        plan.plotIndex != null ||
        plan.targetLevel != null) {
      throw const FormatException('作業に不正な建設先があります');
    }
    return plan;
  }
}

/// Entire simulation generation, including the clock anchor and one-time rewards.
/// Flutter, rendering, I/O and wall-clock acquisition are deliberately excluded.
class GameState {
  GameState._();
  static const schemaVersion = 2;
  static const moneyScale = 60000;
  late String worldId;
  late int lastWallClockMs;
  int simulatedMs = 0;

  /// Fixed-point credits: one minute of rate integration is exact even when
  /// the caller advances in irregular millisecond-sized intervals.
  int moneyUnits = GameContent.initialMoney * moneyScale;
  int earthLevel = 1;
  int population = GameContent.initialPopulation;
  int earthKits = 0;
  int marsKits = 0;
  int marsHabitats = 0;
  int marsResidents = 0;
  String? habitatChoice;
  int nextPlanId = 1;
  int contractRevenue = 0;
  final Set<String> research = {};
  final Set<String> achievements = {};
  final Set<String> claimedRewards = {};
  final Map<String, bool> facilities = {
    for (final id in GameContent.facilities.keys) id: true,
  };
  final List<PlannedTask> plans = [];
  final Map<String, DistrictState> districts = {};
  final List<String> log = [];

  factory GameState.initial(DateTime now) {
    final state = GameState._();
    state.lastWallClockMs = now.millisecondsSinceEpoch;
    state.worldId = 'world-${now.microsecondsSinceEpoch}';
    state.log.add('地球の小さな拠点から、火星開発を始めましょう。');
    return state;
  }
  DistrictState? districtAt(String cityId, int plotIndex) =>
      districts['$cityId:$plotIndex'];
  PlannedTask? districtPlanAt(String cityId, int plotIndex) {
    for (final plan in plans) {
      if (!plan.isFinished &&
          plan.cityId == cityId &&
          plan.plotIndex == plotIndex) {
        return plan;
      }
    }
    return null;
  }

  bool cityUnlocked(String cityId) => cityLockReason(cityId) == null;
  String? cityLockReason(String cityId) {
    final city = GameContent.cities[cityId];
    if (city == null) return '都市が見つかりません';
    if (city.planet == 'mars' && !achievements.contains('first_landing')) {
      return '初回の火星輸送が必要';
    }
    if (city.requiredResearch != null &&
        !research.contains(city.requiredResearch)) {
      return '前提研究：${GameContent.tasks[city.requiredResearch]!.name}';
    }
    return null;
  }

  DistrictEffects get districtEffects => _districtEffects(districts);
  int facilityBonusCap(String facilityId) {
    final branch = GameContent.facilityResearchBranches[facilityId];
    var stage = 0;
    for (final id in research) {
      final task = GameContent.tasks[id];
      if (task != null &&
          task.unique &&
          (facilityId == 'lab' || task.researchBranch == branch)) {
        stage = math.max(stage, task.researchStage);
      }
    }
    return GameContent.efficiencyCapsByStage[math.min(
      stage,
      GameContent.efficiencyCapsByStage.length - 1,
    )];
  }

  int researchEfficiencyBonus(String facilityId) => research.fold(
    0,
    (sum, id) =>
        sum + (GameContent.researchEfficiencyBonuses[id]?[facilityId] ?? 0),
  );
  int _cappedEfficiency(String facilityId, int raw) => math.min(
    facilityBonusCap(facilityId),
    raw + researchEfficiencyBonus(facilityId),
  );
  int get researchBonusPercent =>
      _cappedEfficiency('lab', districtEffects.research);
  int get factoryBonusPercent =>
      _cappedEfficiency('factory', districtEffects.factory);
  int get launchBonusPercent =>
      _cappedEfficiency('launch', districtEffects.launch);
  int get marsBonusPercent => _cappedEfficiency('mars', districtEffects.mars);

  int districtCount(String districtId) =>
      districts.values.where((d) => d.districtId == districtId).length;
  Set<String> get developedMarsCityIds {
    final ids = <String>{
      for (final district in districts.values)
        if (GameContent.cities[district.cityId]!.planet == 'mars')
          district.cityId,
    };
    // Existing closed habitats remain part of the first landing settlement.
    // New districts already contribute their own explicit city IDs.
    if (marsHabitats > districtCount('mars_habitat')) ids.add('mars_arcadia');
    return ids;
  }

  int facilityBonusPercent(String facilityId) => switch (facilityId) {
    'lab' => researchBonusPercent,
    'factory' => factoryBonusPercent,
    'launch' => launchBonusPercent,
    'mars' => marsBonusPercent,
    _ => 0,
  };
  int effectiveDurationMs(TaskDefinition task) =>
      _scaledDuration(task.durationMs, task.facilityId);
  int currentTaskDurationMs(String taskId) =>
      effectiveDurationMs(GameContent.tasks[taskId]!);
  int _scaledDuration(int duration, String facilityId) =>
      (duration * 100 + 99 + facilityBonusPercent(facilityId)) ~/
      (100 + facilityBonusPercent(facilityId));
  int plannedCost(PlannedTask plan) => plan.definition.districtId == null
      ? plan.definition.cost
      : GameContent.districts[plan.definition.districtId]!.costForLevel(
          plan.targetLevel!,
        );
  int plannedDurationMs(PlannedTask plan) => plan.definition.districtId == null
      ? effectiveDurationMs(plan.definition)
      : _scaledDuration(
          GameContent.districts[plan.definition.districtId]!.durationMsForLevel(
            plan.targetLevel!,
          ),
          plan.definition.facilityId,
        );

  DistrictPreview districtPreview(
    String cityId,
    int plotIndex,
    String districtId, {
    bool upgrade = false,
  }) {
    final city = GameContent.cities[cityId];
    final definition = GameContent.districts[districtId];
    final current = districtAt(cityId, plotIndex);
    final level = upgrade ? (current?.level ?? 0) + 1 : 1;
    String? reason;
    if (city == null ||
        definition == null ||
        plotIndex < 0 ||
        plotIndex >= city.plotCount) {
      reason = '都市・区画・地区を選択してください';
    } else if (city.planet != definition.planet) {
      reason = 'この惑星には配置できません';
    } else if (!cityUnlocked(cityId)) {
      reason = cityLockReason(cityId);
    } else if (districtPlanAt(cityId, plotIndex) != null) {
      reason = 'この区画は建設・増強を予約済みです';
    } else if (upgrade &&
        (current == null || current.districtId != districtId)) {
      reason = '増強する地区がありません';
    } else if (!upgrade && current != null) {
      reason = 'この区画は使用中です';
    } else if (level > definition.maxLevel) {
      reason = 'この地区は最大レベルです';
    } else if (definition.allowedTerrain.isNotEmpty &&
        !definition.allowedTerrain.contains(city.terrainAt(plotIndex))) {
      reason =
          '必要な地形：${definition.allowedTerrain.map((t) => GameContent.terrainNames[t]).join('・')}';
    } else if (definition.requiredResearch != null &&
        !research.contains(definition.requiredResearch)) {
      reason = '前提研究：${GameContent.tasks[definition.requiredResearch]!.name}';
    } else if (districtId == 'mars_habitat' && habitatChoice == null) {
      reason = '居住方式を選択してください';
    } else if (upgrade) {
      final required = city.planet == 'earth'
          ? (level == 2 ? 'automated_fabrication' : 'industrial_network')
          : (level == 2 ? 'local_resources' : 'regional_habitats');
      if (!research.contains(required)) {
        reason = '前提研究：${GameContent.tasks[required]!.name}';
      }
    }
    var delta = const DistrictEffects();
    final bonuses = <String>[];
    if (city != null &&
        definition != null &&
        plotIndex >= 0 &&
        plotIndex < city.plotCount) {
      final after = Map<String, DistrictState>.of(districts);
      final proposed = DistrictState(
        cityId: cityId,
        plotIndex: plotIndex,
        districtId: districtId,
        level: level,
      );
      after[proposed.key] = proposed;
      final beforeEffects = districtEffects;
      final afterEffects = _districtEffects(after);
      delta = afterEffects - beforeEffects;
      bonuses.add('地形：${GameContent.terrainNames[city.terrainAt(plotIndex)]}');
      for (final neighbor in city.adjacentPlots(plotIndex)) {
        final district = districtAt(cityId, neighbor);
        if (district != null) {
          bonuses.add(
            '隣接：${GameContent.districts[district.districtId]!.name} Lv.${district.level}',
          );
        }
      }
      if (bonuses.length == 1) bonuses.add('隣接地区なし');
      if (facilities[definition.operatingFacilityId] != true) {
        bonuses.add('設備休止中：再開後に地区の効果が有効');
      }
      // Include the current research-stage cap in each displayed delta.
      int change(String facilityId, int before, int after) =>
          _cappedEfficiency(facilityId, after) -
          _cappedEfficiency(facilityId, before);
      delta = DistrictEffects(
        tax: delta.tax,
        upkeep: delta.upkeep,
        research: change('lab', beforeEffects.research, afterEffects.research),
        factory: change('factory', beforeEffects.factory, afterEffects.factory),
        launch: change('launch', beforeEffects.launch, afterEffects.launch),
        mars: change('mars', beforeEffects.mars, afterEffects.mars),
      );
    }
    return DistrictPreview(
      cost: definition?.costForLevel(level) ?? 0,
      durationMs: definition == null
          ? 0
          : _scaledDuration(
              definition.durationMsForLevel(level),
              definition.planet == 'earth' ? 'factory' : 'mars',
            ),
      targetLevel: level,
      taxDeltaPerMinute: delta.tax,
      upkeepDeltaPerMinute: delta.upkeep,
      researchBonusDelta: delta.research,
      factoryBonusDelta: delta.factory,
      launchBonusDelta: delta.launch,
      marsBonusDelta: delta.mars,
      bonuses: bonuses,
      blockedReason: reason,
    );
  }

  DistrictEffects _districtEffects(Map<String, DistrictState> layout) {
    var result = const DistrictEffects();
    for (final district in layout.values) {
      final definition = GameContent.districts[district.districtId]!;
      if (facilities[definition.operatingFacilityId] != true) continue;
      final city = GameContent.cities[district.cityId]!;
      final terrain = city.terrainAt(district.plotIndex);
      final neighbors = [
        for (final index in city.adjacentPlots(district.plotIndex))
          if (layout['${city.id}:$index'] case final DistrictState neighbor)
            if (facilities[GameContent
                    .districts[neighbor.districtId]!
                    .operatingFacilityId] ==
                true)
              neighbor,
      ];
      int count(Set<String> ids) => neighbors
          .where((n) => ids.contains(n.districtId))
          .fold(0, (sum, n) => sum + n.level);
      final power = neighbors
          .where((n) => n.districtId == 'solar')
          .fold(
            0,
            (sum, n) =>
                sum +
                (city.terrainAt(n.plotIndex) == 'ridge'
                        ? GameContent.solarRidgeEfficiency
                        : GameContent.districtEfficiencyBase['solar']!) *
                    n.level,
          );
      var tax = definition.baseTaxPerMinute;
      var research = 0, factory = 0, launch = 0, mars = 0;
      final baseEfficiency =
          GameContent.districtEfficiencyBase[district.districtId] ?? 0;
      switch (district.districtId) {
        case 'housing':
          tax +=
              (terrain == 'coast' ? 4 : 0) +
              3 * count({'campus'}) -
              3 * count({'industry'});
        case 'campus':
          research =
              baseEfficiency +
              (terrain == 'ridge' ? GameContent.efficiencyTerrainBonus : 0) +
              GameContent.efficiencyAdjacentBonus * count({'housing'}) +
              power;
        case 'industry':
          factory =
              baseEfficiency +
              (terrain == 'mineral' ? GameContent.efficiencyTerrainBonus : 0) +
              GameContent.efficiencyAdjacentBonus * count({'spaceport'}) +
              power;
        case 'spaceport':
          launch =
              baseEfficiency +
              (terrain == 'coast' ? GameContent.efficiencyTerrainBonus : 0) +
              GameContent.efficiencyAdjacentBonus * count({'industry'}) +
              power;
        case 'mars_habitat':
          tax +=
              3 * count({'greenhouse', 'extractor'}) +
              ((habitatChoice == 'dome' && terrain == 'plain') ||
                      (habitatChoice == 'underground' && terrain == 'crater')
                  ? 4
                  : 0);
        case 'greenhouse':
          tax += terrain == 'ice' ? 6 : 0;
          mars = baseEfficiency * count({'mars_habitat'});
        case 'extractor':
          mars = baseEfficiency;
        case 'mars_lab':
          research =
              baseEfficiency +
              (terrain == 'ridge' ? GameContent.efficiencyTerrainBonus : 0) +
              GameContent.efficiencyAdjacentBonus *
                  count({'mars_habitat', 'extractor'});
      }
      final level = district.level;
      result += DistrictEffects(
        tax: math.max(0, tax) * level,
        upkeep: definition.upkeepPerMinute * level,
        research: research * level,
        factory: factory * level,
        launch: launch * level,
        mars: mars * level,
      );
    }
    return result;
  }

  int get money => moneyUnits ~/ moneyScale;
  set money(int value) {
    if (value < 0) throw ArgumentError.value(value, 'money');
    moneyUnits = value * moneyScale;
  }

  int get taxPerMinute =>
      GameContent.baseTaxPerMinute +
      (earthLevel - 1) * GameContent.districtTaxPerMinute +
      districtEffects.tax;
  int get upkeepPerMinute =>
      GameContent.facilities.values
          .where((f) => facilities[f.id]!)
          .fold(0, (sum, f) => sum + f.upkeepPerMinute) +
      districtEffects.upkeep;
  int get netPerMinute => taxPerMinute - upkeepPerMinute;
  int get activePlanCount => plans.where((p) => !p.isFinished).length;
  bool get awaitingHabitatChoice =>
      habitatChoice == null && achievements.contains('first_landing');

  PlannedTask? currentPlanFor(String facilityId) {
    for (final plan in plans) {
      if (plan.definition.facilityId == facilityId &&
          plan.status == 'running') {
        return plan;
      }
    }
    return null;
  }

  /// Ordered starts after the current paid iteration. A repeating running plan
  /// appears here as well as in currentPlanFor, representing only future runs.
  List<PlannedTask> upcomingPlansFor(String facilityId) => plans
      .where((p) => p.definition.facilityId == facilityId && p.hasFutureRuns)
      .toList(growable: false);

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'contentVersion': GameContent.version,
    'worldId': worldId,
    'lastWallClockMs': lastWallClockMs,
    'simulatedMs': simulatedMs,
    'moneyUnits': moneyUnits,
    'earthLevel': earthLevel,
    'population': population,
    'earthKits': earthKits,
    'marsKits': marsKits,
    'marsHabitats': marsHabitats,
    'marsResidents': marsResidents,
    'habitatChoice': habitatChoice,
    'nextPlanId': nextPlanId,
    'contractRevenue': contractRevenue,
    'research': research.toList(),
    'achievements': achievements.toList(),
    'claimedRewards': claimedRewards.toList(),
    'facilities': Map<String, bool>.of(facilities),
    'plans': plans.map((p) => p.toJson()).toList(),
    'log': List<String>.of(log),
    'districts': districts.values.map((d) => d.toJson()).toList(),
  };

  factory GameState.fromJson(Map<String, dynamic> json) {
    final legacy =
        json['schemaVersion'] == 1 && json['contentVersion'] == 'prototype-1';
    if (!legacy &&
        (json['schemaVersion'] != schemaVersion ||
            json['contentVersion'] != GameContent.version)) {
      throw const FormatException('未対応の保存形式またはコンテンツ版です。元のデータを保持してください。');
    }
    final state = GameState._();
    state.worldId = json['worldId'] as String;
    state.lastWallClockMs = json['lastWallClockMs'] as int;
    state.simulatedMs = json['simulatedMs'] as int;
    state.moneyUnits = json['moneyUnits'] as int;
    state.earthLevel = json['earthLevel'] as int;
    state.population = json['population'] as int;
    state.earthKits = json['earthKits'] as int;
    state.marsKits = json['marsKits'] as int;
    state.marsHabitats = json['marsHabitats'] as int;
    state.marsResidents = json['marsResidents'] as int;
    state.habitatChoice = json['habitatChoice'] as String?;
    state.nextPlanId = json['nextPlanId'] as int;
    state.contractRevenue = json['contractRevenue'] as int;
    state.research.addAll((json['research'] as List).cast<String>());
    state.achievements.addAll((json['achievements'] as List).cast<String>());
    state.claimedRewards.addAll(
      (json['claimedRewards'] as List).cast<String>(),
    );
    final enabled = Map<String, bool>.from(json['facilities'] as Map);
    if (GameContent.facilities.keys.any((id) => !enabled.containsKey(id))) {
      throw const FormatException('保存に設備がありません');
    }
    state.facilities
      ..clear()
      ..addAll(enabled);
    state.plans.addAll(
      (json['plans'] as List).map(
        (p) => PlannedTask.fromJson(Map<String, dynamic>.from(p as Map)),
      ),
    );
    state.log.addAll((json['log'] as List).cast<String>());
    if (!legacy) {
      for (final item in json['districts'] as List) {
        final district = DistrictState.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
        if (state.districts.containsKey(district.key)) {
          throw const FormatException('同じ区画に地区が重複しています');
        }
        state.districts[district.key] = district;
      }
    }
    final targets = <String>{};
    for (final plan in state.plans.where(
      (p) => !p.isFinished && p.cityId != null,
    )) {
      final key = '${plan.cityId}:${plan.plotIndex}';
      if (!targets.add(key)) throw const FormatException('同じ区画に予約が重複しています');
      final current = state.districts[key];
      if (plan.definition.isDistrictUpgrade
          ? current == null ||
                current.districtId != plan.definition.districtId ||
                current.level + 1 != plan.targetLevel
          : current != null) {
        throw const FormatException('建設予約と地区状態が一致しません');
      }
    }
    if (state.simulatedMs < 0 ||
        state.moneyUnits < 0 ||
        state.earthLevel < 1 ||
        state.population < 0 ||
        state.earthKits < 0 ||
        state.marsKits < 0 ||
        state.marsHabitats < 0 ||
        state.marsResidents < 0 ||
        state.nextPlanId < 1 ||
        (state.habitatChoice != null &&
            !['dome', 'underground'].contains(state.habitatChoice)) ||
        state.plans.map((p) => p.id).toSet().length != state.plans.length) {
      throw const FormatException('保存された進行状態が不正です');
    }
    for (final id in GameContent.facilities.keys) {
      if (state.plans
              .where(
                (p) => p.definition.facilityId == id && p.status == 'running',
              )
              .length >
          1) {
        throw const FormatException('同じ設備で複数の作業が実行されています');
      }
    }
    return state;
  }
}
