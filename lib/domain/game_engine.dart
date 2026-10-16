import 'dart:math' as math;

import 'game_content.dart';
import 'contextual_tips.dart';
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

  int facilityBonusCap(String facilityId) => state.facilityBonusCap(facilityId);

  List<ResearchRequirementStatus> researchRequirements(String taskId) {
    final task = GameContent.tasks[taskId];
    if (task == null) return const [];
    final requirements = task.researchRequirements;
    return [
      for (final id in task.prerequisiteIds)
        ResearchRequirementStatus(
          label: '研究：${GameContent.tasks[id]!.name}',
          current: state.research.contains(id) ? 1 : 0,
          required: 1,
          unmetReason: '前提研究待ち：${GameContent.tasks[id]!.name}',
        ),
      if (requirements.marsHabitats > 0)
        ResearchRequirementStatus(
          label: '火星の閉鎖居住施設（従来の居住施設を含む）',
          current: state.marsHabitats,
          required: requirements.marsHabitats,
          unmetReason:
              '実証待ち：火星の閉鎖居住施設 ${state.marsHabitats}/${requirements.marsHabitats}基',
        ),
      for (final entry in requirements.districtCounts.entries)
        ResearchRequirementStatus(
          label: '完成した${GameContent.districts[entry.key]!.name}',
          current: state.districtCount(entry.key),
          required: entry.value,
          unmetReason:
              '実証待ち：${GameContent.districts[entry.key]!.name} ${state.districtCount(entry.key)}/${entry.value}地区',
        ),
      if (requirements.developedMarsCities > 0)
        ResearchRequirementStatus(
          label: '地区を整備した火星都市（従来の居住拠点を含む）',
          current: state.developedMarsCityIds.length,
          required: requirements.developedMarsCities,
          unmetReason:
              '実証待ち：火星都市の整備 ${state.developedMarsCityIds.length}/${requirements.developedMarsCities}都市',
        ),
    ];
  }

  List<String> researchRequirementReasons(String taskId) => [
    for (final requirement in researchRequirements(taskId))
      if (!requirement.isMet) requirement.unmetReason,
  ];

  String? enqueue(String taskId, {int? repeats = 1}) {
    final task = GameContent.tasks[taskId];
    if (task == null) return '未対応の計画です';
    if (task.districtId != null) return '都市の区画から建設を予約してください';
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

  String? enqueueDistrict(String cityId, int plotIndex, String districtId) =>
      _enqueueDistrict(cityId, plotIndex, districtId, upgrade: false);

  String? upgradeDistrict(String cityId, int plotIndex) {
    final district = state.districtAt(cityId, plotIndex);
    if (district == null) return '増強する地区がありません';
    return _enqueueDistrict(
      cityId,
      plotIndex,
      district.districtId,
      upgrade: true,
    );
  }

  String? _enqueueDistrict(
    String cityId,
    int plotIndex,
    String districtId, {
    required bool upgrade,
  }) {
    final preview = state.districtPreview(
      cityId,
      plotIndex,
      districtId,
      upgrade: upgrade,
    );
    if (!preview.isValid) return preview.blockedReason;
    if (state.activePlanCount >= GameContent.maxActivePlans) {
      return '予約は最大${GameContent.maxActivePlans}件です';
    }
    final definition = GameContent.districts[districtId]!;
    final plan = PlannedTask(
      id: 'plan-${state.nextPlanId++}',
      taskId: definition.taskId(upgrade: upgrade),
      cityId: cityId,
      plotIndex: plotIndex,
      targetLevel: preview.targetLevel,
    );
    state.plans.add(plan);
    if (state.firstRunTutorial == FirstRunTutorialStep.placeHousing &&
        !upgrade &&
        cityId == 'earth_delta' &&
        districtId == 'housing') {
      state.firstRunTutorialPlanId = plan.id;
      state.firstRunTutorial = FirstRunTutorialStep.finishConstruction;
    }
    _record(
      '${state.cityName(cityId)}の区画${plotIndex + 1}に${definition.name} Lv.${preview.targetLevel}を予約',
    );
    _stabilize();
    return null;
  }

  /// Luna finishes only the paid first housing iteration. Normal completion
  /// applies its population, district and notice exactly once; no other clock,
  /// reservation, income interval or research is accelerated.
  String? completeTutorialConstruction() {
    if (state.firstRunTutorial != FirstRunTutorialStep.finishConstruction) {
      return '最初の住宅を配置してから、ルナの建設補助を使ってください';
    }
    final plan = state.plans
        .where((plan) => plan.id == state.firstRunTutorialPlanId)
        .firstOrNull;
    if (plan == null ||
        plan.definition.districtId != 'housing' ||
        plan.definition.isDistrictUpgrade ||
        plan.cityId != 'earth_delta' ||
        plan.targetLevel != 1 ||
        plan.status != 'running' ||
        plan.completedRuns != 0 ||
        plan.remainingRepeats != 1) {
      return '住宅の建設が始まってから、ルナの建設補助を使えます';
    }
    plan.remainingMs = 0;
    _complete(plan);
    _record('ルナの建設補助で、最初の住宅が完成しました');
    _stabilize();
    return null;
  }

  /// Acknowledgements never grant money, research, or new achievements.
  String? continueFirstRunTutorial() {
    switch (state.firstRunTutorial) {
      case FirstRunTutorialStep.income:
        state.firstRunTutorial =
            state.research.contains('life_support') ||
                state.plans.any(
                  (plan) =>
                      plan.taskId == 'life_support' &&
                      (plan.status == 'running' || plan.status == 'completed'),
                )
            ? FirstRunTutorialStep.researchStarted
            : FirstRunTutorialStep.startResearch;
        return null;
      case FirstRunTutorialStep.researchStarted:
        state.firstRunTutorial = FirstRunTutorialStep.completed;
        return null;
      default:
        return '案内中の操作を終えてから進んでください';
    }
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
      if (state.firstRunTutorial == FirstRunTutorialStep.finishConstruction &&
          plan.id == state.firstRunTutorialPlanId) {
        state.firstRunTutorial = FirstRunTutorialStep.placeHousing;
        state.firstRunTutorialPlanId = null;
      }
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

  String? assignResearchers(int count) {
    final reason = state.staffAllocationReason(count);
    if (reason != null) return reason;
    if (state.researchers == count) return null;
    state.researchers = count;
    _record('専門職を研究$count名・工業${state.industrialWorkers}名へ配分。次の着工から適用');
    _stabilize();
    return null;
  }

  String? choosePartnership(String eventId, String choiceId) {
    final reason = state.partnershipLockReason(eventId);
    if (reason != null) return reason;
    final event = GameContent.partnerships[eventId]!;
    final choice = event.choices.where((c) => c.id == choiceId).firstOrNull;
    if (choice == null) return '提案された選択肢から選んでください';
    state.partnershipChoices[eventId] = choiceId;
    state.claimedRewards.add('${state.worldId}:partnership:$eventId');
    state.moneyUnits += choice.funding * GameState.moneyScale;
    _record(
      '${event.partner}：${choice.title}を選択${choice.funding > 0 ? '（+${choice.funding}ドル）' : ''}',
    );
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
      return '再開には維持費1分分の${facility.upkeepPerMinute}ドルが必要です（支払は通常どおり）';
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
          if (_requirementReason(plan, includeMoney: false).isNotEmpty) {
            continue;
          }
          final gap =
              state.plannedCost(plan) * GameState.moneyScale - state.moneyUnits;
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
          plan.stopReason = _requirementReason(plan);
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
    if (state.dismissedTipIds.isNotEmpty) {
      final retained = retainedContextualTipDismissals(
        state,
        state.dismissedTipIds,
      );
      state.dismissedTipIds
        ..clear()
        ..addAll(retained);
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

  String _requirementReason(PlannedTask plan, {bool includeMoney = true}) {
    final task = plan.definition;
    if (task.facilityId == 'lab' && state.researchers == 0) {
      return '人員待ち：研究者1名以上が必要';
    }
    if (task.facilityId == 'factory' && state.industrialWorkers == 0) {
      return '人員待ち：工業員1名以上が必要';
    }
    if (task.id == 'train_specialists' &&
        state.specialistCount + GameContent.specialistTrainingCount >
            GameContent.maxSpecialists) {
      return '専門職は上限${GameContent.maxSpecialists}名です。育成の反復を終了してください';
    }
    final researchReasons = researchRequirementReasons(task.id);
    if (researchReasons.isNotEmpty) return researchReasons.join(' / ');
    if (task.requiresHabitatChoice && state.habitatChoice == null) {
      return state.achievements.contains('first_landing')
          ? '分岐待ち：居住方式を選択'
          : '火星輸送後に居住方式を選択';
    }
    if (plan.cityId != null) {
      final cityReason = state.cityLockReason(plan.cityId!);
      if (cityReason != null) return cityReason;
      if (task.isDistrictUpgrade) {
        final prerequisite = GameContent.districts[task.districtId]!
            .researchForUpgrade(plan.targetLevel!);
        if (!state.research.contains(prerequisite)) {
          return '前提研究待ち：${GameContent.tasks[prerequisite]!.name}';
        }
      }
    }
    if (task.inputResource != null &&
        _resource(task.inputResource!) < task.inputAmount) {
      return '資源不足：${GameContent.resourceNames[task.inputResource]}が${task.inputAmount}基必要';
    }
    final cost = state.plannedCost(plan);
    if (includeMoney && state.moneyUnits < cost * GameState.moneyScale) {
      return '資金不足：$costドルが必要';
    }
    return '';
  }

  void _start(PlannedTask plan) {
    final task = plan.definition;
    final cost = state.plannedCost(plan);
    state.moneyUnits -= cost * GameState.moneyScale;
    if (task.inputResource != null) {
      _changeResource(task.inputResource!, -task.inputAmount);
    }
    plan.status = 'running';
    plan.iterationSpecialists = switch (task.facilityId) {
      'lab' => state.researchers,
      'factory' => state.industrialWorkers,
      _ => 0,
    };
    plan.iterationDurationMs = state.plannedDurationMs(plan);
    plan.remainingMs = plan.iterationDurationMs;
    plan.stopReason = '';
    if (state.firstRunTutorial == FirstRunTutorialStep.startResearch &&
        task.id == 'life_support') {
      state.firstRunTutorial = FirstRunTutorialStep.researchStarted;
    }
    _record('${task.name}を開始（-$costドル）');
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
    if (task.outputResource != null) {
      _changeResource(task.outputResource!, task.outputAmount);
    }
    if (task.unique) state.research.add(task.id);
    if (task.districtId != null) {
      final definition = GameContent.districts[task.districtId]!;
      final district = DistrictState(
        cityId: plan.cityId!,
        plotIndex: plan.plotIndex!,
        districtId: definition.id,
        level: plan.targetLevel!,
      );
      state.districts[district.key] = district;
      if (definition.planet == 'earth') {
        state.population += definition.residents;
      }
      if (definition.id == 'mars_habitat') {
        if (!task.isDistrictUpgrade) state.marsHabitats++;
        state.marsResidents += definition.residents;
        _achievement(
          '${state.habitatChoice}_habitat',
          reward: GameContent.achievementReward,
        );
      }
    }
    switch (task.id) {
      case 'train_specialists':
        state.specialistCount += GameContent.specialistTrainingCount;
      case 'earth_expansion':
        state.earthLevel++;
        state.population += GameContent.residentsPerDistrict;
      case 'mars_delivery':
      case 'cargo_delivery':
        _achievement('first_landing', reward: 0);
      case 'build_habitat':
        state.marsHabitats++;
        state.marsResidents += GameContent.residentsPerHabitat;
        _achievement(
          '${state.habitatChoice}_habitat',
          reward: GameContent.achievementReward,
        );
    }
    state.recordCompletion(plan);
    if (state.firstRunTutorial == FirstRunTutorialStep.finishConstruction &&
        plan.id == state.firstRunTutorialPlanId) {
      state.firstRunTutorial = FirstRunTutorialStep.income;
    }
    _record('${task.name}が完了${task.reward == 0 ? '' : '（+${task.reward}ドル）'}');
  }

  void _achievement(String id, {required int reward}) {
    state.achievements.add(id);
    final rewardKey = '${state.worldId}:achievement:$id';
    if (state.claimedRewards.add(rewardKey)) {
      state.moneyUnits += reward * GameState.moneyScale;
      _record(
        '実績：${GameContent.achievementNames[id]}${reward == 0 ? '' : '（+$rewardドル）'}',
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
