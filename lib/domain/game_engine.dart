import 'dart:math' as math;

import 'game_content.dart';
import 'game_state.dart';

/// Deterministic, event-boundary simulation. At a shared timestamp:
/// (1) income/upkeep accrues, (2) jobs finish in facility order,
/// (3) insolvent facilities suspend, (4) the first reserved job per facility
/// may start. Starting a job pays its full cost and consumes its cargo once.
class GameEngine {
  GameEngine(this.state) {
    _stabilize();
  }
  final GameState state;

  String? enqueue(String taskId, {int? repeats = 1}) {
    final task = GameContent.tasks[taskId];
    if (task == null) return '未対応の計画です';
    if (repeats != null && repeats < 1) return '反復回数は1回以上を指定してください';
    if (state.activePlanCount >= GameContent.maxActivePlans) {
      return '予約は最大${GameContent.maxActivePlans}件です';
    }
    if (task.unique &&
        (repeats != 1 ||
            state.research.contains(taskId) ||
            state.plans.any((p) => p.taskId == taskId && !p.isFinished))) {
      return '研究は1回だけ予約・実施できます';
    }
    state.plans.add(
      PlannedTask(
        id: 'plan-${state.nextPlanId++}',
        taskId: taskId,
        remainingRepeats: repeats,
      ),
    );
    _record('${task.name}を予約（${repeats == null ? '無期限' : '$repeats回'}）');
    _stabilize();
    return null;
  }

  /// For a running order, this ends repetition after its paid current run.
  /// Unstarted orders are removed without a refund (nothing was paid).
  String? cancelQueued(String planId) {
    final matches = state.plans.where((p) => p.id == planId);
    if (matches.isEmpty) return '計画が見つかりません';
    final plan = matches.first;
    if (plan.isFinished) return 'この計画は終了しています';
    if (plan.status == 'running') {
      plan.remainingRepeats = 1;
      _record('${plan.definition.name}は実行中の1回で終了');
    } else {
      plan.status = 'cancelled';
      plan.stopReason = '予約を取り消しました';
      _record('${plan.definition.name}の予約を取り消し');
    }
    _stabilize();
    return null;
  }

  /// Changes only future starts on one facility. Its paid current iteration
  /// stays running, even if that plan's remaining repetitions move backwards.
  /// The ordered plans list is already part of the atomic save generation.
  String? reorderPlan(
    String planId, {
    required String relativeToPlanId,
    required bool before,
  }) {
    final planIndex = state.plans.indexWhere((p) => p.id == planId);
    final relativeIndex = state.plans.indexWhere(
      (p) => p.id == relativeToPlanId,
    );
    if (planIndex < 0 || relativeIndex < 0) return '計画が見つかりません';
    final plan = state.plans[planIndex];
    final relative = state.plans[relativeIndex];
    if (!plan.hasFutureRuns || !relative.hasFutureRuns) {
      return '順番を変えられる次の予約がありません';
    }
    if (plan.definition.facilityId != relative.definition.facilityId) {
      return '同じ設備の予約だけを並べ替えられます';
    }
    if (plan == relative) return '別の予約を指定してください';
    state.plans.removeAt(planIndex);
    final target = state.plans.indexOf(relative) + (before ? 0 : 1);
    state.plans.insert(target, plan);
    _record('${plan.definition.name}の予約順を変更');
    _stabilize();
    return null;
  }

  String? chooseHabitat(String choice) {
    if (!['dome', 'underground'].contains(choice)) return '居住方式を選んでください';
    if (state.habitatChoice != null) return 'この試作では居住方式は選択済みです';
    if (!state.achievements.contains('first_landing')) {
      return '火星への輸送完了後に選択できます';
    }
    state.habitatChoice = choice;
    _record(choice == 'dome' ? '方針決定：ドーム居住' : '方針決定：地下居住');
    _stabilize();
    return null;
  }

  String? setFacilityEnabled(String facilityId, bool enabled) {
    final facility = GameContent.facilities[facilityId];
    if (facility == null) return '設備が見つかりません';
    if (state.facilities[facilityId] == enabled) return null;
    if (enabled && state.money < facility.upkeepPerMinute) {
      return '再開には維持費1分分の${facility.upkeepPerMinute} Crが必要です（支払は通常どおり）';
    }
    state.facilities[facilityId] = enabled;
    _record('${facility.name}を${enabled ? '再開' : '休止'}');
    _stabilize();
    return null;
  }

  /// Uses device time. Moving backwards only rebases the anchor: completed
  /// executions, inventory and rewards remain committed. No clock penalty.
  void advanceTo(DateTime now) {
    final timestamp = now.millisecondsSinceEpoch;
    final delta = timestamp - state.lastWallClockMs;
    state.lastWallClockMs = timestamp;
    if (delta > 0) _advance(delta);
  }

  /// Explicit development control; never changes the device-time anchor or
  /// the content durations. The UI must identify this as a development tool.
  void advanceBy(Duration duration) {
    if (duration.isNegative) throw ArgumentError.value(duration, 'duration');
    _advance(duration.inMilliseconds);
  }

  void _advance(int deltaMs) {
    _stabilize();
    final target = state.simulatedMs + deltaMs;
    while (state.simulatedMs < target) {
      var step = target - state.simulatedMs;
      for (final plan in state.plans) {
        if (plan.status == 'running' &&
            state.facilities[plan.definition.facilityId]!) {
          step = math.min(step, plan.remainingMs);
        }
      }
      final net = state.netPerMinute;
      if (net < 0 && state.moneyUnits > 0) {
        step = math.min(step, _ceilDiv(state.moneyUnits, -net));
      }
      // A queued, affordable-in-future job is also an event boundary. Without
      // this boundary, aggregate offline catch-up would start jobs too late.
      if (net > 0) {
        for (final id in GameContent.facilities.keys) {
          final plan = _head(id);
          if (plan == null ||
              plan.status != 'queued' ||
              !state.facilities[id]!) {
            continue;
          }
          if (_requirementReason(
            plan.definition,
            includeMoney: false,
          ).isNotEmpty) {
            continue;
          }
          final gap =
              plan.definition.cost * GameState.moneyScale - state.moneyUnits;
          if (gap > 0) step = math.min(step, _ceilDiv(gap, net));
        }
      }
      if (step <= 0) throw StateError('Simulation did not advance');
      state.moneyUnits = math.max(0, state.moneyUnits + net * step);
      for (final plan in state.plans) {
        if (plan.status == 'running' &&
            state.facilities[plan.definition.facilityId]!) {
          plan.remainingMs -= step;
        }
      }
      state.simulatedMs += step;
      _stabilize();
    }
  }

  void _stabilize() {
    for (final id in GameContent.facilities.keys) {
      final plan = _head(id);
      if (plan != null && plan.status == 'running' && plan.remainingMs == 0) {
        _complete(plan);
      }
    }
    _suspendForBudget();
    for (final id in GameContent.facilities.keys) {
      final head = _head(id);
      for (final plan in state.plans.where(
        (p) => p.definition.facilityId == id && !p.isFinished,
      )) {
        if (!state.facilities[id]!) {
          plan.stopReason = '設備休止中・手動で再開';
        } else if (plan != head) {
          plan.stopReason = '共用設備の順番待ち';
        } else if (plan.status == 'running') {
          plan.stopReason = '';
        } else {
          plan.stopReason = _requirementReason(plan.definition);
          if (plan.stopReason.isEmpty) _start(plan);
        }
      }
    }
    _trimFinishedPlans();
    _suspendForBudget();
    // A just-started job may use the last credits. Keep the visible reason
    // consistent with suspension without re-running starts or completions.
    for (final plan in state.plans.where((p) => !p.isFinished)) {
      if (!state.facilities[plan.definition.facilityId]!) {
        plan.stopReason = '設備休止中・手動で再開';
      }
    }
  }

  void _trimFinishedPlans() {
    var excess =
        state.plans.where((p) => p.isFinished).length -
        GameContent.maxFinishedPlans;
    if (excess <= 0) return;
    state.plans.removeWhere((plan) {
      if (excess > 0 && plan.isFinished) {
        excess--;
        return true;
      }
      return false;
    });
  }

  PlannedTask? _head(String facilityId) {
    // Queue edits never interrupt or charge again for an active paid run.
    final current = state.currentPlanFor(facilityId);
    if (current != null) return current;
    for (final plan in state.plans) {
      if (!plan.isFinished && plan.definition.facilityId == facilityId) {
        return plan;
      }
    }
    return null;
  }

  String _requirementReason(TaskDefinition task, {bool includeMoney = true}) {
    if (task.requiredResearch != null &&
        !state.research.contains(task.requiredResearch)) {
      return '前提研究待ち：${GameContent.tasks[task.requiredResearch]!.name}';
    }
    if (task.requiresHabitatChoice && state.habitatChoice == null) {
      return state.achievements.contains('first_landing')
          ? '分岐待ち：居住方式を選択'
          : '火星輸送後に居住方式を選択';
    }
    if (task.inputResource != null && _resource(task.inputResource!) < 1) {
      return '資源不足：${GameContent.resourceNames[task.inputResource]}が1基必要';
    }
    if (includeMoney && state.moneyUnits < task.cost * GameState.moneyScale) {
      return '資金不足：${task.cost} Crが必要';
    }
    return '';
  }

  void _start(PlannedTask plan) {
    final task = plan.definition;
    state.moneyUnits -= task.cost * GameState.moneyScale;
    if (task.inputResource != null) _changeResource(task.inputResource!, -1);
    plan.status = 'running';
    plan.remainingMs = task.durationMs;
    plan.stopReason = '';
    _record('${task.name}を開始（-${task.cost} Cr）');
  }

  void _complete(PlannedTask plan) {
    final task = plan.definition;
    // The execution ordinal and its effect live in the same saved generation.
    plan.completedRuns++;
    if (plan.remainingRepeats != null) {
      plan.remainingRepeats = plan.remainingRepeats! - 1;
    }
    plan.status = plan.remainingRepeats == 0 ? 'completed' : 'queued';
    plan.stopReason = plan.isFinished ? '指定回数が完了' : '';
    state.moneyUnits += task.reward * GameState.moneyScale;
    if (task.id.endsWith('_contract')) state.contractRevenue += task.reward;
    if (task.outputResource != null) _changeResource(task.outputResource!, 1);
    switch (task.id) {
      case 'life_support':
        state.research.add(task.id);
      case 'earth_expansion':
        state.earthLevel++;
        state.population += GameContent.residentsPerDistrict;
      case 'mars_delivery':
        _achievement('first_landing', reward: 0);
      case 'build_habitat':
        state.marsHabitats++;
        state.marsResidents += GameContent.residentsPerHabitat;
        _achievement(
          '${state.habitatChoice}_habitat',
          reward: GameContent.achievementReward,
        );
    }
    _record('${task.name}が完了${task.reward == 0 ? '' : '（+${task.reward} Cr）'}');
  }

  void _achievement(String id, {required int reward}) {
    state.achievements.add(id);
    final rewardKey = '${state.worldId}:achievement:$id';
    if (state.claimedRewards.add(rewardKey)) {
      state.moneyUnits += reward * GameState.moneyScale;
      _record(
        '実績：${GameContent.achievementNames[id]}${reward == 0 ? '' : '（+$reward Cr）'}',
      );
    }
  }

  void _suspendForBudget() {
    if (state.moneyUnits > 0 || state.netPerMinute >= 0) return;
    // Provisional priority. Tax collection never stops and there is no debt.
    for (final id in ['launch', 'factory', 'lab', 'mars']) {
      if (state.netPerMinute >= 0) break;
      if (state.facilities[id]!) {
        state.facilities[id] = false;
        _record('資金不足により${GameContent.facilities[id]!.name}を休止。税収で再建できます。');
      }
    }
  }

  int _resource(String id) => switch (id) {
    'earthKits' => state.earthKits,
    'marsKits' => state.marsKits,
    _ => throw ArgumentError.value(id, 'resource'),
  };
  void _changeResource(String id, int amount) {
    switch (id) {
      case 'earthKits':
        state.earthKits += amount;
      case 'marsKits':
        state.marsKits += amount;
      default:
        throw ArgumentError.value(id, 'resource');
    }
  }

  void _record(String text) {
    state.log.add('[${state.simulatedMs ~/ 1000}s] $text');
    if (state.log.length > 40) state.log.removeAt(0);
  }

  static int _ceilDiv(int value, int divisor) =>
      (value + divisor - 1) ~/ divisor;
}
