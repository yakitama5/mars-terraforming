import 'dart:convert';

import 'game_content.dart';
import 'game_engine.dart';
import 'game_state.dart';

/// Deliberately short planning windows, independent of development time skips.
const planForecastHorizons = [
  Duration(minutes: 30),
  Duration(hours: 1),
  Duration(hours: 8),
];

enum ForecastFacilityStatus { running, waiting, paused, idle }

class ForecastCompletion {
  const ForecastCompletion({
    required this.planId,
    required this.taskId,
    required this.runs,
    this.cityId,
    this.plotIndex,
    this.targetLevel,
  });
  final String planId, taskId;
  final int runs;
  final String? cityId;
  final int? plotIndex, targetLevel;
}

class ForecastFacility {
  const ForecastFacility({
    required this.facilityId,
    required this.enabled,
    required this.status,
    required this.stopReason,
    required this.taskId,
    required this.remainingMs,
    required this.queuedPlans,
    required this.completedRuns,
  });
  final String facilityId;
  final bool enabled;
  final ForecastFacilityStatus status;
  final String stopReason;

  /// The paid iteration, or the head reservation when no iteration is running.
  final String? taskId;
  final int remainingMs;

  /// Future starts, including another iteration of a running repeating plan.
  final int queuedPlans, completedRuns;
}

/// Read-only projection of the orders already present in a world. Population
/// means Earth's population; Mars residents are reported separately as in state.
class PlanForecast {
  const PlanForecast._({
    required this.horizon,
    required this.money,
    required this.moneyDelta,
    required this.moneyUnits,
    required this.netPerMinute,
    required this.districtCount,
    required this.districtDelta,
    required this.totalDistrictLevels,
    required this.districtLevelDelta,
    required this.population,
    required this.populationDelta,
    required this.marsResidents,
    required this.marsResidentsDelta,
    required this.earthKits,
    required this.moonKits,
    required this.marsKits,
    required this.completedResearch,
    required this.newAchievements,
    required this.completions,
    required this.facilities,
  });
  final Duration horizon;
  final int money, moneyDelta, moneyUnits, netPerMinute;
  final int districtCount,
      districtDelta,
      totalDistrictLevels,
      districtLevelDelta;
  final int population, populationDelta, marsResidents, marsResidentsDelta;
  final int earthKits, moonKits, marsKits;
  final Set<String> completedResearch, newAchievements;
  final List<ForecastCompletion> completions;
  final List<ForecastFacility> facilities;
  int get completedRuns => completions.fold(0, (sum, item) => sum + item.runs);
}

/// Simulate only explicitly reserved work on a deep copy. This never writes a
/// save, changes the source clock anchor, chooses a branch, or adds orders.
/// The UI uses [planForecastHorizons] and refreshes on request, not every frame.
PlanForecast forecastPlans(GameState state, Duration horizon) {
  if (horizon.isNegative) throw ArgumentError.value(horizon, 'horizon');
  final copy = GameState.fromJson(
    jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
  );
  // Hold copied plan references even when the engine trims old finished rows.
  // The references never point into the player's world.
  final tracked = [
    for (final plan in copy.plans)
      if (!plan.isFinished) (plan: plan, completedRuns: plan.completedRuns),
  ];
  GameEngine(copy).advanceBy(horizon);
  final completions = [
    for (final item in tracked)
      if (item.plan.completedRuns > item.completedRuns)
        ForecastCompletion(
          planId: item.plan.id,
          taskId: item.plan.taskId,
          runs: item.plan.completedRuns - item.completedRuns,
          cityId: item.plan.cityId,
          plotIndex: item.plan.plotIndex,
          targetLevel: item.plan.targetLevel,
        ),
  ];
  final facilities = [
    for (final id in GameContent.facilities.keys)
      _facilityForecast(copy, id, completions),
  ];
  int levels(GameState value) =>
      value.districts.values.fold(0, (sum, district) => sum + district.level);
  return PlanForecast._(
    horizon: horizon,
    money: copy.money,
    moneyDelta: copy.money - state.money,
    moneyUnits: copy.moneyUnits,
    netPerMinute: copy.netPerMinute,
    districtCount: copy.districts.length,
    districtDelta: copy.districts.length - state.districts.length,
    totalDistrictLevels: levels(copy),
    districtLevelDelta: levels(copy) - levels(state),
    population: copy.population,
    populationDelta: copy.population - state.population,
    marsResidents: copy.marsResidents,
    marsResidentsDelta: copy.marsResidents - state.marsResidents,
    earthKits: copy.earthKits,
    moonKits: copy.moonKits,
    marsKits: copy.marsKits,
    completedResearch: Set.unmodifiable(
      copy.research.difference(state.research),
    ),
    newAchievements: Set.unmodifiable(
      copy.achievements.difference(state.achievements),
    ),
    completions: List.unmodifiable(completions),
    facilities: List.unmodifiable(facilities),
  );
}

ForecastFacility _facilityForecast(
  GameState state,
  String id,
  List<ForecastCompletion> completions,
) {
  final enabled = state.facilities[id]!;
  final current = state.currentPlanFor(id);
  final upcoming = state.upcomingPlansFor(id);
  final head = current ?? upcoming.firstOrNull;
  final completedRuns = completions
      .where((item) => GameContent.tasks[item.taskId]!.facilityId == id)
      .fold(0, (sum, item) => sum + item.runs);
  final status = !enabled
      ? ForecastFacilityStatus.paused
      : current != null && current.stopReason.isEmpty
      ? ForecastFacilityStatus.running
      : current != null || upcoming.isNotEmpty
      ? ForecastFacilityStatus.waiting
      : ForecastFacilityStatus.idle;
  return ForecastFacility(
    facilityId: id,
    enabled: enabled,
    status: status,
    stopReason: switch (status) {
      ForecastFacilityStatus.paused => '設備休止中・手動で再開',
      ForecastFacilityStatus.running => '',
      ForecastFacilityStatus.waiting => head!.stopReason,
      ForecastFacilityStatus.idle => completedRuns > 0 ? '予約した作業が完了' : '予約なし',
    },
    taskId: head?.taskId,
    remainingMs: current?.remainingMs ?? 0,
    queuedPlans: upcoming.length,
    completedRuns: completedRuns,
  );
}
