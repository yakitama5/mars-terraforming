import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/game_state.dart';
import '../domain/onboarding_guide.dart';
import 'strategy_widgets.dart';
import 'mission_adviser.dart';
import 'mission_dialogue.dart';

class EarlyDevelopmentGuide extends StatelessWidget {
  const EarlyDevelopmentGuide({
    super.key,
    required this.controller,
    required this.compact,
    required this.onResearch,
    required this.onCity,
    required this.onOperations,
    required this.onAgency,
  });
  final GameController controller;
  final bool compact;
  final ValueChanged<String> onResearch, onCity;
  final void Function(int section, {String? facilityId}) onOperations;
  final ValueChanged<int> onAgency;
  GameState get game => controller.state;

  PlannedTask? _plan(String id) => game.plans
      .where((plan) => plan.taskId == id && !plan.isFinished)
      .firstOrNull;

  String _taskStatus(String id) {
    final plan = _plan(id);
    if (plan != null) {
      if (_isStopped(plan)) return '停止中 · ${_stopReason(plan)}';
      return plan.status == 'running'
          ? '進行中 · 残り ${gameDuration(plan.remainingMs)}'
          : '予約済み · ${plan.stopReason.isEmpty ? '順番を確認' : plan.stopReason}';
    }
    final task = GameContent.tasks[id]!;
    final missing = (task.cost - game.money).clamp(0, task.cost);
    return '必要 ${dollars(task.cost)} · ${gameDuration(game.currentTaskDurationMs(id))}'
        '${missing > 0 ? '（あと ${dollars(missing)}）' : ' · 資金あり'}';
  }

  bool _isStopped(PlannedTask plan) =>
      !plan.isFinished &&
      (game.facilities[plan.definition.facilityId] != true ||
          (plan.stopReason.isNotEmpty && plan.stopReason != '共用設備の順番待ち'));

  String _stopReason(PlannedTask plan) =>
      plan.stopReason.isNotEmpty ? plan.stopReason : '設備休止中・手動で再開';

  void _openStep(OnboardingStep step) {
    switch (step.destination) {
      case OnboardingDestination.research:
        onResearch(step.target);
      case OnboardingDestination.city:
        onCity(step.target);
      case OnboardingDestination.operations:
        onOperations(int.parse(step.target), facilityId: step.facilityId);
    }
  }

  String _stepStatus(OnboardingStep step) => switch (step.status) {
    OnboardingStatus.completed => '達成済み',
    OnboardingStatus.running => '進行中 · 残り ${gameDuration(step.remainingMs)}',
    OnboardingStatus.queued => '予約済み · 設備の順番待ち',
    OnboardingStatus.stopped => '停止中 · ${step.reason}',
    OnboardingStatus.locked => '準備中 · ${step.reason}',
    OnboardingStatus.available => '次に取り組めます',
  };

  String _stepAction(OnboardingStep step) => switch (step.destination) {
    OnboardingDestination.research => step.isCompleted ? '研究成果を見る' : '研究を開く',
    OnboardingDestination.city => step.isCompleted ? '完成した都市を見る' : '都市を開く',
    OnboardingDestination.operations => switch (step.target) {
      '0' => '進み具合・予約順を見る',
      '1' => '製造・受注を開く',
      _ => '輸送・居住を開く',
    },
  };

  MinaExpression _stepExpression(OnboardingStep step) => switch (step.status) {
    OnboardingStatus.completed => MinaExpression.joy,
    OnboardingStatus.stopped => MinaExpression.sorrow,
    OnboardingStatus.available
        when step.id == 'first_landing' || step.id == 'first_habitat' =>
      MinaExpression.delight,
    _ => MinaExpression.normal,
  };

  Widget _roadmapStep(
    OnboardingStep step,
    int index, {
    required bool selected,
    required VoidCallback onOpen,
  }) {
    final status = switch (step.status) {
      OnboardingStatus.completed => '達成済み',
      OnboardingStatus.running => '進行中',
      OnboardingStatus.queued => '予約済み',
      OnboardingStatus.stopped => '停止中',
      OnboardingStatus.locked => '準備中',
      OnboardingStatus.available => '未着手',
    };
    final color = step.status == OnboardingStatus.stopped
        ? strategyCopper
        : step.isCompleted
        ? strategyMuted
        : strategyMint;
    return Material(
      key: Key('onboarding-step-${step.id}'),
      color: selected ? strategySelected : Colors.transparent,
      child: InkWell(
        key: Key('onboarding-toggle-${step.id}'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: step.isCompleted
                    ? Icon(Icons.check_circle_outline, color: color, size: 20)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$status · 目安 ${step.timeHint}',
                      style: TextStyle(fontSize: 11, color: color),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 20, color: strategyMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _showRoadmap(BuildContext context) {
    final initialGuide = OnboardingGuide.fromState(game);
    var selectedId =
        initialGuide.steps.where((step) => !step.isCompleted).firstOrNull?.id ??
        initialGuide.steps.last.id;
    var viewingList = false;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateSelection) => ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            if (controller.engine == null) {
              return AlertDialog(
                title: const Text('手引きを更新できません'),
                content: const Text(
                  '進行状態を確認できないため、案内を停止しました。閉じて保存状態を確認してください。',
                ),
                actions: [
                  TextButton(
                    key: const Key('onboarding-close'),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('閉じる'),
                  ),
                ],
              );
            }
            final guide = OnboardingGuide.fromState(game);
            final selected = guide.steps.firstWhere(
              (step) => step.id == selectedId,
            );
            final text =
                '${selected.story}\n\n${selected.lesson}'
                '${guide.isComplete && selected.id == guide.steps.last.id ? '\n\nここからは、あなたの計画です。収入が足りなければ街と受注、開発を速めるなら研究、火星を育てるなら製造と輸送を見直しましょう。' : ''}';
            return Dialog(
              key: const Key('onboarding-dialogue-dialog'),
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 1000,
                  maxHeight: 600,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: MediaQuery.sizeOf(context).height,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Material(
                        color: strategyPanel.withValues(alpha: .94),
                        borderRadius: BorderRadius.circular(12),
                        child: Row(
                          children: [
                            if (!viewingList)
                              TextButton.icon(
                                key: const Key('onboarding-list'),
                                onPressed: () =>
                                    updateSelection(() => viewingList = true),
                                icon: const Icon(Icons.list_alt, size: 18),
                                label: const Text('6工程'),
                              )
                            else
                              const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '最初の1時間の手引き · ${guide.completedCount}/6達成',
                                maxLines: 2,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              key: const Key('onboarding-close'),
                              tooltip: '閉じて開発を続ける',
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: viewingList
                            ? Material(
                                color: strategyPanel.withValues(alpha: .94),
                                borderRadius: BorderRadius.circular(12),
                                child: SingleChildScrollView(
                                  key: const Key('onboarding-roadmap-scroll'),
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '時間は目安です。順番や期限の制限はなく、自由に進められます。1時間を過ぎても手引きを使えます。',
                                        style: TextStyle(
                                          color: strategyMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '開始から ${gameDuration(guide.elapsedMs)}（不在中を含む）',
                                        style: const TextStyle(
                                          color: strategyMuted,
                                          fontSize: 11,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      for (final (index, step)
                                          in guide.steps.indexed)
                                        _roadmapStep(
                                          step,
                                          index,
                                          selected: selectedId == step.id,
                                          onOpen: () => updateSelection(() {
                                            selectedId = step.id;
                                            viewingList = false;
                                          }),
                                        ),
                                    ],
                                  ),
                                ),
                              )
                            : MissionDialogue(
                                key: Key('onboarding-story-${selected.id}'),
                                title: selected.title,
                                text: text,
                                dialogueKey:
                                    'onboarding-${selected.id}-${selected.status.name}',
                                expression: _stepExpression(selected),
                                // Live remaining time does not restart the dialogue.
                                actions: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _stepStatus(selected),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            selected.status ==
                                                OnboardingStatus.stopped
                                            ? strategyCopper
                                            : strategyMint,
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        key: Key(
                                          'onboarding-open-${selected.id}',
                                        ),
                                        onPressed: () {
                                          Navigator.of(dialogContext).pop();
                                          _openStep(selected);
                                        },
                                        icon: const Icon(
                                          Icons.arrow_forward,
                                          size: 16,
                                        ),
                                        label: Text(_stepAction(selected)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final guide = OnboardingGuide.fromState(game);
    final shortResearch = [
      for (final id in [
        'process_design',
        'cargo_packaging',
        'habitat_operations',
      ])
        if (!game.research.contains(id) &&
            _plan(id) == null &&
            controller.engine!.researchRequirementReasons(id).isEmpty)
          GameContent.tasks[id]!,
    ];
    final labWork = game.currentPlanFor('lab');
    late String title, detail;
    late VoidCallback open;
    var actionLabel = '研究を開く';
    var actionIcon = Icons.science_outlined;
    var expression = MinaExpression.normal;
    String? focusedTask;
    if (!game.research.contains('life_support')) {
      focusedTask = 'life_support';
      title = '生命維持の実証';
      detail = _taskStatus('life_support');
      open = () => onResearch('life_support');
    } else if (!game.research.contains('urban_planning')) {
      focusedTask = 'urban_planning';
      title = '都市基盤の計画';
      detail = _taskStatus('urban_planning');
      open = () => onResearch('urban_planning');
    } else if (!game.achievements.contains('first_landing')) {
      final delivery = _plan('mars_delivery') ?? _plan('cargo_delivery');
      final preparingDelivery = game.earthKits > 0 || delivery != null;
      if (preparingDelivery) expression = MinaExpression.delight;
      focusedTask = preparingDelivery
          ? delivery?.taskId ?? 'mars_delivery'
          : _plan('batch_habitat_kit')?.taskId ?? 'habitat_kit';
      title = preparingDelivery ? '火星への輸送を準備' : '居住キットを製造';
      detail = _taskStatus(focusedTask);
      open = () => onOperations(preparingDelivery ? 2 : 1);
      actionLabel = preparingDelivery ? '輸送・居住を開く' : '製造・受注を開く';
      actionIcon = preparingDelivery
          ? Icons.rocket_launch_outlined
          : Icons.inventory_2_outlined;
    } else if (game.habitatChoice == null) {
      expression = MinaExpression.joy;
      title = '火星の居住方式を選ぶ';
      detail = '初輸送は完了 · ドームか地下居住を選べます';
      open = () => onOperations(2);
      actionLabel = '居住方式を選ぶ';
      actionIcon = Icons.home_outlined;
    } else if (game.marsHabitats == 0) {
      focusedTask = _plan('build_habitat')?.taskId ?? 'district_mars_habitat';
      title = '火星の居住地区を建設';
      final plan = game.plans
          .where((plan) => plan.taskId == focusedTask && !plan.isFinished)
          .firstOrNull;
      detail = plan == null
          ? '到着キット ${game.marsKits}基 · 区画を選び費用と隣接を比較'
          : '${plan.status == 'running' ? '建設中' : '予約済み'} · ${plan.stopReason.isEmpty ? '残り ${gameDuration(plan.remainingMs)}' : plan.stopReason}';
      open = () => onCity('mars_arcadia');
      actionLabel = '建設する区画を選ぶ';
      actionIcon = Icons.location_city_outlined;
    } else if (labWork != null) {
      focusedTask = labWork.taskId;
      title = '${labWork.definition.name}を進める';
      detail = '進行中 · 残り ${gameDuration(labWork.remainingMs)} · 都市計画は並行できます';
      open = labWork.definition.unique
          ? () => onResearch(labWork.taskId)
          : () => onAgency(0);
      if (!labWork.definition.unique) {
        actionLabel = '人員育成を確認する';
        actionIcon = Icons.groups_outlined;
      }
    } else if (shortResearch.isNotEmpty) {
      expression = MinaExpression.delight;
      title = '短い応用研究を選ぶ（任意）';
      detail =
          '${shortResearch.first.name}：${_taskStatus(shortResearch.first.id)}';
      open = () => onResearch(shortResearch.first.id);
    } else if (game.specialistCount == GameContent.initialSpecialists) {
      expression = MinaExpression.delight;
      focusedTask = 'train_specialists';
      title = '次の研究に向け人員育成も検討';
      detail = _taskStatus('train_specialists');
      open = () => onAgency(0);
      actionLabel = '人員育成を確認する';
      actionIcon = Icons.groups_outlined;
    } else {
      expression = MinaExpression.delight;
      title = '研究と都市の次の投資を選ぶ';
      detail = '地区の実証を重ねて増強・新都市・長期受注へ';
      open = () => onResearch('automated_fabrication');
    }
    if (guide.isComplete) expression = MinaExpression.joy;
    final focusedPlan = focusedTask == null ? null : _plan(focusedTask);
    if (focusedPlan != null && _isStopped(focusedPlan)) {
      expression = MinaExpression.sorrow;
      title = '${focusedPlan.definition.name}の停止を確認・再開';
      detail = '停止中 · ${_stopReason(focusedPlan)}';
      open = () =>
          onOperations(0, facilityId: focusedPlan.definition.facilityId);
      actionLabel = '停止理由を確認する';
      actionIcon = Icons.pause_circle_outline;
    } else if (focusedPlan != null) {
      open = () =>
          onOperations(0, facilityId: focusedPlan.definition.facilityId);
      actionLabel = '進み具合・予約順を見る';
      actionIcon = Icons.view_timeline_outlined;
    } else if (focusedTask != null &&
        GameContent.tasks[focusedTask]!.cost > game.money) {
      expression = MinaExpression.sorrow;
      title = '${GameContent.tasks[focusedTask]!.name}の資金を準備';
      detail = '${_taskStatus(focusedTask)} · 受注や提携支援を確認';
      open = game.availablePartnerships.isNotEmpty
          ? () => onAgency(1)
          : () => onOperations(1);
      actionLabel = game.availablePartnerships.isNotEmpty
          ? '提携支援を確認する'
          : '受注で資金を準備する';
      actionIcon = Icons.payments_outlined;
    }
    final hasEarthDistrict =
        game.earthLevel > 1 ||
        game.districts.values.any((d) => d.cityId == 'earth_delta');
    final cityLabel = hasEarthDistrict
        ? '地区を比較・増強'
        : '住宅 ${dollars(GameContent.districts['housing']!.cost)}';
    final availablePartnerships = game.availablePartnerships.length;
    return StrategyCard(
      selected: true,
      padding: EdgeInsets.all(compact ? 9 : 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;
              final fullLabel = constraints.maxWidth >= 420 * textScale;
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      guide.isComplete
                          ? '導入達成 · 次にできること'
                          : '最初の1時間 · ${guide.completedCount}/${guide.steps.length}達成',
                      style: TextStyle(
                        color: strategyMint,
                        fontSize: compact ? 10 : 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: '導入の手順と達成状況を確認',
                    child: TextButton.icon(
                      key: const Key('guide-roadmap'),
                      onPressed: () => _showRoadmap(context),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: strategyMint,
                      ),
                      icon: const Icon(Icons.menu_book_outlined, size: 17),
                      label: Text(
                        fullLabel ? '6工程の手引き' : '手引き',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          LinearProgressIndicator(
            key: const Key('onboarding-progress'),
            value: guide.progress,
            minHeight: 2,
            color: strategyMint,
            backgroundColor: strategyLine,
            semanticsLabel:
                '導入の達成状況 ${guide.completedCount}/${guide.steps.length}達成',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              MinaAvatar(size: 34, expression: expression),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            detail,
            style: const TextStyle(color: strategyMuted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('next-goal'),
            onPressed: open,
            style: FilledButton.styleFrom(
              alignment: Alignment.centerLeft,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            icon: Icon(actionIcon, size: 18),
            label: Text(
              actionLabel,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          if (game.research.contains('urban_planning') &&
              labWork == null &&
              shortResearch.isNotEmpty)
            PopupMenuButton<String>(
              key: const Key('guide-short-research'),
              tooltip: '並行してできる短い研究（任意）',
              onSelected: onResearch,
              itemBuilder: (_) => [
                for (final task in shortResearch)
                  PopupMenuItem(
                    key: Key('guide-research-${task.id}'),
                    value: task.id,
                    child: Text(
                      '${task.name} · ${dollars(task.cost)} · ${gameDuration(game.currentTaskDurationMs(task.id))}',
                    ),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '並行してできる短い研究（任意） ▼',
                  style: TextStyle(fontSize: 11, color: strategyMint),
                ),
              ),
            ),
          if (labWork == null && game.upcomingPlansFor('lab').isNotEmpty)
            TextButton(
              key: const Key('guide-lab-queue'),
              onPressed: () => onOperations(0, facilityId: 'lab'),
              child: const Text(
                '研究所に予約あり · 設備配分で順番を確認',
                style: TextStyle(fontSize: 11, color: strategyCopper),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  key: const Key('guide-city'),
                  onPressed: () => onCity('earth_delta'),
                  child: Text(
                    cityLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              Expanded(
                child: TextButton(
                  key: Key(
                    availablePartnerships > 0
                        ? 'guide-partnership'
                        : 'guide-contract',
                  ),
                  onPressed: availablePartnerships > 0
                      ? () => onAgency(1)
                      : () => onOperations(1),
                  child: Text(
                    availablePartnerships > 0
                        ? '提携支援 $availablePartnerships件'
                        : '受注で資金を準備',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
