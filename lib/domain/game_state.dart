import 'dart:math' as math;

import 'game_content.dart';
import 'completion_notice.dart';
export 'completion_notice.dart';
import 'district_state.dart';
export 'district_state.dart';
export 'agency_state.dart';

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

  /// Staff remain committed until this paid iteration completes, even paused.
  int iterationSpecialists = 0;

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
    'iterationSpecialists': iterationSpecialists,
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
    plan.iterationSpecialists =
        json['iterationSpecialists'] as int? ??
        (plan.status == 'running' &&
                ['lab', 'factory'].contains(plan.definition.facilityId)
            ? GameContent.baselineDepartmentStaff
            : 0);
    if (![
          'queued',
          'running',
          'completed',
          'cancelled',
        ].contains(plan.status) ||
        plan.completedRuns < 0 ||
        plan.remainingMs < 0 ||
        plan.iterationDurationMs < 0 ||
        plan.iterationSpecialists < 0 ||
        plan.iterationSpecialists > GameContent.maxSpecialists ||
        (!['lab', 'factory'].contains(plan.definition.facilityId) &&
            plan.iterationSpecialists != 0) ||
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
  int specialistCount = GameContent.initialSpecialists;
  int researchers = GameContent.baselineDepartmentStaff;
  final Map<String, String> partnershipChoices = {};
  int get industrialWorkers => specialistCount - researchers;
  int get reservedResearchers =>
      currentPlanFor('lab')?.iterationSpecialists ?? 0;
  int get reservedIndustrialWorkers =>
      currentPlanFor('factory')?.iterationSpecialists ?? 0;
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
  static const maxCompletionNotices = 48;
  final List<CompletionNotice> completionNotices = [];
  int nextCompletionNoticeId = 1;
  int readCompletionNoticeId = 0;
  bool completionBannersEnabled = true;
  bool tipsEnabled = true;
  bool tutorialHidden = false;
  final Set<String> dismissedTipIds = {};
  Iterable<CompletionNotice> get unreadCompletionNotices =>
      completionNotices.where((notice) => notice.id > readCompletionNoticeId);

  void recordCompletion(PlannedTask plan) {
    // Combine unread repeats of the same reservation, even across other jobs.
    // A new ID makes subsequent completions unread after acknowledgement.
    final previousIndex = completionNotices.indexWhere(
      (notice) =>
          notice.planId == plan.id && notice.id > readCompletionNoticeId,
    );
    final previousCount = previousIndex < 0
        ? 0
        : completionNotices.removeAt(previousIndex).count;
    completionNotices.add(
      CompletionNotice(
        id: nextCompletionNoticeId++,
        planId: plan.id,
        taskId: plan.taskId,
        simulatedMs: simulatedMs,
        count: previousCount + 1,
        cityId: plan.cityId,
        plotIndex: plan.plotIndex,
        targetLevel: plan.targetLevel,
      ),
    );
    if (completionNotices.length > maxCompletionNotices) {
      completionNotices.removeAt(0);
    }
  }

  void markCompletionsRead(int throughId) {
    readCompletionNoticeId = math.max(
      readCompletionNoticeId,
      throughId.clamp(0, nextCompletionNoticeId - 1),
    );
  }

  factory GameState.initial(DateTime now) {
    final state = GameState._();
    state.lastWallClockMs = now.millisecondsSinceEpoch;
    state.worldId = 'world-${now.microsecondsSinceEpoch}';
    state.log.add('地球の小さな拠点から、火星開発を始めましょう。');
    return state;
  }
  String? staffAllocationReason(int count) {
    if (count < 0 || count > specialistCount) return '専門職の総数内で配分してください';
    if (count < reservedResearchers) {
      return '支払済みの研究に$reservedResearchers名を確保中です。完了まで減らせません';
    }
    if (specialistCount - count < reservedIndustrialWorkers) {
      return '支払済みの製造・建設に$reservedIndustrialWorkers名を確保中です。完了まで減らせません';
    }
    return null;
  }

  int staffEfficiencyBonusFor(String facilityId, int researchCount) {
    if (researchCount < 0 || researchCount > specialistCount) {
      throw ArgumentError.value(researchCount, 'researchCount');
    }
    final assigned = switch (facilityId) {
      'lab' => researchCount,
      'factory' => specialistCount - researchCount,
      _ => GameContent.baselineDepartmentStaff,
    };
    return (assigned - GameContent.baselineDepartmentStaff) *
        GameContent.staffEfficiencyPerPerson;
  }

  int staffEfficiencyBonus(String facilityId) =>
      staffEfficiencyBonusFor(facilityId, researchers);
  Iterable<PartnershipChoice> get chosenPartnerships sync* {
    for (final entry in partnershipChoices.entries) {
      yield GameContent.partnerships[entry.key]!.choices.firstWhere(
        (c) => c.id == entry.value,
      );
    }
  }

  int partnershipEfficiencyBonus(String facilityId) => chosenPartnerships.fold(
    0,
    (sum, choice) => sum + (choice.efficiencyBonuses[facilityId] ?? 0),
  );
  AgencyStatus get agencyStatus {
    final levels = districts.values.fold(0, (sum, d) => sum + d.level);
    final marsLevels = districts.values
        .where((d) => GameContent.cities[d.cityId]!.planet == 'mars')
        .fold(0, (sum, d) => sum + d.level);
    final spaceResearch = research
        .where(
          (id) =>
              ['輸送', '居住・現地生産'].contains(GameContent.tasks[id]?.researchBranch),
        )
        .length;
    return AgencyStatus(
      fame: math.min(
        100,
        research.length * 4 +
            districts.length * 2 +
            achievements.length * 8 +
            partnershipChoices.length * 3,
      ),
      technology: math.min(100, research.length * 6 + levels),
      friendship: math.min(
        100,
        10 + chosenPartnerships.fold(0, (sum, c) => sum + c.friendship),
      ),
      spaceContribution: math.min(
        100,
        spaceResearch * 3 +
            achievements.length * 8 +
            marsLevels * 2 +
            chosenPartnerships.fold(0, (sum, c) => sum + c.spaceContribution),
      ),
    );
  }

  String? partnershipLockReason(String id) {
    final event = GameContent.partnerships[id];
    if (event == null) return '未対応の提携です';
    if (partnershipChoices.containsKey(id) ||
        claimedRewards.contains('$worldId:partnership:$id')) {
      return 'この提案は選択済みです';
    }
    if (event.requiredResearch != null &&
        !research.contains(event.requiredResearch)) {
      return '必要研究：${GameContent.tasks[event.requiredResearch]!.name}';
    }
    if (districts.length < event.minimumDistricts) {
      return '完成地区 ${districts.length}/${event.minimumDistricts}区画';
    }
    if (event.requiredDistrict != null &&
        districtCount(event.requiredDistrict!) == 0) {
      return '必要な実証：${GameContent.districts[event.requiredDistrict]!.name}1区画';
    }
    if (event.requiredAchievement != null &&
        !achievements.contains(event.requiredAchievement)) {
      return '必要実績：${GameContent.achievementNames[event.requiredAchievement]}';
    }
    final status = agencyStatus;
    for (final (label, current, required) in [
      ('知名度', status.fame, event.minimumFame),
      ('技術力', status.technology, event.minimumTechnology),
      ('友好度', status.friendship, event.minimumFriendship),
      ('宇宙支援貢献', status.spaceContribution, event.minimumSpaceContribution),
    ]) {
      if (current < required) return '$label $current/$required';
    }
    return null;
  }

  List<PartnershipDefinition> get availablePartnerships => [
    for (final event in GameContent.partnerships.values)
      if (partnershipLockReason(event.id) == null) event,
  ];

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

  CityDevelopmentSummary cityDevelopment(String cityId) {
    final city = GameContent.cities[cityId];
    if (city == null) throw ArgumentError.value(cityId, 'cityId');
    final completed = districts.values.where((d) => d.cityId == cityId);
    final totalLevels = completed.fold(0, (sum, d) => sum + d.level);
    final thresholds = GameContent.cityStageThresholds;
    var stage = 0;
    while (stage + 1 < thresholds.length &&
        totalLevels >= thresholds[stage + 1]) {
      stage++;
    }
    return CityDevelopmentSummary(
      completedPlots: completed.length,
      totalLevels: totalLevels,
      emptyPlots: city.plotCount - completed.length,
      reservedPlots: plans
          .where(
            (p) =>
                !p.isFinished &&
                p.cityId == cityId &&
                p.definition.districtId != null &&
                !p.definition.isDistrictUpgrade,
          )
          .length,
      stageName: GameContent.cityStageNames[stage],
      nextStageAtTotalLevels: stage + 1 < thresholds.length
          ? thresholds[stage + 1]
          : null,
    );
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
    raw +
        researchEfficiencyBonus(facilityId) +
        staffEfficiencyBonus(facilityId) +
        partnershipEfficiencyBonus(facilityId),
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
      : _districtInvestment(
          plan.cityId!,
          GameContent.districts[plan.definition.districtId]!,
          plan.targetLevel!,
          upgrade: plan.definition.isDistrictUpgrade,
        ).cost;
  int plannedDurationMs(PlannedTask plan) => plan.definition.districtId == null
      ? effectiveDurationMs(plan.definition)
      : _scaledDuration(
          _districtInvestment(
            plan.cityId!,
            GameContent.districts[plan.definition.districtId]!,
            plan.targetLevel!,
            upgrade: plan.definition.isDistrictUpgrade,
          ).durationMs,
          plan.definition.facilityId,
        );

  /// Quotes depend on completed plots at the time of starting work. Unpaid
  /// reservations can be reordered; only the first completed plot opens a city.
  /// Running iterations retain their already-paid duration and inventory.
  _DistrictInvestment _districtInvestment(
    String cityId,
    DistrictDefinition definition,
    int level, {
    required bool upgrade,
  }) {
    final city = GameContent.cities[cityId];
    final count = districts.values.where((d) => d.cityId == cityId).length;
    final development = upgrade
        ? 0
        : count * GameContent.newPlotDevelopmentPercent;
    final baseCost = definition.costForLevel(level);
    final baseDuration = definition.durationMsForLevel(level);
    return _DistrictInvestment(
      baseCost: baseCost,
      developmentCost: (baseCost * development + 99) ~/ 100,
      setupCost: !upgrade && count == 0 ? city?.setupCost ?? 0 : 0,
      baseDurationMs: baseDuration,
      developmentDurationMs: (baseDuration * development + 99) ~/ 100,
      setupDurationMs: !upgrade && count == 0
          ? (city?.setupDurationSeconds ?? 0) * 1000
          : 0,
      developmentPercent: 100 + development,
    );
  }

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
      final required = definition.researchForUpgrade(level);
      if (!research.contains(required)) {
        reason = '前提研究：${GameContent.tasks[required]!.name}';
      }
    }
    var delta = const DistrictEffects();
    var rawDelta = const DistrictEffects();
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
      rawDelta = delta;
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
    final investment = definition == null
        ? const _DistrictInvestment()
        : _districtInvestment(cityId, definition, level, upgrade: upgrade);
    return DistrictPreview(
      cost: investment.cost,
      durationMs: definition == null
          ? 0
          : _scaledDuration(
              investment.durationMs,
              definition.planet == 'earth' ? 'factory' : 'mars',
            ),
      baseCost: investment.baseCost,
      developmentCost: investment.developmentCost,
      setupCost: investment.setupCost,
      baseDurationMs: investment.baseDurationMs,
      developmentDurationMs: investment.developmentDurationMs,
      setupDurationMs: investment.setupDurationMs,
      additionalPlots: upgrade ? 0 : 1,
      developmentPercent: investment.developmentPercent,
      rawResearchBonusDelta: rawDelta.research,
      rawFactoryBonusDelta: rawDelta.factory,
      rawLaunchBonusDelta: rawDelta.launch,
      rawMarsBonusDelta: rawDelta.mars,
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
    'specialistCount': specialistCount,
    'researchers': researchers,
    'partnershipChoices': Map<String, String>.of(partnershipChoices),
    'nextPlanId': nextPlanId,
    'contractRevenue': contractRevenue,
    'research': research.toList(),
    'achievements': achievements.toList(),
    'claimedRewards': claimedRewards.toList(),
    'facilities': Map<String, bool>.of(facilities),
    'plans': plans.map((p) => p.toJson()).toList(),
    'log': List<String>.of(log),
    'completionNotices': completionNotices
        .map((notice) => notice.toJson())
        .toList(),
    'nextCompletionNoticeId': nextCompletionNoticeId,
    'readCompletionNoticeId': readCompletionNoticeId,
    'guidancePreferences': {
      'completionBannersEnabled': completionBannersEnabled,
      'tipsEnabled': tipsEnabled,
      'tutorialHidden': tutorialHidden,
      'dismissedTipIds': dismissedTipIds.toList(),
    },
    'districts': districts.values.map((d) => d.toJson()).toList(),
  };

  factory GameState.fromJson(Map<String, dynamic> json) {
    final legacy =
        json['schemaVersion'] == 1 && json['contentVersion'] == 'prototype-1';
    final compatibleDistricts =
        json['schemaVersion'] == schemaVersion &&
        [
          GameContent.version,
          'district-4',
          'district-3',
          'district-2',
        ].contains(json['contentVersion']);
    if (!legacy && !compatibleDistricts) {
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
    final currentAgency = json['contentVersion'] == GameContent.version;
    if (currentAgency) {
      state.specialistCount = json['specialistCount'] as int;
      state.researchers = json['researchers'] as int;
      state.partnershipChoices.addAll(
        Map<String, String>.from(json['partnershipChoices'] as Map),
      );
    }
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
    // Optional additions keep existing saves playable without replaying history.
    if (json.containsKey('completionNotices')) {
      state.completionNotices.addAll(
        (json['completionNotices'] as List).map(
          (item) =>
              CompletionNotice.fromJson(Map<String, dynamic>.from(item as Map)),
        ),
      );
      state.nextCompletionNoticeId = json['nextCompletionNoticeId'] as int;
      state.readCompletionNoticeId = json['readCompletionNoticeId'] as int;
      var previousId = 0;
      for (final notice in state.completionNotices) {
        if (notice.id <= previousId ||
            notice.id >= state.nextCompletionNoticeId ||
            notice.simulatedMs > state.simulatedMs) {
          throw const FormatException('完了通知の順序が不正です');
        }
        previousId = notice.id;
      }
      if (state.completionNotices.length > maxCompletionNotices ||
          state.nextCompletionNoticeId < 1 ||
          state.readCompletionNoticeId < 0 ||
          state.readCompletionNoticeId >= state.nextCompletionNoticeId) {
        throw const FormatException('完了通知の既読位置が不正です');
      }
    }
    if (json['guidancePreferences'] case final Map preferences) {
      state.completionBannersEnabled =
          preferences['completionBannersEnabled'] as bool? ?? true;
      state.tipsEnabled = preferences['tipsEnabled'] as bool? ?? true;
      state.tutorialHidden = preferences['tutorialHidden'] as bool? ?? false;
      state.dismissedTipIds.addAll(
        (preferences['dismissedTipIds'] as List? ?? []).cast<String>(),
      );
    }
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
    if (state.specialistCount < GameContent.initialSpecialists ||
        state.specialistCount > GameContent.maxSpecialists ||
        state.researchers < 0 ||
        state.researchers > state.specialistCount ||
        state.researchers < state.reservedResearchers ||
        state.industrialWorkers < state.reservedIndustrialWorkers) {
      throw const FormatException('専門職の配分・確保人数が不正です');
    }
    for (final entry in state.partnershipChoices.entries) {
      final event = GameContent.partnerships[entry.key];
      if (event == null ||
          !event.choices.any((choice) => choice.id == entry.value) ||
          !state.claimedRewards.contains(
            '${state.worldId}:partnership:${entry.key}',
          )) {
        throw const FormatException('提携の選択・受領記録が不正です');
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

/// Shared calculation used by both the visible preview and actual start.
class _DistrictInvestment {
  const _DistrictInvestment({
    this.baseCost = 0,
    this.developmentCost = 0,
    this.setupCost = 0,
    this.baseDurationMs = 0,
    this.developmentDurationMs = 0,
    this.setupDurationMs = 0,
    this.developmentPercent = 100,
  });
  final int baseCost, developmentCost, setupCost;
  final int baseDurationMs, developmentDurationMs, setupDurationMs;
  final int developmentPercent;
  int get cost => baseCost + developmentCost + setupCost;
  int get durationMs =>
      baseDurationMs + developmentDurationMs + setupDurationMs;
}
