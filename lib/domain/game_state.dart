import 'dart:math' as math;

import 'game_content.dart';
import 'mission_identity.dart';
export 'mission_identity.dart';
import 'completion_notice.dart';
export 'completion_notice.dart';
import 'district_state.dart';
export 'district_state.dart';
export 'agency_state.dart';
import 'first_run_tutorial.dart';
export 'first_run_tutorial.dart';
export 'city_building.dart';

class PlannedTask {
  PlannedTask({
    required this.id,
    required this.taskId,
    this.remainingRepeats = 1,
    this.cityId,
    this.plotIndex,
    this.targetLevel,
    this.developmentCityId,
    this.buildingInstanceId,
    this.buildingPlotIndex,
    this.buildingSlotIndex,
    this.surveyPlotIndex,
    this.relocation = false,
  });
  final String id;
  final String taskId;
  final String? cityId;
  final int? plotIndex;
  final int? targetLevel;
  final String? developmentCityId;
  final String? buildingInstanceId;
  final int? buildingPlotIndex, buildingSlotIndex, surveyPlotIndex;
  final bool relocation;
  Map<String, int> iterationLocalOutputs = {};
  int iterationBatteryUnits = 0;

  /// Frozen when an iteration pays, including legacy iterations on migration.
  int iterationDurationMs = 0;

  /// Staff remain committed until this paid iteration completes, even paused.
  int iterationSpecialists = 0;

  /// Unpaid construction and research saved before v11 require a new explicit
  /// start. The plan retains its destination and never blocks regular work.
  bool requiresManualStart = false;

  bool get isImmediateAction =>
      definition.unique ||
      definition.districtId != null ||
      definition.developmentId != null ||
      relocation ||
      [
        'build_habitat',
        'earth_expansion',
        'relocate_base_lab',
      ].contains(taskId);

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
    'requiresManualStart': requiresManualStart,
    'cityId': cityId,
    'plotIndex': plotIndex,
    'targetLevel': targetLevel,
    'developmentCityId': developmentCityId,
    'buildingInstanceId': buildingInstanceId,
    'buildingPlotIndex': buildingPlotIndex,
    'buildingSlotIndex': buildingSlotIndex,
    'surveyPlotIndex': surveyPlotIndex,
    'relocation': relocation,
    'iterationLocalOutputs': iterationLocalOutputs,
    'iterationBatteryUnits': iterationBatteryUnits,
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
      developmentCityId: json['developmentCityId'] as String?,
      buildingInstanceId: json['buildingInstanceId'] as String?,
      buildingPlotIndex: json['buildingPlotIndex'] as int?,
      buildingSlotIndex: json['buildingSlotIndex'] as int?,
      surveyPlotIndex: json['surveyPlotIndex'] as int?,
      relocation: json['relocation'] as bool? ?? false,
    );
    plan.iterationLocalOutputs = Map<String, int>.from(
      json['iterationLocalOutputs'] as Map? ?? {},
    );
    plan.iterationBatteryUnits = json['iterationBatteryUnits'] as int? ?? 0;
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
    plan.requiresManualStart = json['requiresManualStart'] as bool? ?? false;
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
        (plan.requiresManualStart &&
            (plan.status != 'queued' || !plan.isImmediateAction)) ||
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
    if (plan.definition.developmentId != null) {
      final technologyId = plan.definition.developmentId!;
      final city = GameContent.cities[plan.developmentCityId];
      if (city == null ||
          (plan.buildingPlotIndex != null
              ? GameContent.mapBuildingDefinitions[technologyId]?.allowedPlanets
                        .contains(city.planet) !=
                    true
              : city.planet != GameContent.developmentPlanet(technologyId)) ||
          plan.remainingRepeats != (plan.status == 'completed' ? 0 : 1)) {
        throw const FormatException('設備導入先または反復回数が不正です');
      }
    } else if (plan.definition.buildingTechnologyId != null ||
        plan.relocation) {
      if (plan.buildingInstanceId == null ||
          !GameContent.cities.containsKey(plan.developmentCityId)) {
        throw const FormatException('施設の仕事・移設の対象が不正です');
      }
    } else if (plan.developmentCityId != null) {
      throw const FormatException('作業に不正な設備導入先があります');
    }
    if (plan.iterationBatteryUnits < 0 ||
        plan.iterationBatteryUnits > plan.definition.powerDemand ||
        plan.iterationLocalOutputs.entries.any(
          (e) =>
              !GameContent.buildingResourceNames.containsKey(e.key) ||
              e.value < 0,
        ) ||
        (plan.buildingPlotIndex != null &&
            (plan.buildingPlotIndex! < 0 ||
                plan.buildingPlotIndex! >=
                    GameContent.cities[plan.developmentCityId]!.plotCount ||
                plan.buildingSlotIndex == null ||
                plan.buildingSlotIndex! < 0 ||
                plan.buildingSlotIndex! >= GameContent.buildingSlotCount))) {
      throw const FormatException('施設の位置・入出力が不正です');
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
  static const researchPointScale = 6000000;
  late String worldId;
  late int lastWallClockMs;
  int simulatedMs = 0;

  /// Fixed-point credits: one minute of rate integration is exact even when
  /// the caller advances in irregular millisecond-sized intervals.
  int moneyUnits = GameContent.initialMoney * moneyScale;
  int earthLevel = 1;
  int population = GameContent.initialPopulation;
  int earthKits = 0;
  int moonKits = 0;
  int marsKits = 0;
  int marsHabitats = 0;
  int marsResidents = 0;
  String? habitatChoice;
  int specialistCount = GameContent.initialSpecialists;
  int researchers = GameContent.baselineDepartmentStaff;
  int researchPointUnits =
      GameContent.initialResearchPoints * researchPointScale;
  final Set<String> developments = {};
  final Map<String, bool> developmentEnabled = {};
  final Map<String, int> developmentResearchers = {};
  final Map<String, String> developmentCityIds = {};
  final Map<String, String> developmentTechnologyIds = {};
  final Map<String, BuildingLocation> buildingLocations = {
    'base_lab': const BuildingLocation(
      cityId: 'earth_delta',
      plotIndex: -1,
      legacySite: true,
    ),
  };
  final Map<String, Map<String, int>> cityStocks = {};
  final Set<String> surveyedSites = {};
  final Set<String> connectedGridCities = {};
  final Set<String> preparedVehicles = {};
  int nextBuildingId = 1;
  final Map<String, String> partnershipChoices = {};
  int get industrialWorkers =>
      specialistCount - researchers - developmentWorkers;
  int get developmentWorkers => developments.fold(
    0,
    (sum, id) =>
        sum + (isDevelopmentOperational(id) ? developmentCrewFor(id) : 0),
  );
  int get specializedResearchers => developmentResearchers.entries.fold(
    0,
    (sum, entry) =>
        sum + (isDevelopmentOperational(entry.key) ? entry.value : 0),
  );
  int get minAssignableResearchers =>
      reservedResearchers + specializedResearchers;
  int get maxAssignableResearchers =>
      specialistCount - developmentWorkers - reservedIndustrialWorkers;
  int get labResearchers =>
      math.max(0, researchers - specializedResearchers - reservedResearchers);
  // Specialist fields above remain only for reading old snapshots. Operating
  // capacity now belongs to buildings, not assignable pools of people.
  int get totalPopulation => population + marsResidents;
  int get moneyCapacity =>
      GameContent.moneyBaseCapacity +
      totalPopulation * GameContent.moneyCapacityPerResident;
  int get researchPointCapacity =>
      GameContent.researchPointBaseCapacity +
      totalPopulation * GameContent.researchPointCapacityPerResident;
  bool get isMoneyAtCapacity => moneyUnits >= moneyCapacity * moneyScale;
  bool get isResearchAtCapacity =>
      researchPointUnits >= researchPointCapacity * researchPointScale;

  /// Preserve an older balance above capacity. Only subsequent positive
  /// accrual is limited; normal upkeep and purchases continue to spend it.
  int addMoneyUnits(int amount) {
    final before = moneyUnits;
    if (amount <= 0) {
      moneyUnits = math.max(0, moneyUnits + amount);
    } else {
      moneyUnits += math.min(
        amount,
        math.max(0, moneyCapacity * moneyScale - moneyUnits),
      );
    }
    return moneyUnits - before;
  }

  int addResearchPointUnits(int amount) {
    if (amount < 0) throw ArgumentError.value(amount, 'amount');
    final added = math.min(
      amount,
      math.max(
        0,
        researchPointCapacity * researchPointScale - researchPointUnits,
      ),
    );
    researchPointUnits += added;
    return added;
  }

  double get researchPoints => researchPointUnits / researchPointScale;
  int get researchPointUnitsPerMs => _researchPointUnitsPerMsFor();
  double get researchPointsPerMinute =>
      researchPointUnitsPerMs * 60000 / researchPointScale;
  double get researchPointsPerHour => researchPointsPerMinute * 60;
  double researchPointsPerMinuteForResearchers(int count) =>
      researchPointsPerMinute;
  int _researchPointUnitsPerMsFor() {
    final modifier =
        100 +
        math
            .min(
              facilityBonusCap('lab'),
              districtEffects.research +
                  researchEfficiencyBonus('lab') +
                  partnershipEfficiencyBonus('lab') +
                  developmentEfficiencyBonus('lab'),
            )
            .toInt();
    var rate = facilities['lab']!
        ? GameContent.baseResearchPointsPerMinute * modifier
        : 0;
    for (final id in developments) {
      if (isDevelopmentOperational(id)) {
        rate +=
            GameContent.developmentResearchPointsPerMinute(
              developmentTechnologyId(id),
            ) *
            modifier;
      }
    }
    return rate;
  }

  bool isDevelopmentOperational(String id) =>
      developments.contains(id) &&
      developmentEnabled[id] == true &&
      facilities[developmentFacilityFor(id)] == true;
  int get developmentUpkeepPerMinute => developments.fold(
    0,
    (sum, id) =>
        sum +
        (isDevelopmentOperational(id)
            ? GameContent.developmentUpkeepPerMinute(
                developmentTechnologyId(id),
              )
            : 0),
  );
  int developmentEfficiencyBonus(String facilityId) {
    var result = 0;
    for (final id in developments) {
      if (!isDevelopmentOperational(id)) continue;
      final target = switch (developmentEffectFor(id)) {
        ResearchUnlockEffect.research => 'lab',
        ResearchUnlockEffect.production => 'factory',
        ResearchUnlockEffect.transport => 'launch',
        ResearchUnlockEffect.construction => 'mars',
        ResearchUnlockEffect.income || ResearchUnlockEffect.partnership => '',
      };
      if (target != facilityId) continue;
      result += GameContent.developmentEfficiencyBonus(
        developmentTechnologyId(id),
      );
    }
    return result;
  }

  int get developmentIncomePerMinute => developments.fold(0, (sum, id) {
    if (!isDevelopmentOperational(id) ||
        ![
          ResearchUnlockEffect.income,
          ResearchUnlockEffect.partnership,
        ].contains(developmentEffectFor(id))) {
      return sum;
    }
    return sum +
        GameContent.developmentIncomePerMinute(developmentTechnologyId(id));
  });

  String developmentTechnologyId(String id) =>
      developmentTechnologyIds[id] ?? id;
  String developmentFacilityFor(String id) {
    if (id == 'base_lab') return 'lab';
    final location = buildingLocations[id];
    if (location != null && !location.legacySite) {
      final planet = GameContent.cities[location.cityId]!.planet;
      if (planet == 'moon' || planet == 'mars') return planet;
    }
    return GameContent.developmentFacilityId(developmentTechnologyId(id));
  }

  ResearchUnlockEffect developmentEffectFor(String id) =>
      developmentTechnologyId(id) == 'lunar_shuttles' &&
          buildingLocations[id]?.legacySite == false &&
          GameContent.cities[developmentCityIds[id]]?.planet == 'moon'
      ? ResearchUnlockEffect.transport
      : GameContent.developmentEffect(developmentTechnologyId(id));
  int developmentCrewFor(String id) =>
      developmentTechnologyId(id) == 'lunar_shuttles' &&
          developmentEffectFor(id) == ResearchUnlockEffect.transport
      ? GameContent.mapVehicleCrew
      : GameContent.developmentCrewRequirement(developmentTechnologyId(id));
  int developmentResearchCapacityFor(String id) =>
      developmentTechnologyId(id) == 'lunar_shuttles' &&
          developmentEffectFor(id) == ResearchUnlockEffect.transport
      ? 0
      : GameContent.developmentResearchCapacity(developmentTechnologyId(id));
  bool mapBuildingUnlocked(String id) =>
      GameContent.mapBuildingDefinitions.containsKey(id) &&
      (id == 'base_lab' || research.contains(id));
  int cityStock(String cityId, String resourceId) =>
      cityStocks[cityId]?[resourceId] ?? 0;
  bool isSiteSurveyed(String cityId, int plotIndex) =>
      surveyedSites.contains('$cityId:$plotIndex');
  String siteSurveyReport(String cityId, int plotIndex) {
    final city = GameContent.cities[cityId];
    if (city == null || plotIndex < 0 || plotIndex >= city.plotCount) {
      return '調査する区画を選んでください';
    }
    if (!isSiteSurveyed(cityId, plotIndex)) {
      return '未調査。基本地形は確認でき、詳細調査で現地の適性を記録します。';
    }
    return city.terrainAt(plotIndex) == 'ice'
        ? '氷層の採水適性を確認。ここで開始する現地採水の原水+${GameContent.surveyedIceYieldBonus}/工程。'
        : '地質と搬入条件を記録済み。この区画の調査は完了し、RP報酬の再取得はありません。';
  }

  int cityBatteryCharge(String cityId) => cityStock(cityId, 'charge');
  bool _gridOperational(String cityId) =>
      connectedGridCities.contains(cityId) &&
      developments.any(
        (id) =>
            developmentTechnologyId(id) == 'urban_planning' &&
            developmentCityIds[id] == cityId &&
            isDevelopmentOperational(id),
      );
  int cityPowerSupply(String cityId) =>
      GameContent.baseCityPower +
      (_gridOperational(cityId)
          ? districts.values
                    .where(
                      (d) =>
                          d.cityId == cityId &&
                          ['solar', 'moon_solar'].contains(d.districtId),
                    )
                    .length *
                GameContent.solarDistrictPower
          : 0);
  int cityPowerDemand(String cityId) => plans
      .where(
        (p) =>
            p.status == 'running' &&
            p.developmentCityId == cityId &&
            p.definition.buildingTechnologyId != null,
      )
      .fold(
        0,
        (sum, p) => sum + p.definition.powerDemand - p.iterationBatteryUnits,
      );
  int buildingBatteryRequired(String cityId, TaskDefinition task) => math.max(
    0,
    task.powerDemand -
        math.max(0, cityPowerSupply(cityId) - cityPowerDemand(cityId)),
  );
  int buildingSurveyTarget(String id, [int? target]) {
    if (target != null) return target;
    final location = buildingLocations[id];
    if (location != null && location.plotIndex >= 0) return location.plotIndex;
    final cityId = developmentCityIds[id];
    if (cityId == null) return 0;
    for (var i = 0; i < GameContent.cities[cityId]!.plotCount; i++) {
      if (!isSiteSurveyed(cityId, i)) return i;
    }
    return 0;
  }

  List<TaskDefinition> buildingWorkTasks(String id) {
    final technologyId = developmentTechnologyId(id);
    final definition = GameContent.mapBuildingDefinitions[technologyId];
    if (definition == null || !developments.contains(id)) return const [];
    return [
      for (final taskId in definition.workTaskIds) GameContent.tasks[taskId]!,
      if (technologyId == 'process_design' &&
          research.contains('material_reforming'))
        GameContent.tasks['building_recycle_parts']!,
    ];
  }

  Map<String, int> buildingLocalInputs(String id, TaskDefinition task) {
    final inputs = Map<String, int>.of(task.localInputs);
    if (task.workAction == 'prepareRocket' &&
        cityStock(developmentCityIds[id]!, 'serviceCredit') > 0) {
      inputs.remove('parts');
      inputs['serviceCredit'] = 1;
    }
    return inputs;
  }

  Map<String, int> buildingLocalOutputs(String id, TaskDefinition task) {
    final location = buildingLocations[id];
    final surveyBonus =
        task.workAction == 'mineIce' &&
            location != null &&
            !location.legacySite &&
            isSiteSurveyed(location.cityId, location.plotIndex)
        ? GameContent.surveyedIceYieldBonus
        : 0;
    return {
      for (final e in task.localOutputs.entries)
        e.key: e.value + (e.key == 'rawWater' ? surveyBonus : 0),
    };
  }

  String? buildingWorkLockReason(
    String id,
    String taskId, {
    int? targetPlotIndex,
  }) {
    final task = GameContent.tasks[taskId];
    if (task == null || !buildingWorkTasks(id).any((t) => t.id == taskId)) {
      return 'この施設では実施できない仕事です';
    }
    if (!isDevelopmentOperational(id)) return '施設を稼働してから仕事を予約してください';
    final cityId = developmentCityIds[id]!;
    final city = GameContent.cities[cityId]!;
    final definition =
        GameContent.mapBuildingDefinitions[developmentTechnologyId(id)]!;
    if (!definition.allowedPlanets.contains(city.planet)) {
      return 'この仕事には対応する天体への施設配置が必要です';
    }
    final cityReason = cityLockReason(cityId);
    if (cityReason != null) return cityReason;
    if (task.workAction == 'survey') {
      final target = buildingSurveyTarget(id, targetPlotIndex);
      if (target < 0 || target >= city.plotCount) return '調査する区画を選んでください';
      if (isSiteSurveyed(cityId, target)) return 'この区画の調査は完了しています';
    }
    if (task.workAction == 'grid' && connectedGridCities.contains(cityId)) {
      return 'この都市の配電接続は完了しています';
    }
    if (['prepareRocket', 'prepareShuttle'].contains(task.workAction) &&
        plans.any(
          (p) =>
              p.status == 'running' &&
              p.buildingInstanceId == id &&
              [
                'rocketFlight',
                'shuttleFlight',
              ].contains(p.definition.workAction),
        )) {
      return '機体の帰還を待ってから整備してください';
    }
    if (['prepareRocket', 'prepareShuttle'].contains(task.workAction) &&
        preparedVehicles.contains(id)) {
      return '機体は整備済みです。便を運航してください';
    }
    if (['rocketFlight', 'shuttleFlight'].contains(task.workAction) &&
        !preparedVehicles.contains(id)) {
      return '機体を整備してから運航してください';
    }
    final spaceReason = spaceTaskLockReason(task);
    if (spaceReason != null) return spaceReason;
    for (final e in buildingLocalInputs(id, task).entries) {
      if (cityStock(cityId, e.key) < e.value) {
        return '都市内の${GameContent.buildingResourceNames[e.key]}が${e.value}必要です';
      }
    }
    for (final e in buildingLocalOutputs(id, task).entries) {
      final cap = e.key == 'charge'
          ? GameContent.batteryCapacity
          : GameContent.buildingStockLimit;
      final pending = plans
          .where((p) => p.status == 'running' && p.developmentCityId == cityId)
          .fold(0, (sum, p) => sum + (p.iterationLocalOutputs[e.key] ?? 0));
      if (cityStock(cityId, e.key) + pending + e.value > cap) {
        return '${GameContent.buildingResourceNames[e.key]}の保管上限です';
      }
    }
    final battery = buildingBatteryRequired(cityId, task);
    if (battery > 0 &&
        (task.workAction == 'charge' || cityBatteryCharge(cityId) < battery)) {
      return '電力不足：配電接続または蓄電が必要です（不足$battery）';
    }
    return null;
  }

  Set<int> _occupiedBuildingSlots(
    String cityId,
    int plotIndex, {
    String? ignoreInstance,
    String? ignorePlan,
  }) {
    final result = <int>{};
    for (final e in buildingLocations.entries) {
      if (e.key == ignoreInstance ||
          e.value.legacySite ||
          e.value.cityId != cityId ||
          e.value.plotIndex != plotIndex) {
        continue;
      }
      // A relocating building is shown and reserved only at its destination.
      if (plans.any(
        (p) =>
            p.status == 'running' &&
            p.relocation &&
            p.buildingInstanceId == e.key,
      )) {
        continue;
      }
      final definition =
          GameContent.mapBuildingDefinitions[developmentTechnologyId(e.key)]!;
      if (definition.occupiesWholePlot) {
        result.addAll([0, 1]);
      } else {
        result.add(e.value.slotIndex);
      }
    }
    for (final p in plans.where(
      (p) =>
          !p.isFinished &&
          p.id != ignorePlan &&
          p.buildingInstanceId != ignoreInstance &&
          p.developmentCityId == cityId &&
          p.buildingPlotIndex == plotIndex,
    )) {
      final definition =
          GameContent.mapBuildingDefinitions[p.relocation
              ? developmentTechnologyId(p.buildingInstanceId!)
              : p.definition.developmentId]!;
      if (definition.occupiesWholePlot) {
        result.addAll([0, 1]);
      } else {
        result.add(p.buildingSlotIndex!);
      }
    }
    return result;
  }

  String? _buildingPlacementReason(
    String technologyId,
    String cityId,
    int plotIndex,
    int slotIndex, {
    String? instanceId,
    String? ignorePlan,
  }) {
    final definition = GameContent.mapBuildingDefinitions[technologyId];
    final city = GameContent.cities[cityId];
    if (definition == null || city == null) return '対応する都市と施設を選んでください';
    if (!mapBuildingUnlocked(technologyId)) return '対応する技術の解放が必要です';
    final cityReason = cityLockReason(cityId);
    if (cityReason != null) return cityReason;
    if (!definition.allowedPlanets.contains(city.planet)) {
      return 'この天体には建設できません';
    }
    if (plotIndex < 0 ||
        plotIndex >= city.plotCount ||
        slotIndex < 0 ||
        slotIndex >= GameContent.buildingSlotCount) {
      return '区画と建設枠を選んでください';
    }
    if (definition.occupiesWholePlot && slotIndex != 0) {
      return '大型施設は区画全体を使用します';
    }
    if (definition.allowedTerrain.isNotEmpty &&
        !definition.allowedTerrain.contains(city.terrainAt(plotIndex))) {
      return 'この地形には建設できません';
    }
    if (developments.any(
          (id) =>
              id != instanceId &&
              developmentTechnologyId(id) == technologyId &&
              developmentCityIds[id] == cityId,
        ) ||
        plans.any(
          (p) =>
              !p.isFinished &&
              p.id != ignorePlan &&
              p.buildingInstanceId != instanceId &&
              p.developmentCityId == cityId &&
              p.definition.developmentId == technologyId,
        )) {
      return 'この都市には同系統の施設が導入済み、または予約済みです';
    }
    final occupied = _occupiedBuildingSlots(
      cityId,
      plotIndex,
      ignoreInstance: instanceId,
      ignorePlan: ignorePlan,
    );
    final district = districtAt(cityId, plotIndex);
    if (district != null) {
      if (GameContent.districtOccupiesWholePlot(district.districtId)) {
        occupied.addAll([0, 1]);
      } else {
        occupied.add(0);
      }
    }
    for (final p in plans.where(
      (p) =>
          !p.isFinished &&
          p.id != ignorePlan &&
          p.cityId == cityId &&
          p.plotIndex == plotIndex,
    )) {
      if (GameContent.districtOccupiesWholePlot(p.definition.districtId!)) {
        occupied.addAll([0, 1]);
      } else {
        occupied.add(0);
      }
    }
    if (definition.occupiesWholePlot
        ? occupied.isNotEmpty
        : occupied.contains(slotIndex)) {
      return 'この建設枠は使用中、または予約済みです';
    }
    return null;
  }

  String? buildingPlanLockReason(PlannedTask plan) => _buildingPlacementReason(
    plan.relocation
        ? developmentTechnologyId(plan.buildingInstanceId!)
        : plan.definition.developmentId!,
    plan.developmentCityId!,
    plan.buildingPlotIndex!,
    plan.buildingSlotIndex!,
    instanceId: plan.buildingInstanceId,
    ignorePlan: plan.id,
  );
  String? mapBuildingKitResource(String cityId) =>
      switch (GameContent.cities[cityId]?.planet) {
        'moon' => 'moonKits',
        'mars' => 'marsKits',
        _ => null,
      };
  int resourceAmount(String id) => switch (id) {
    'earthKits' => earthKits,
    'moonKits' => moonKits,
    'marsKits' => marsKits,
    _ => throw ArgumentError.value(id, 'resource'),
  };

  /// Future iterations quote their inputs. A running paid iteration never
  /// enters the start transition again, including after a saved restart.
  Map<String, int> plannedInputResources(PlannedTask plan) {
    final task = plan.definition;
    return {
      if (task.inputResource != null) task.inputResource!: task.inputAmount,
      if (plan.buildingPlotIndex != null &&
          !plan.relocation &&
          task.developmentId != null &&
          mapBuildingKitResource(plan.developmentCityId!) != null)
        mapBuildingKitResource(plan.developmentCityId!)!:
            GameContent.mapBuildingKitRequirement,
    };
  }

  BuildingPreview buildingPreview(
    String id, {
    required String cityId,
    required int plotIndex,
    int slotIndex = 0,
    bool relocation = false,
  }) {
    final existing =
        relocation && (id == 'base_lab' || developments.contains(id));
    final technologyId = developmentTechnologyId(id);
    final location = buildingLocations[id];
    if (!GameContent.mapBuildingDefinitions.containsKey(technologyId)) {
      return const BuildingPreview(
        cost: 0,
        durationMs: 0,
        upkeepPerMinute: 0,
        blockedReason: '対応する施設を選んでください',
      );
    }
    var reason = _buildingPlacementReason(
      technologyId,
      cityId,
      plotIndex,
      slotIndex,
      instanceId: existing ? id : null,
    );
    if (existing &&
        location?.legacySite == false &&
        location?.cityId == cityId &&
        location?.plotIndex == plotIndex &&
        location?.slotIndex == slotIndex) {
      reason = '現在の敷地と同じ位置です';
    }
    if (existing &&
        plans.any((p) => !p.isFinished && p.buildingInstanceId == id)) {
      reason = 'この施設の仕事・建設を終えてから移設してください';
    }
    if (!existing && technologyId == 'base_lab') {
      reason = '基礎研究所は既存の1棟を移設してください';
    }
    final resourceId = !existing && technologyId != 'base_lab'
        ? mapBuildingKitResource(cityId)
        : null;
    return BuildingPreview(
      resourceId: resourceId,
      requiredKits: resourceId == null
          ? 0
          : GameContent.mapBuildingKitRequirement,
      availableKits: resourceId == null ? 0 : resourceAmount(resourceId),
      cost: existing
          ? (location?.legacySite == true || id == 'base_lab'
                ? 0
                : (GameContent.developmentCost(technologyId) +
                          GameContent.buildingRelocationDivisor -
                          1) ~/
                      GameContent.buildingRelocationDivisor)
          : technologyId == 'base_lab'
          ? 0
          : GameContent.developmentCost(technologyId),
      durationMs: existing
          ? GameContent.buildingRelocationDurationMs
          : technologyId == 'base_lab'
          ? 0
          : effectiveDurationMs(
              GameContent.tasks[GameContent.developmentTaskId(technologyId)]!,
            ),
      upkeepPerMinute: id == 'base_lab'
          ? 0
          : GameContent.developmentUpkeepPerMinute(technologyId),
      blockedReason: reason,
    );
  }

  void validateBuildingState() {
    if (nextBuildingId < 1) throw const FormatException('施設番号が不正です');
    for (final e in developmentTechnologyIds.entries) {
      if (!developments.contains(e.key) ||
          !GameContent.mapBuildingDefinitions.containsKey(e.value) ||
          e.value == 'base_lab' ||
          e.key == e.value) {
        throw const FormatException('施設実体と技術の対応が不正です');
      }
    }
    final slots = <String>{};
    final technologies = <String>{};
    for (final e in buildingLocations.entries) {
      final id = e.key;
      final location = e.value;
      final technologyId = developmentTechnologyId(id);
      final definition = GameContent.mapBuildingDefinitions[technologyId];
      final city = GameContent.cities[location.cityId];
      if (definition == null ||
          city == null ||
          (id != 'base_lab' && !developments.contains(id)) ||
          (id != 'base_lab' && developmentCityIds[id] != location.cityId) ||
          location.slotIndex < 0 ||
          location.slotIndex >= GameContent.buildingSlotCount) {
        throw const FormatException('施設の保存位置が不正です');
      }
      if (!technologies.add('${location.cityId}:$technologyId')) {
        throw const FormatException('同じ都市に同系統の施設が重複しています');
      }
      if (location.legacySite) {
        if (location.plotIndex != -1) {
          throw const FormatException('既存敷地の位置が不正です');
        }
        continue;
      }
      if (location.plotIndex < 0 ||
          location.plotIndex >= city.plotCount ||
          !definition.allowedPlanets.contains(city.planet) ||
          (definition.allowedTerrain.isNotEmpty &&
              !definition.allowedTerrain.contains(
                city.terrainAt(location.plotIndex),
              )) ||
          (definition.occupiesWholePlot && location.slotIndex != 0)) {
        throw const FormatException('施設の用地条件が不正です');
      }
      if (plans.any(
        (p) =>
            p.status == 'running' && p.relocation && p.buildingInstanceId == id,
      )) {
        continue;
      }
      final used = definition.occupiesWholePlot ? [0, 1] : [location.slotIndex];
      for (final slot in used) {
        if (!slots.add('${location.cityId}:${location.plotIndex}:$slot')) {
          throw const FormatException('施設の建設枠が重複しています');
        }
      }
    }
    if (!buildingLocations.containsKey('base_lab')) {
      throw const FormatException('基礎研究所がありません');
    }
    for (final id in developments) {
      if (GameContent.mapBuildingDefinitions.containsKey(
            developmentTechnologyId(id),
          ) &&
          !buildingLocations.containsKey(id)) {
        throw const FormatException('施設の位置がありません');
      }
    }
    for (final d in districts.values) {
      for (final slot
          in GameContent.districtOccupiesWholePlot(d.districtId)
              ? [0, 1]
              : [0]) {
        if (!slots.add('${d.cityId}:${d.plotIndex}:$slot')) {
          throw const FormatException('地区と施設の用地が重複しています');
        }
      }
    }
    final technologyTargets = {
      for (final id in developments)
        if (GameContent.mapBuildingDefinitions.containsKey(
          developmentTechnologyId(id),
        ))
          '${developmentCityIds[id]}:${developmentTechnologyId(id)}': id,
    };
    final relocating = plans
        .where((p) => !p.isFinished && p.relocation)
        .map((p) => p.buildingInstanceId)
        .toList();
    if (relocating.toSet().length != relocating.length) {
      throw const FormatException('同じ施設の移設予約が重複しています');
    }
    final pendingSurveys = <String>{};
    final newIds = <String>{};
    for (final p in plans) {
      if (p.status != 'running' &&
          (p.iterationLocalOutputs.isNotEmpty ||
              p.iterationBatteryUnits != 0)) {
        throw const FormatException('未実行の仕事に支払済みの生産量があります');
      }
      if (p.definition.buildingTechnologyId == null &&
          p.buildingPlotIndex == null &&
          (p.buildingInstanceId != null ||
              p.buildingSlotIndex != null ||
              p.surveyPlotIndex != null)) {
        throw const FormatException('作業に不正な施設の参照があります');
      }
      if (p.buildingPlotIndex != null) {
        if (p.buildingInstanceId == null ||
            p.buildingSlotIndex == null ||
            p.developmentCityId == null) {
          throw const FormatException('施設建設の実体が不正です');
        }
        final tech = p.relocation
            ? developmentTechnologyId(p.buildingInstanceId!)
            : p.definition.developmentId;
        final def = GameContent.mapBuildingDefinitions[tech];
        final city = GameContent.cities[p.developmentCityId];
        if (def == null ||
            city == null ||
            !def.allowedPlanets.contains(city.planet) ||
            (def.allowedTerrain.isNotEmpty &&
                !def.allowedTerrain.contains(
                  city.terrainAt(p.buildingPlotIndex!),
                )) ||
            (def.occupiesWholePlot && p.buildingSlotIndex != 0)) {
          throw const FormatException('予約施設の用地条件が不正です');
        }
        if (p.relocation &&
            p.buildingInstanceId != 'base_lab' &&
            !developments.contains(p.buildingInstanceId)) {
          throw const FormatException('移設元の施設がありません');
        }
        if (!p.isFinished) {
          final target = '${p.developmentCityId}:$tech';
          if (technologyTargets.containsKey(target) &&
              technologyTargets[target] != p.buildingInstanceId) {
            throw const FormatException('同じ都市の施設系統が重複しています');
          }
          technologyTargets[target] = p.buildingInstanceId!;
          if (p.remainingRepeats != 1) {
            throw const FormatException('施設工事の反復回数が不正です');
          }
          if (!p.relocation &&
              (!newIds.add(p.buildingInstanceId!) ||
                  developments.contains(p.buildingInstanceId))) {
            throw const FormatException('施設実体の建設予約が重複しています');
          }
          for (final slot
              in def.occupiesWholePlot ? [0, 1] : [p.buildingSlotIndex!]) {
            if (!slots.add(
              '${p.developmentCityId}:${p.buildingPlotIndex}:$slot',
            )) {
              throw const FormatException('施設予約の建設枠が重複しています');
            }
          }
        }
      } else if (p.relocation) {
        throw const FormatException('移設先がありません');
      }
      if (p.definition.buildingTechnologyId != null) {
        final id = p.buildingInstanceId;
        final task = p.definition;
        if (!p.isFinished && relocating.contains(id)) {
          throw const FormatException('移設中の施設に仕事が予約されています');
        }
        if (!p.isFinished &&
            task.workAction == 'survey' &&
            !pendingSurveys.add(
              '${p.developmentCityId}:${p.surveyPlotIndex}',
            )) {
          throw const FormatException('同じ区画の調査予約が重複しています');
        }
        if (id == null ||
            !developments.contains(id) ||
            (!p.isFinished && developmentCityIds[id] != p.developmentCityId) ||
            !buildingWorkTasks(id).any((t) => t.id == task.id) ||
            p.buildingPlotIndex != null) {
          throw const FormatException('施設の仕事の対象が不正です');
        }
        if (task.workAction == 'survey' &&
            (p.surveyPlotIndex == null ||
                p.surveyPlotIndex! < 0 ||
                p.surveyPlotIndex! >=
                    GameContent.cities[p.developmentCityId]!.plotCount ||
                p.remainingRepeats != (p.status == 'completed' ? 0 : 1))) {
          throw const FormatException('調査対象が不正です');
        }
        if (task.workAction != 'survey' && p.surveyPlotIndex != null) {
          throw const FormatException('仕事に不正な調査対象があります');
        }
        for (final output in p.iterationLocalOutputs.entries) {
          if (!task.localOutputs.containsKey(output.key) ||
              output.value >
                  task.localOutputs[output.key]! +
                      (task.workAction == 'mineIce'
                          ? GameContent.surveyedIceYieldBonus
                          : 0)) {
            throw const FormatException('施設の凍結済み生産量が不正です');
          }
        }
      } else if (p.iterationLocalOutputs.isNotEmpty ||
          p.iterationBatteryUnits != 0) {
        throw const FormatException('仕事に不正な都市在庫があります');
      }
    }
    for (final p in plans.where(
      (p) =>
          !p.isFinished && p.cityId != null && !p.definition.isDistrictUpgrade,
    )) {
      for (final slot
          in GameContent.districtOccupiesWholePlot(p.definition.districtId!)
              ? [0, 1]
              : [0]) {
        if (!slots.add('${p.cityId}:${p.plotIndex}:$slot')) {
          throw const FormatException('地区予約と施設の用地が重複しています');
        }
      }
    }
    for (final e in cityStocks.entries) {
      if (!GameContent.cities.containsKey(e.key) ||
          e.value.entries.any(
            (v) =>
                !GameContent.buildingResourceNames.containsKey(v.key) ||
                v.value < 0 ||
                v.value >
                    (v.key == 'charge'
                        ? GameContent.batteryCapacity
                        : GameContent.buildingStockLimit),
          )) {
        throw const FormatException('都市在庫が不正です');
      }
    }
    for (final key in surveyedSites) {
      final parts = key.split(':');
      final city = GameContent.cities[parts.first];
      final plot = parts.length == 2 ? int.tryParse(parts.last) : null;
      if (city == null || plot == null || plot < 0 || plot >= city.plotCount) {
        throw const FormatException('調査記録が不正です');
      }
    }
    if (connectedGridCities.any((id) => !GameContent.cities.containsKey(id)) ||
        preparedVehicles.any(
          (id) =>
              !developments.contains(id) ||
              ![
                'reusable_launch',
                'lunar_shuttles',
              ].contains(developmentTechnologyId(id)) ||
              plans.any(
                (p) =>
                    p.status == 'running' &&
                    p.buildingInstanceId == id &&
                    [
                      'rocketFlight',
                      'shuttleFlight',
                    ].contains(p.definition.workAction),
              ),
        )) {
      throw const FormatException('配電・機体整備の記録が不正です');
    }
  }

  List<CityBuildingSnapshot> cityBuildings(String cityId) {
    final result = <CityBuildingSnapshot>[];
    final ids = <String>{
      if (buildingLocations['base_lab']?.cityId == cityId) 'base_lab',
      ...developments.where(
        (id) =>
            GameContent.mapBuildingDefinitions.containsKey(
              developmentTechnologyId(id),
            ) &&
            developmentCityIds[id] == cityId,
      ),
    };
    for (final id in ids) {
      if (plans.any(
        (p) =>
            p.status == 'running' && p.relocation && p.buildingInstanceId == id,
      )) {
        continue;
      }
      final technologyId = developmentTechnologyId(id);
      final definition = GameContent.mapBuildingDefinitions[technologyId]!;
      final location =
          buildingLocations[id] ??
          BuildingLocation(cityId: cityId, plotIndex: -1, legacySite: true);
      final work = plans
          .where(
            (p) =>
                !p.isFinished &&
                p.buildingInstanceId == id &&
                p.definition.buildingTechnologyId != null,
          )
          .firstOrNull;
      result.add(
        CityBuildingSnapshot(
          id: id,
          technologyId: technologyId,
          catalogId: definition.catalogId,
          name: definition.name,
          cityId: cityId,
          plotIndex: location.plotIndex,
          slotIndex: location.slotIndex,
          legacySite: location.legacySite,
          operational: id == 'base_lab'
              ? facilities['lab'] == true
              : isDevelopmentOperational(id),
          occupiesWholePlot: definition.occupiesWholePlot,
          workState: work?.status ?? 'none',
          workProgress: work?.progress ?? 0,
          workLabel: work?.definition.name ?? '',
          vehiclePresent: !plans.any(
            (p) =>
                p.status == 'running' &&
                p.buildingInstanceId == id &&
                [
                  'rocketFlight',
                  'shuttleFlight',
                ].contains(p.definition.workAction),
          ),
        ),
      );
    }
    for (final p in plans.where(
      (p) =>
          !p.isFinished &&
          p.developmentCityId == cityId &&
          p.buildingPlotIndex != null,
    )) {
      final id = p.buildingInstanceId!;
      final technologyId = p.relocation
          ? developmentTechnologyId(id)
          : p.definition.developmentId!;
      final definition = GameContent.mapBuildingDefinitions[technologyId]!;
      result.add(
        CityBuildingSnapshot(
          id: id,
          technologyId: technologyId,
          catalogId: definition.catalogId,
          name: definition.name,
          cityId: cityId,
          plotIndex: p.buildingPlotIndex!,
          slotIndex: p.buildingSlotIndex!,
          legacySite: false,
          operational: false,
          occupiesWholePlot: definition.occupiesWholePlot,
          workState: p.status,
          workProgress: p.progress,
          workLabel: p.status == 'queued' && p.stopReason.isNotEmpty
              ? p.stopReason
              : p.relocation
              ? '移設中'
              : '建設中',
          underConstruction: true,
        ),
      );
    }
    return result;
  }

  /// Only the explored frontier exists in the UI: unseen roots, descendants,
  /// and graph geometry must never disclose the future shape of a field.
  Set<String> get discoveredResearchIds {
    final visible = <String>{...research, ..._knownResearch};
    for (final technology in ResearchCatalog.purchasableTechnologies) {
      if (GameContent.starterResearchCatalogIds.contains(
        technology.catalogId,
      )) {
        visible.add(technology.id);
        continue;
      }
      if (technology.prerequisiteIds.isEmpty &&
          technology.alternativePrerequisiteIds.isEmpty) {
        if (GameContent.researchDiscoveryParentIds(technology.id)
            .any(research.contains)) {
          visible.add(technology.id);
        }
      } else if (technology.prerequisiteIds.every(research.contains) &&
          (technology.alternativePrerequisiteIds.isEmpty ||
              technology.alternativePrerequisiteIds.any(research.contains))) {
        visible.add(technology.id);
      }
    }
    // Already reserved old research is known to its player and stays inspectable.
    visible.addAll(
      plans
          .where((plan) => plan.definition.unique && !plan.isFinished)
          .map((plan) => plan.taskId),
    );
    return visible.where((id) => GameContent.tasks[id]?.unique == true).toSet();
  }

  /// Before v8, completing any research exposed another independent root.
  /// Restore that historical frontier once when loading, without using it to
  /// discover more roots in a current world.
  Set<String> _legacyDiscoveredResearchIds() {
    final visible = <String>{...research};
    for (final field in ResearchField.values) {
      final technologies = ResearchCatalog.purchasableTechnologies
          .where((technology) => technology.field == field)
          .toList();
      final starter = technologies.firstWhere(
        (technology) => GameContent.starterResearchCatalogIds.contains(
          technology.catalogId,
        ),
      );
      final roots = [
        starter,
        ...technologies.where(
          (technology) =>
              technology.id != starter.id &&
              technology.prerequisiteIds.isEmpty &&
              technology.alternativePrerequisiteIds.isEmpty,
        ),
      ];
      final rootOrder = GameContent.researchRootOrderByField[field]!;
      roots.sort((a, b) {
        final left = rootOrder.indexOf(a.catalogId);
        final right = rootOrder.indexOf(b.catalogId);
        return (left < 0 ? rootOrder.length : left).compareTo(
          right < 0 ? rootOrder.length : right,
        );
      });
      final completed = technologies
          .where((technology) => research.contains(technology.id))
          .length;
      for (var index = 0; index < roots.length && index <= completed; index++) {
        visible.add(roots[index].id);
      }
      for (final technology in technologies) {
        if (technology.prerequisiteIds.isEmpty &&
            technology.alternativePrerequisiteIds.isEmpty) {
          continue;
        }
        if (technology.prerequisiteIds.every(research.contains) &&
            (technology.alternativePrerequisiteIds.isEmpty ||
                technology.alternativePrerequisiteIds.any(research.contains))) {
          visible.add(technology.id);
        }
      }
    }
    // Already reserved old research is known to its player and stays inspectable.
    visible.addAll(
      plans
          .where((plan) => plan.definition.unique && !plan.isFinished)
          .map((plan) => plan.taskId),
    );
    return visible.where((id) => GameContent.tasks[id]?.unique == true).toSet();
  }

  Set<String> get visibleResearchIds => discoveredResearchIds;
  bool isResearchDiscovered(String id) => discoveredResearchIds.contains(id);
  String researchNameForDisplay(String id) => isResearchDiscovered(id)
      ? GameContent.tasks[id]?.name ?? '研究'
      : '研究を進めて手掛かりを探してください';

  int? researchWaitMs(String id) {
    final gap =
        GameContent.researchPointCost(id) * researchPointScale -
        researchPointUnits;
    if (gap <= 0) return 0;
    if (GameContent.researchPointCost(id) > researchPointCapacity) return null;
    final rate = researchPointUnitsPerMs;
    return rate <= 0 ? null : (gap + rate - 1) ~/ rate;
  }

  int get reservedResearchers =>
      currentPlanFor('lab')?.iterationSpecialists ?? 0;
  int get reservedIndustrialWorkers =>
      currentPlanFor('factory')?.iterationSpecialists ?? 0;
  int nextPlanId = 1;
  int contractRevenue = 0;
  final Set<String> research = {};
  final Set<String> _knownResearch = {};
  final Set<String> achievements = {};
  // A v8 reserved Mars operation must remain playable without fabricating lunar
  // facilities or replaying achievement rewards during migration.
  final Set<String> legacyUnlockedPlanets = {};
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
  MissionIdentity identity = const MissionIdentity();
  bool openingSeen = false;
  bool openingStarted = false;
  FirstRunTutorialStep firstRunTutorial = FirstRunTutorialStep.placeHousing;
  String? firstRunTutorialPlanId;

  /// Reading the initial story and compulsory walkthrough never spends the
  /// starter budget. Replays and worlds from before the walkthrough run normally.
  bool get introductionPausesClock =>
      (openingStarted && !openingSeen) ||
      firstRunTutorial != FirstRunTutorialStep.completed;
  String cityName(String cityId) => identity.cityName(cityId);
  String get rocketName => identity.rocketName;
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
    return '人員の育成・配置は不要になりました。施設への投資で能力を伸ばせます';
  }

  int staffEfficiencyBonusFor(String facilityId, int researchCount) {
    return 0;
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
              GameContent.researchTechnologies[id]?.field ==
                  ResearchField.mechanics ||
              [
                '輸送',
                '居住・現地生産',
              ].contains(GameContent.legacyResearchBranchFor(id)),
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
      return '必要研究：${researchNameForDisplay(event.requiredResearch!)}';
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
    final builtPlots = <int>{
      for (final d in completed) d.plotIndex,
      for (final b in cityBuildings(cityId))
        if (!b.legacySite && !b.underConstruction) b.plotIndex,
    };
    final reserved = <int>{
      for (final p in plans)
        if (!p.isFinished &&
            p.cityId == cityId &&
            !p.definition.isDistrictUpgrade)
          p.plotIndex!,
      for (final b in cityBuildings(cityId))
        if (b.underConstruction) b.plotIndex,
    };
    return CityDevelopmentSummary(
      completedPlots: builtPlots.length,
      totalLevels: totalLevels,
      emptyPlots: city.plotCount - builtPlots.length,
      reservedPlots: reserved.length,
      reservedOccupiedPlots: reserved.intersection(builtPlots).length,
      stageName: GameContent.cityStageNames[stage],
      nextStageAtTotalLevels: stage + 1 < thresholds.length
          ? thresholds[stage + 1]
          : null,
    );
  }

  bool cityUnlocked(String cityId) => cityLockReason(cityId) == null;
  bool planetUnlocked(String planet) => planetLockReason(planet) == null;
  String? planetLockReason(String planet) => switch (planet) {
    'earth' => null,
    'moon' =>
      achievements.contains('first_launch') ||
              achievements.contains('mars_route_open') ||
              achievements.contains('first_landing') ||
              legacyUnlockedPlanets.contains('moon')
          ? null
          : '初めてのロケット打ち上げを完了してください',
    'mars' =>
      achievements.contains('mars_route_open') ||
              achievements.contains('first_landing') ||
              legacyUnlockedPlanets.contains('mars')
          ? null
          : '月面基地と月面打ち上げ基地を整え、火星探査機を打ち上げてください',
    _ => '対応する天体がありません',
  };
  String? spaceTaskLockReason(TaskDefinition task) {
    if (task.id == 'moon_delivery') return planetLockReason('moon');
    if (task.id == 'mars_probe') {
      final moonReason = planetLockReason('moon');
      if (moonReason != null) return moonReason;
      if (achievements.contains('mars_route_open')) return '火星航路は開拓済みです';
      if (districtCount('moon_outpost') == 0) return '月面基地を建設してください';
      if (districtCount('moon_spaceport') == 0) return '月面打ち上げ基地を建設してください';
      if (facilities['moon'] != true) return '月面建設班を再開してください';
    }
    if (task.outputResource == 'marsKits' &&
        task.inputResource == 'earthKits') {
      return planetLockReason('mars');
    }
    return null;
  }

  String? cityLockReason(String cityId) {
    final city = GameContent.cities[cityId];
    if (city == null) return '都市が見つかりません';
    final planetReason = planetLockReason(city.planet);
    if (planetReason != null) return planetReason;
    if (city.planet == 'mars' &&
        !achievements.contains('first_landing') &&
        !legacyUnlockedPlanets.contains('mars')) {
      return '初回の火星輸送が必要';
    }
    if (city.requiredResearch != null &&
        !research.contains(city.requiredResearch)) {
      return '前提研究：${researchNameForDisplay(city.requiredResearch!)}';
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
          (facilityId == 'lab' ||
              task.researchBranch == branch ||
              GameContent.legacyResearchBranchFor(id) == branch ||
              (facilityId == 'factory' &&
                  GameContent.researchTechnologies[id]?.unlockEffect ==
                      ResearchUnlockEffect.production) ||
              (facilityId == 'launch' &&
                  GameContent.researchTechnologies[id]?.unlockEffect ==
                      ResearchUnlockEffect.transport) ||
              (facilityId == 'mars' &&
                  GameContent.researchTechnologies[id]?.unlockEffect ==
                      ResearchUnlockEffect.construction))) {
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
        partnershipEfficiencyBonus(facilityId) +
        developmentEfficiencyBonus(facilityId),
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
  int get launchCostReductionPercent {
    var discount = 0;
    if (facilities['launch'] == true && districtCount('space_elevator') > 0) {
      discount += GameContent.spaceElevatorLaunchDiscountPercent;
    }
    if (facilities['moon'] == true &&
        districtCount('moon_outpost') > 0 &&
        districtCount('moon_spaceport') > 0) {
      discount += GameContent.moonSpaceportLaunchDiscountPercent;
      if (districtCount('moon_solar') > 0 &&
          districtCount('moon_extractor') > 0) {
        discount += GameContent.moonPropellantLaunchDiscountPercent;
      }
    }
    return math.min(GameContent.maxLaunchDiscountPercent, discount);
  }

  Map<String, int> kitSupportInputs(TaskDefinition task) {
    if (task.outputResource != 'earthKits') return const {};
    final cities = GameContent.cities.values.where((c) => c.planet == 'earth');
    return {
      for (final resource in ['parts', 'provisions', 'serviceCredit'])
        resource: math.min(
          task.outputAmount,
          cities.fold(0, (sum, c) => sum + cityStock(c.id, resource)),
        ),
    };
  }

  int taskCost(TaskDefinition task) {
    final support = kitSupportInputs(task);
    final reduction =
        (support['parts'] ?? 0) * GameContent.kitPartCostReduction +
        (support['provisions'] ?? 0) * GameContent.kitProvisionCostReduction +
        (support['serviceCredit'] ?? 0) * GameContent.kitServiceCostReduction;
    return math.max(
      0,
      task.usesLaunchCost
          ? (task.cost * (100 - launchCostReductionPercent) + 99) ~/ 100
          : task.cost - reduction,
    );
  }

  int currentTaskDurationMs(String taskId) =>
      effectiveDurationMs(GameContent.tasks[taskId]!);
  int _scaledDuration(int duration, String facilityId) =>
      (duration * 100 + 99 + facilityBonusPercent(facilityId)) ~/
      (100 + facilityBonusPercent(facilityId));
  int plannedCost(PlannedTask plan) => plan.relocation
      ? (buildingLocations[plan.buildingInstanceId]?.legacySite == true ||
                plan.buildingInstanceId == 'base_lab'
            ? 0
            : (GameContent.developmentCost(
                        developmentTechnologyId(plan.buildingInstanceId!),
                      ) +
                      GameContent.buildingRelocationDivisor -
                      1) ~/
                  GameContent.buildingRelocationDivisor)
      : plan.definition.districtId == null
      ? taskCost(plan.definition)
      : _districtInvestment(
          plan.cityId!,
          GameContent.districts[plan.definition.districtId]!,
          plan.targetLevel!,
          upgrade: plan.definition.isDistrictUpgrade,
        ).cost;
  int plannedDurationMs(PlannedTask plan) => plan.relocation
      ? GameContent.buildingRelocationDurationMs
      : plan.definition.districtId == null
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

  /// Knowledge unlocks a design independently of funds, land and city access.
  /// Discovering or reserving a research candidate does not unlock its designs.
  bool districtResearchUnlocked(String districtId) {
    final definition = GameContent.districts[districtId];
    return definition != null &&
        definition.requiredResearchIds.every(research.contains);
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
    } else if (!upgrade &&
        _occupiedBuildingSlots(cityId, plotIndex).any(
          (slot) =>
              GameContent.districtOccupiesWholePlot(districtId) || slot == 0,
        )) {
      reason = 'この区画は施設または建設予約が使用しています';
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
    } else if (!districtResearchUnlocked(districtId)) {
      reason =
          '前提研究：${researchNameForDisplay(definition.requiredResearchIds.firstWhere((id) => !research.contains(id)))}';
    } else if (city.planet == 'moon' &&
        districtId != 'moon_outpost' &&
        districtCount('moon_outpost') == 0) {
      reason = '月面基地を先に建設してください';
    } else if (districtId == 'space_elevator' &&
        !upgrade &&
        (districtCount('space_elevator') > 0 ||
            plans.any(
              (plan) =>
                  !plan.isFinished &&
                  plan.definition.districtId == 'space_elevator',
            ))) {
      reason = '宇宙エレベーターは1基だけ建設できます';
    } else if (districtId == 'mars_habitat' && habitatChoice == null) {
      reason = '居住方式を選択してください';
    } else if (upgrade) {
      final required = definition.researchForUpgrade(level);
      if (!research.contains(required)) {
        reason = '前提研究：${researchNameForDisplay(required)}';
      }
    }
    var delta = const DistrictEffects();
    var rawDelta = const DistrictEffects();
    var terrainEffects = const DistrictEffects();
    var adjacencyEffects = const DistrictEffects();
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
      // Explain placement with the same engine formula used for live income.
      // Difference both layouts so an upgrade reports only its added effect
      // and an industry district also reports losses to existing housing.
      final noTerrainDelta =
          _districtEffects(after, includeTerrain: false) -
          _districtEffects(districts, includeTerrain: false);
      final baseDelta =
          _districtEffects(
            after,
            includeTerrain: false,
            includeAdjacency: false,
          ) -
          _districtEffects(
            districts,
            includeTerrain: false,
            includeAdjacency: false,
          );
      final noAdjacencyDelta =
          _districtEffects(after, includeAdjacency: false) -
          _districtEffects(districts, includeAdjacency: false);
      final terrainDelta = rawDelta - noTerrainDelta;
      // The tax floor belongs to the adjacency that caused the loss, rather
      // than making an existing coastal district look like harmful terrain.
      terrainEffects = DistrictEffects(
        tax: noAdjacencyDelta.tax - baseDelta.tax,
        research: terrainDelta.research,
        factory: terrainDelta.factory,
        launch: terrainDelta.launch,
        mars: terrainDelta.mars,
      );
      adjacencyEffects = rawDelta - baseDelta - terrainEffects;
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
              definition.planet == 'earth' ? 'factory' : definition.planet,
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
      terrainEffects: terrainEffects,
      adjacencyEffects: adjacencyEffects,
      blockedReason: reason,
    );
  }

  DistrictEffects _districtEffects(
    Map<String, DistrictState> layout, {
    bool includeTerrain = true,
    bool includeAdjacency = true,
  }) {
    var result = const DistrictEffects();
    for (final district in layout.values) {
      final definition = GameContent.districts[district.districtId]!;
      if (facilities[definition.operatingFacilityId] != true) continue;
      final city = GameContent.cities[district.cityId]!;
      final terrain = includeTerrain ? city.terrainAt(district.plotIndex) : '';
      final neighbors = [
        for (final index
            in includeAdjacency
                ? city.adjacentPlots(district.plotIndex)
                : const <int>[])
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
                (includeTerrain && city.terrainAt(n.plotIndex) == 'ridge'
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
      districtEffects.tax +
      developmentIncomePerMinute;
  int get upkeepPerMinute =>
      GameContent.facilities.values
          .where((f) => facilities[f.id]!)
          .fold(0, (sum, f) => sum + f.upkeepPerMinute) +
      districtEffects.upkeep +
      developmentUpkeepPerMinute;
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
    'missionIdentity': identity.toJson(),
    'openingSeen': openingSeen,
    'openingStarted': openingStarted,
    'firstRunTutorial': firstRunTutorial.name,
    'firstRunTutorialPlanId': firstRunTutorialPlanId,
    'lastWallClockMs': lastWallClockMs,
    'simulatedMs': simulatedMs,
    'moneyUnits': moneyUnits,
    'earthLevel': earthLevel,
    'population': population,
    'earthKits': earthKits,
    'moonKits': moonKits,
    'marsKits': marsKits,
    'marsHabitats': marsHabitats,
    'marsResidents': marsResidents,
    'habitatChoice': habitatChoice,
    'specialistCount': specialistCount,
    'researchers': researchers,
    'researchPointUnits': researchPointUnits,
    'developments': developments.toList(),
    'developmentEnabled': Map<String, bool>.of(developmentEnabled),
    'developmentResearchers': Map<String, int>.of(developmentResearchers),
    'developmentCityIds': Map<String, String>.of(developmentCityIds),
    'developmentTechnologyIds': Map<String, String>.of(
      developmentTechnologyIds,
    ),
    'buildingLocations': {
      for (final e in buildingLocations.entries) e.key: e.value.toJson(),
    },
    'cityStocks': {
      for (final e in cityStocks.entries) e.key: Map<String, int>.of(e.value),
    },
    'surveyedSites': surveyedSites.toList()..sort(),
    'connectedGridCities': connectedGridCities.toList()..sort(),
    'preparedVehicles': preparedVehicles.toList()..sort(),
    'nextBuildingId': nextBuildingId,
    'partnershipChoices': Map<String, String>.of(partnershipChoices),
    'nextPlanId': nextPlanId,
    'contractRevenue': contractRevenue,
    'research': research.toList(),
    'discoveredResearch': discoveredResearchIds.toList()..sort(),
    'achievements': achievements.toList(),
    'legacyUnlockedPlanets': legacyUnlockedPlanets.toList()..sort(),
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
          'district-10',
          'district-9',
          'district-8',
          'district-7',
          'district-6',
          'district-5',
          'district-4',
          'district-3',
          'district-2',
        ].contains(json['contentVersion']);
    if (!legacy && !compatibleDistricts) {
      throw const FormatException('未対応の保存形式またはコンテンツ版です。元のデータを保持してください。');
    }
    final state = GameState._();
    state.worldId = json['worldId'] as String;
    // Existing worlds continue directly; only genuinely new worlds play the OP.
    state.openingSeen = json['openingSeen'] as bool? ?? true;
    state.openingStarted = json['openingStarted'] as bool? ?? false;
    state.firstRunTutorial = FirstRunTutorialStep.fromSaved(
      json['firstRunTutorial'],
    );
    state.firstRunTutorialPlanId = json['firstRunTutorialPlanId'] as String?;
    if (json['missionIdentity'] case final Map identity) {
      state.identity = MissionIdentity.fromJson(
        Map<String, dynamic>.from(identity),
      );
    }
    state.lastWallClockMs = json['lastWallClockMs'] as int;
    state.simulatedMs = json['simulatedMs'] as int;
    state.moneyUnits = json['moneyUnits'] as int;
    state.earthLevel = json['earthLevel'] as int;
    state.population = json['population'] as int;
    state.earthKits = json['earthKits'] as int;
    state.moonKits = json['moonKits'] as int? ?? 0;
    state.marsKits = json['marsKits'] as int;
    state.marsHabitats = json['marsHabitats'] as int;
    state.marsResidents = json['marsResidents'] as int;
    state.habitatChoice = json['habitatChoice'] as String?;
    final currentAgency =
        json['contentVersion'] == GameContent.version ||
        json['contentVersion'] == 'district-10' ||
        json['contentVersion'] == 'district-9' ||
        json['contentVersion'] == 'district-8' ||
        json['contentVersion'] == 'district-7' ||
        json['contentVersion'] == 'district-6' ||
        json['contentVersion'] == 'district-5';
    if (currentAgency) {
      state.specialistCount = json['specialistCount'] as int;
      state.researchers = json['researchers'] as int;
      state.partnershipChoices.addAll(
        Map<String, String>.from(json['partnershipChoices'] as Map),
      );
    }
    // Old worlds receive no retroactive RP, construction, or achievement reward.
    // New worlds alone begin with the explicitly budgeted starter RP.
    state.researchPointUnits = json['researchPointUnits'] as int? ?? 0;
    state.developments.addAll(
      (json['developments'] as List? ?? []).cast<String>(),
    );
    state.developmentEnabled.addAll(
      Map<String, bool>.from(json['developmentEnabled'] as Map? ?? {}),
    );
    state.developmentResearchers.addAll(
      Map<String, int>.from(json['developmentResearchers'] as Map? ?? {}),
    );
    state.developmentCityIds.addAll(
      Map<String, String>.from(json['developmentCityIds'] as Map? ?? {}),
    );
    state.developmentTechnologyIds.addAll(
      Map<String, String>.from(json['developmentTechnologyIds'] as Map? ?? {}),
    );
    if (json['contentVersion'] == GameContent.version &&
        json['buildingLocations'] is! Map) {
      throw const FormatException('現行保存に施設の位置がありません');
    }
    if (json['buildingLocations'] case final Map locations) {
      state.buildingLocations.clear();
      for (final e in locations.entries) {
        state.buildingLocations[e.key as String] = BuildingLocation.fromJson(
          Map<String, dynamic>.from(e.value as Map),
        );
      }
    } else {
      for (final id in state.developments) {
        if (GameContent.mapBuildingDefinitions.containsKey(id)) {
          state.buildingLocations[id] = BuildingLocation(
            cityId: state.developmentCityIds[id]!,
            plotIndex: -1,
            legacySite: true,
          );
        }
      }
    }
    for (final e in (json['cityStocks'] as Map? ?? {}).entries) {
      state.cityStocks[e.key as String] = Map<String, int>.from(e.value as Map);
    }
    state.surveyedSites.addAll(
      (json['surveyedSites'] as List? ?? []).cast<String>(),
    );
    state.connectedGridCities.addAll(
      (json['connectedGridCities'] as List? ?? []).cast<String>(),
    );
    state.preparedVehicles.addAll(
      (json['preparedVehicles'] as List? ?? []).cast<String>(),
    );
    state.nextBuildingId = json['nextBuildingId'] as int? ?? 1;
    state.nextPlanId = json['nextPlanId'] as int;
    state.contractRevenue = json['contractRevenue'] as int;
    state.research.addAll((json['research'] as List).cast<String>());
    if (json.containsKey('discoveredResearch')) {
      final known = json['discoveredResearch'];
      if (known is! List ||
          known.any(
            (id) =>
                id is! String ||
                GameContent.researchTechnologies[id]?.isPurchasable != true,
          )) {
        throw const FormatException('保存された既知の研究が不正です。元のデータを保持してください。');
      }
      state._knownResearch.addAll(known.cast<String>());
    }
    // A missing optional key in hand-authored current fixtures starts from the
    // v8 discovery rules. It must never reactivate the old root-count rule.
    state.achievements.addAll((json['achievements'] as List).cast<String>());
    final legacyPlanets = json['legacyUnlockedPlanets'] as List? ?? const [];
    if (legacyPlanets.any((planet) => !['moon', 'mars'].contains(planet))) {
      throw const FormatException('保存された天体のアクセス権が不正です');
    }
    state.legacyUnlockedPlanets.addAll(legacyPlanets.cast<String>());
    state.claimedRewards.addAll(
      (json['claimedRewards'] as List).cast<String>(),
    );
    final enabled = Map<String, bool>.from(json['facilities'] as Map);
    if (json['contentVersion'] != GameContent.version) {
      enabled.putIfAbsent('moon', () => true);
    }
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
    for (final plan in state.plans) {
      if (plan.status == 'queued' && plan.isImmediateAction) {
        plan.requiresManualStart = true;
        plan.stopReason = '着手待ち：内容を確認して開始してください';
      }
    }
    final strandedTutorialResearch =
        json['contentVersion'] != GameContent.version &&
        state.firstRunTutorial == FirstRunTutorialStep.startResearch &&
        state.plans.any(
          (plan) => plan.taskId == 'life_support' && plan.status == 'queued',
        );
    if ((!json.containsKey('researchPointUnits') || strandedTutorialResearch) &&
        state.firstRunTutorial != FirstRunTutorialStep.completed &&
        !state.research.contains('life_support') &&
        !state.plans.any(
          (plan) => plan.taskId == 'life_support' && plan.status == 'running',
        )) {
      // The old protected walkthrough cannot advance its clock to earn RP.
      // Carry only its unused starter research budget, once, into the new bank.
      state.researchPointUnits = math.max(
        state.researchPointUnits,
        GameContent.researchPointCost('life_support') * researchPointScale,
      );
    }
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
    if (state.researchPointUnits < 0 ||
        state.developments.any(
          (id) =>
              GameContent
                  .researchTechnologies[state.developmentTechnologyId(id)]
                  ?.isPurchasable !=
              true,
        ) ||
        state.developmentEnabled.keys.any(
          (id) => !state.developments.contains(id),
        ) ||
        state.developmentResearchers.keys.any(
          (id) => !state.developments.contains(id),
        ) ||
        state.developmentCityIds.keys.any(
          (id) => !state.developments.contains(id),
        )) {
      throw const FormatException('研究ポイントまたは導入設備の状態が不正です');
    }
    for (final id in state.developments) {
      final city = GameContent.cities[state.developmentCityIds[id]];
      final assigned = state.developmentResearchers[id] ?? 0;
      if (!state.research.contains(state.developmentTechnologyId(id)) ||
          city == null ||
          (state.buildingLocations[id]?.legacySite == false
              ? GameContent
                        .mapBuildingDefinitions[state.developmentTechnologyId(
                          id,
                        )]
                        ?.allowedPlanets
                        .contains(city.planet) !=
                    true
              : city.planet !=
                    GameContent.developmentPlanet(
                      state.developmentTechnologyId(id),
                    )) ||
          assigned < 0 ||
          (state.developmentEnabled[id] == true &&
              state.facilities[state.developmentFacilityFor(id)] != true)) {
        throw const FormatException('設備の導入先または配属が不正です');
      }
    }
    if (state.developments.where(state.isDevelopmentOperational).length >
        GameContent.maxOperationalDevelopments) {
      throw const FormatException('専門設備の稼働数が不正です');
    }
    if (state.specialistCount < 0 ||
        state.researchers < 0 ||
        state.researchers > state.specialistCount) {
      throw const FormatException('過去の専門職記録が不正です');
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
    final developmentTargets = <String>{};
    for (final plan in state.plans.where(
      (plan) => !plan.isFinished && plan.definition.developmentId != null,
    )) {
      if (plan.relocation) continue;
      final id = plan.definition.developmentId!;
      final target = plan.buildingInstanceId == null
          ? id
          : '${plan.developmentCityId}:$id';
      if (!developmentTargets.add(target) ||
          (plan.buildingInstanceId == null &&
              state.developments.contains(id))) {
        throw const FormatException('設備の導入予約が重複しています');
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
    if (state.firstRunTutorial == FirstRunTutorialStep.finishConstruction) {
      final tutorialPlan = state.plans
          .where((plan) => plan.id == state.firstRunTutorialPlanId)
          .firstOrNull;
      if (tutorialPlan == null ||
          tutorialPlan.cityId != 'earth_delta' ||
          tutorialPlan.definition.districtId != 'housing' ||
          tutorialPlan.definition.isDistrictUpgrade ||
          tutorialPlan.targetLevel != 1 ||
          !['queued', 'running'].contains(tutorialPlan.status) ||
          tutorialPlan.completedRuns != 0 ||
          tutorialPlan.remainingRepeats != 1) {
        throw const FormatException('初回チュートリアルの建設予約が不正です');
      }
    }
    if (state.simulatedMs < 0 ||
        state.moneyUnits < 0 ||
        state.earthLevel < 1 ||
        state.population < 0 ||
        state.earthKits < 0 ||
        state.moonKits < 0 ||
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
    if (![
      GameContent.version,
      'district-9',
      'district-8',
    ].contains(json['contentVersion'])) {
      state._knownResearch.addAll(state._legacyDiscoveredResearchIds());
    }
    if (json['contentVersion'] != GameContent.version &&
        (state.plans.any(
              (plan) =>
                  plan.definition.usesLaunchCost && plan.completedRuns > 0,
            ) ||
            state.completionNotices.any(
              (notice) =>
                  GameContent.tasks[notice.taskId]?.usesLaunchCost == true,
            ))) {
      state.legacyUnlockedPlanets.add('moon');
    }
    if (json['contentVersion'] != GameContent.version &&
        (state.achievements.contains('first_landing') ||
            state.marsKits > 0 ||
            state.marsHabitats > 0 ||
            state.marsResidents > 0 ||
            state.districts.values.any(
              (district) =>
                  GameContent.cities[district.cityId]!.planet == 'mars',
            ) ||
            state.developments.any(
              (id) =>
                  GameContent.developmentPlanet(
                    state.developmentTechnologyId(id),
                  ) ==
                  'mars',
            ) ||
            state.plans.any(
              (plan) =>
                  !plan.isFinished &&
                  (plan.definition.outputResource == 'marsKits' ||
                      plan.definition.facilityId == 'mars' ||
                      (plan.definition.developmentId != null &&
                          GameContent.developmentPlanet(
                                plan.definition.developmentId!,
                              ) ==
                              'mars')),
            ))) {
      state.legacyUnlockedPlanets.addAll(['moon', 'mars']);
    }
    state.validateBuildingState();
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
