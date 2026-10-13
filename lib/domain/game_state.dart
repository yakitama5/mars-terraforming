import 'game_content.dart';

class PlannedTask {
  PlannedTask({
    required this.id,
    required this.taskId,
    this.remainingRepeats = 1,
  });
  final String id;
  final String taskId;

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
      ? 1 - remainingMs / definition.durationMs
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
    );
    plan.completedRuns = json['completedRuns'] as int;
    plan.status = json['status'] as String;
    plan.stopReason = json['stopReason'] as String;
    plan.remainingMs = json['remainingMs'] as int;
    if (![
          'queued',
          'running',
          'completed',
          'cancelled',
        ].contains(plan.status) ||
        plan.completedRuns < 0 ||
        plan.remainingMs < 0 ||
        plan.remainingMs > plan.definition.durationMs ||
        (plan.remainingRepeats != null && plan.remainingRepeats! < 0) ||
        (!plan.isFinished && plan.remainingRepeats == 0) ||
        (plan.status == 'running' && plan.remainingMs == 0)) {
      throw const FormatException('不正な作業状態');
    }
    return plan;
  }
}

/// Entire simulation generation, including the clock anchor and one-time rewards.
/// Flutter, rendering, I/O and wall-clock acquisition are deliberately excluded.
class GameState {
  GameState._();
  static const schemaVersion = 1;
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
  final List<String> log = [];

  factory GameState.initial(DateTime now) {
    final state = GameState._();
    state.lastWallClockMs = now.millisecondsSinceEpoch;
    state.worldId = 'world-${now.microsecondsSinceEpoch}';
    state.log.add('地球の小さな拠点から、火星開発を始めましょう。');
    return state;
  }
  int get money => moneyUnits ~/ moneyScale;
  set money(int value) {
    if (value < 0) throw ArgumentError.value(value, 'money');
    moneyUnits = value * moneyScale;
  }

  int get taxPerMinute =>
      GameContent.baseTaxPerMinute +
      (earthLevel - 1) * GameContent.districtTaxPerMinute;
  int get upkeepPerMinute => GameContent.facilities.values
      .where((f) => facilities[f.id]!)
      .fold(0, (sum, f) => sum + f.upkeepPerMinute);
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
  };

  factory GameState.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != schemaVersion ||
        json['contentVersion'] != GameContent.version) {
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
