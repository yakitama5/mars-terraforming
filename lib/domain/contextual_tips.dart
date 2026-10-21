import 'game_content.dart';
import 'game_state.dart';

enum ContextualTipDestination { operations, research, city, agency }

enum ContextualTipOperationsSection { queues, production, transport }

enum ContextualTipAgencySection { staffing, partnerships }

const _learningTipIds = {'parallel-city', 'parallel-research'};

/// A stable, actionable explanation of the current simulation state.
/// IDs deliberately exclude money and remaining time, so ticking the clock
/// never creates a new dismissal or changes the order within a priority.
class ContextualTip {
  const ContextualTip({
    required this.id,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.destination,
    required this.priority,
    this.operationsSection = ContextualTipOperationsSection.queues,
    this.agencySection = ContextualTipAgencySection.staffing,
    this.facilityId,
    this.taskId,
    this.cityId,
  });

  final String id, title, detail, actionLabel;
  final ContextualTipDestination destination;
  final ContextualTipOperationsSection operationsSection;
  final ContextualTipAgencySection agencySection;
  final int priority;
  final String? facilityId, taskId, cityId;
}

/// Reads the engine's already-resolved stop reasons; does not advance, clone,
/// instantiate an engine, or duplicate affordability/progression calculations.
List<ContextualTip> evaluateContextualTips(
  GameState game, {
  Set<String> dismissedIds = const {},
  int limit = 3,
}) {
  if (limit <= 0) return const [];
  final tips = _contextualTipCandidates(game)
    ..removeWhere((tip) => dismissedIds.contains(tip.id))
    ..sort((a, b) {
      final priority = b.priority.compareTo(a.priority);
      return priority == 0 ? a.id.compareTo(b.id) : priority;
    });
  return List.unmodifiable(tips.take(limit));
}

/// Keep learning preferences, but forget a warning once its cause is gone.
/// Run after engine stabilization and before saving a dismissal. This makes a
/// later recurrence visible without recording timestamps or an unbounded log.
Set<String> retainedContextualTipDismissals(
  GameState game,
  Iterable<String> dismissedIds,
) {
  final dismissed = dismissedIds.toSet();
  // Persistent learning preferences do not require recomputing situation tips
  // at every completion boundary during a long offline simulation.
  if (dismissed.every(_learningTipIds.contains)) return dismissed;
  final validIds = {
    ..._learningTipIds,
    for (final tip in _contextualTipCandidates(game)) tip.id,
  };
  return dismissed.where(validIds.contains).toSet();
}

List<ContextualTip> _contextualTipCandidates(GameState game) {
  final tips = <ContextualTip>[];
  for (final facility in GameContent.facilities.values) {
    final current = game.currentPlanFor(facility.id);
    final queue = game.upcomingPlansFor(facility.id);
    final head = current ?? queue.firstOrNull;
    if (head == null) continue;
    if (game.facilities[facility.id] != true) {
      tips.add(
        ContextualTip(
          id: 'paused:${facility.id}:${head.id}',
          title: '${facility.name}の作業が休止中です',
          detail: '再開は手動です。維持費1分分の資金を用意し、設備・進行のスイッチを入れます。支払済みの作業は残り時間から続き、他の設備はそれぞれの条件で動きます。',
          actionLabel: '設備を確認',
          destination: ContextualTipDestination.operations,
          priority: 100,
          facilityId: facility.id,
        ),
      );
      continue;
    }
    if (current == null &&
        head.stopReason.isNotEmpty &&
        !(head.stopReason.contains('居住方式') && game.awaitingHabitatChoice)) {
      final hiddenPrerequisite = head.definition.prerequisiteIds.any(
        (id) => !game.isResearchDiscovered(id),
      );
      final reason = hiddenPrerequisite
          ? '研究を進めて必要な技術を見つけてください'
          : head.stopReason;
      final staff = reason.startsWith('人員待ち');
      final budget = reason.startsWith('資金不足');
      final points = reason.contains('RP') || reason.contains('研究ポイント');
      final resource = reason.startsWith('資源不足');
      final branch = reason.contains('居住方式');
      final trainingLimit = reason.startsWith('専門職は上限');
      final candidateResearch = !staff && !budget && !resource && !branch
          ? head.definition.unique
                ? head.taskId
                : head.definition.prerequisiteIds
                      .where((id) => !game.research.contains(id))
                      .firstOrNull
          : null;
      final researchTask =
          candidateResearch != null &&
              game.isResearchDiscovered(candidateResearch)
          ? candidateResearch
          : null;
      final category = staff
          ? 'staff'
          : budget
          ? 'budget'
          : resource
          ? 'resource'
          : branch
          ? 'branch'
          : trainingLimit
          ? 'training-limit'
          : 'requirements';
      tips.add(
        ContextualTip(
          id: '$category:${head.id}',
          title:
              head.definition.unique && !game.isResearchDiscovered(head.taskId)
              ? '予約した研究の条件を確認'
              : '${head.definition.name}の開始条件を確認',
          detail:
              '$reason。${staff
                  ? '機関運営で専門職を配分できます。'
                  : budget
                  ? '税収や受注で資金を用意できます。後続に受注があれば「次に実行」で前へ移動できます。'
                  : points
                  ? '稼働している研究施設へ研究者を配置すると共通RPが蓄まります。必要量と前提がそろうと、予約した技術が解放されます。'
                  : trainingLimit
                  ? '育成の予約を取り消すと、この研究所の後続を進められます。完了済みの育成は保持されます。'
                  : resource
                  ? '製造・輸送を確認してください。この設備が稼働中なら、資材と資金がそろうと自動で始まります。'
                  : branch
                  ? game.awaitingHabitatChoice
                        ? '輸送・居住で方針を決めると、条件がそろった建設が始まります。'
                        : '月面基地から火星航路を開き、居住キットの火星輸送を完了してください。'
                  : 'この設備が稼働中なら、条件がそろうと自動で始まります。同じ設備の後続は待ち、他の設備は独立して進みます。'}',
          actionLabel: staff
              ? '人員を配分'
              : resource
              ? head.definition.inputResource == 'earthKits'
                    ? '製造を確認'
                    : '輸送を確認'
              : branch
              ? '輸送・居住を確認'
              : researchTask != null
              ? '研究条件を見る'
              : '予約を確認',
          destination: staff
              ? ContextualTipDestination.agency
              : researchTask != null
              ? ContextualTipDestination.research
              : ContextualTipDestination.operations,
          operationsSection: branch
              ? ContextualTipOperationsSection.transport
              : resource
              ? head.definition.inputResource == 'earthKits'
                    ? ContextualTipOperationsSection.production
                    : ContextualTipOperationsSection.transport
              : ContextualTipOperationsSection.queues,
          priority: staff || budget || trainingLimit
              ? 95
              : points
              ? 35
              : 80,
          facilityId: facility.id,
          taskId: researchTask ?? head.taskId,
        ),
      );
    }
    for (var index = 0; index + 1 < queue.length; index++) {
      final plan = queue[index];
      if (plan.remainingRepeats != null) continue;
      tips.add(
        ContextualTip(
          id: 'unlimited:${plan.id}',
          title: '${facility.name}の後続予約が待ち続けます',
          detail:
              '${plan.definition.name}は無期限の反復です。後続の「次に実行」で予約順を変えるか、反復を終了できます。支払済みの現在の1回は続きます。',
          actionLabel: '予約順を確認',
          destination: ContextualTipDestination.operations,
          priority: 90,
          facilityId: facility.id,
          taskId: plan.taskId,
        ),
      );
      break;
    }
  }

  if (game.awaitingHabitatChoice) {
    tips.add(
      const ContextualTip(
        id: 'habitat-choice',
        title: '火星の居住方式を選べます',
        detail: '初輸送が完了しました。輸送・居住でドームか地下居住を選び、火星の都市開発へ進めます。',
        actionLabel: '居住方式を選ぶ',
        destination: ContextualTipDestination.operations,
        operationsSection: ContextualTipOperationsSection.transport,
        priority: 85,
        facilityId: 'mars',
      ),
    );
  }
  if (game.planetUnlocked('moon') && !game.planetUnlocked('mars')) {
    final baseComplete =
        game.districtCount('moon_outpost') > 0 &&
        game.districtCount('moon_spaceport') > 0;
    tips.add(
      ContextualTip(
        id: baseComplete ? 'moon-mars-probe' : 'moon-development',
        title: baseComplete ? '月面基地から火星を探査できます' : '月面開発を始められます',
        detail: baseComplete
            ? '輸送・居住で火星探査機を予約します。打ち上げが完了すると、惑星マップに火星が現れます。'
            : 'キットを月へ輸送し、月面拠点と打ち上げ基地を建設しましょう。月の発電・資源採取は輸送費の削減にもつながります。',
        actionLabel: baseComplete ? '火星探査を開く' : '月面を開く',
        destination: baseComplete
            ? ContextualTipDestination.operations
            : ContextualTipDestination.city,
        operationsSection: ContextualTipOperationsSection.transport,
        cityId: baseComplete ? null : 'moon_south_pole',
        taskId: baseComplete ? 'mars_probe' : null,
        priority: 30,
      ),
    );
  }
  if (game.netPerMinute < 0 && game.money <= game.upkeepPerMinute) {
    tips.add(
      const ContextualTip(
        id: 'low-operating-funds',
        title: '運転資金が少なくなっています',
        detail: '受注収入は完了時に入ります。使っていない設備の休止や予約順を確認しましょう。資金が尽きても税収で立て直せます。',
        actionLabel: '収支と設備を確認',
        destination: ContextualTipDestination.operations,
        priority: 96,
      ),
    );
  }
  final partnerships = game.availablePartnerships;
  if (partnerships.isNotEmpty) {
    tips.add(
      ContextualTip(
        id: 'partnership:${partnerships.first.id}',
        title: '新しい提携の提案があります',
        detail: '資金支援と技術支援の内容を比べて選べます。選ばずに他の開発を続けることもできます。',
        actionLabel: '提携の内容を見る',
        destination: ContextualTipDestination.agency,
        agencySection: ContextualTipAgencySection.partnerships,
        priority: 50,
      ),
    );
  }
  bool idle(String id) =>
      game.facilities[id] == true &&
      game.currentPlanFor(id) == null &&
      game.upcomingPlansFor(id).isEmpty;
  for (final (id, assigned, label) in [
    ('lab', game.labResearchers, '研究者'),
    ('factory', game.industrialWorkers, '工業員'),
  ]) {
    if (assigned != 0 || !idle(id) || game.activePlanCount == 0) continue;
    tips.add(
      ContextualTip(
        id: 'unassigned:$id',
        title: '${GameContent.facilities[id]!.name}に$labelがいません',
        detail: '新しい作業を始めるには1名以上の配分が必要です。機関運営で次の計画に合わせて専門職を配分できます。',
        actionLabel: '人員を配分',
        destination: ContextualTipDestination.agency,
        priority: 55,
        facilityId: id,
      ),
    );
  }
  if ((game.currentPlanFor('lab') != null ||
          game.upcomingPlansFor('lab').any((plan) => plan.definition.unique) ||
          (game.research.isNotEmpty && game.researchPointsPerMinute > 0)) &&
      (game.activePlanCount > 0 || game.research.isNotEmpty) &&
      game.facilities['lab'] == true &&
      idle('factory') &&
      game.industrialWorkers > 0) {
    tips.add(
      const ContextualTip(
        id: 'parallel-city',
        title: '研究中も都市を開発できます',
        detail: '施設でRPを蓄える間も、工場や都市は並行して動きます。研究者と工業員を配分し、住宅や産業への投資を検討しましょう。',
        actionLabel: '都市を開く',
        destination: ContextualTipDestination.city,
        priority: 20,
        cityId: 'earth_delta',
      ),
    );
  }
  final nextResearch = GameContent.tasks.values
      .where(
        (task) =>
            task.unique &&
            game.isResearchDiscovered(task.id) &&
            !game.research.contains(task.id),
      )
      .firstOrNull;
  if (game.currentPlanFor('factory') != null &&
      game.facilities['factory'] == true &&
      idle('lab') &&
      game.researchers > 0 &&
      nextResearch != null) {
    tips.add(
      ContextualTip(
        id: 'parallel-research',
        title: '工場の作業中に次の研究を検討できます',
        detail: '共通RPは、どの分野の技術にも使えます。見つかった技術の必要RPと解放先を比較し、次の投資を選べます。',
        actionLabel: '研究ツリーを開く',
        destination: ContextualTipDestination.research,
        taskId: nextResearch.id,
        priority: 20,
      ),
    );
  }
  return tips;
}
