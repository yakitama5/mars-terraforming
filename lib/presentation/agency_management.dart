import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/game_state.dart';
import 'strategy_widgets.dart';

class AgencyManagement extends StatefulWidget {
  const AgencyManagement({
    super.key,
    required this.controller,
    required this.section,
    required this.onSectionChanged,
    required this.onOpenOperations,
  });
  final GameController controller;
  final int section;
  final ValueChanged<int> onSectionChanged;
  final VoidCallback onOpenOperations;

  @override
  State<AgencyManagement> createState() => _AgencyManagementState();
}

class _AgencyManagementState extends State<AgencyManagement> {
  int get section => widget.section;
  int? proposedResearchers;
  GameState get game => widget.controller.state;

  @override
  Widget build(BuildContext context) => StrategySplit(
    overview: _metrics(),
    detail: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 5, 8, 0),
          child: Row(
            children: [
              for (final (index, id, label) in [
                (0, 'staff', '人員配分'),
                (1, 'partnerships', '提携・支援'),
              ])
                Expanded(
                  child: TextButton(
                    key: Key('agency-section-$id'),
                    onPressed: () => widget.onSectionChanged(index),
                    style: TextButton.styleFrom(
                      foregroundColor: section == index
                          ? strategyMint
                          : strategyMuted,
                      backgroundColor: section == index
                          ? strategySelected
                          : null,
                    ),
                    child: Text(label),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: section == 0 ? _staff() : _partnerships()),
      ],
    ),
  );

  Widget _metrics() {
    final status = game.agencyStatus;
    final metrics = <(String, String, String, String, IconData)>[
      (
        '資金',
        dollars(game.money),
        '研究・建設・人員育成に使う運転資金。',
        '税収・外部受注・提携支援で増加。現在 ${signedDollars(game.netPerMinute)}/分（税収−維持費）。',
        Icons.account_balance_wallet_outlined,
      ),
      (
        '知名度',
        '${status.fame} / 100点',
        '機関の開発実績を表す指標。',
        GameContent.agencyMetricDescriptions['fame']!,
        Icons.campaign_outlined,
      ),
      (
        '技術力',
        '${status.technology} / 100点',
        '研究によって得た技術の蓄積。',
        GameContent.agencyMetricDescriptions['technology']!,
        Icons.science_outlined,
      ),
      (
        '研究者',
        '${game.researchers}人',
        '研究所へ割り当てた専門職。',
        '右の人員配分で変更。研究所の人員効果 ${signedNumber(game.staffEfficiencyBonus('lab'))}%。育成で総人数を増やせます。',
        Icons.school_outlined,
      ),
      (
        '工業員',
        '${game.industrialWorkers}人',
        '共用工場へ割り当てた専門職。',
        '右の人員配分で変更。工場の人員効果 ${signedNumber(game.staffEfficiencyBonus('factory'))}%。受注・製造・地球建設を担当します。',
        Icons.engineering_outlined,
      ),
      (
        '友好',
        '${status.friendship} / 100点',
        '提携先との協力関係の指標。',
        GameContent.agencyMetricDescriptions['friendship']!,
        Icons.handshake_outlined,
      ),
      (
        '宇宙支援貢献',
        '${status.spaceContribution} / 100点',
        '宇宙開発へ寄与した実績の指標。',
        GameContent.agencyMetricDescriptions['spaceContribution']!,
        Icons.rocket_launch_outlined,
      ),
    ];
    return ListView(
      key: const Key('agency-metrics'),
      padding: const EdgeInsets.all(14),
      children: [
        const StrategyHeading('機関を育てる', '人員と提携を整え、研究と都市開発を並行して進めます。'),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 440 ? 2 : 1;
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (label, value, meaning, _, icon) in metrics)
                  SizedBox(
                    width: width,
                    child: StrategyCard(
                      key: Key('agency-metric-$label'),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(icon, size: 18, color: strategyMint),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            value,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: strategyMint,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(meaning, style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        ExpansionTile(
          key: const Key('agency-metric-explanations'),
          tilePadding: EdgeInsets.zero,
          title: const Text('指標の意味と増やし方', style: TextStyle(fontSize: 13)),
          children: [
            for (final (label, _, _, effect, _) in metrics)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: strategyMint,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      effect,
                      style: const TextStyle(
                        color: strategyMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _staff() => LayoutBuilder(
    builder: (context, constraints) => _staffPanel(
      // Keep enough space to expose the whole allocation control on phones.
      scrollConfirmation: constraints.maxHeight < 240,
    ),
  );

  Widget _staffPanel({required bool scrollConfirmation}) {
    final minimum = game.reservedResearchers;
    final maximum = game.specialistCount - game.reservedIndustrialWorkers;
    final candidate = (proposedResearchers ?? game.researchers).clamp(
      minimum,
      maximum,
    );
    final reason = game.staffAllocationReason(candidate);
    final training = GameContent.tasks['train_specialists']!;
    final trainingPlan = game.plans
        .where((p) => p.taskId == training.id && !p.isFinished)
        .firstOrNull;
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const Key('agency-staff'),
            padding: const EdgeInsets.all(14),
            children: [
              Text(
                '専門職 ${game.specialistCount}人',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '研究と工場に人員を配分します。',
                style: TextStyle(fontSize: 12, color: strategyMuted),
              ),
              const SizedBox(height: 12),
              StrategyFact(
                '現在の配分',
                '研究 ${game.researchers}人 / 工業 ${game.industrialWorkers}人',
              ),
              Row(
                children: [
                  IconButton(
                    key: const Key('staff-research-less'),
                    tooltip: '研究者を1人減らす',
                    onPressed: candidate <= minimum
                        ? null
                        : () => setState(
                            () => proposedResearchers = candidate - 1,
                          ),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Expanded(
                    child: Text(
                      '研究 $candidate人 / 工業 ${game.specialistCount - candidate}人',
                      key: const Key('staff-proposed'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    key: const Key('staff-research-more'),
                    tooltip: '研究者を1人増やす',
                    onPressed: candidate >= maximum
                        ? null
                        : () => setState(
                            () => proposedResearchers = candidate + 1,
                          ),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: StrategyStat(
                      '研究の人員効果',
                      '${signedNumber(game.staffEfficiencyBonus('lab'))}% → ${signedNumber(game.staffEfficiencyBonusFor('lab', candidate))}%',
                    ),
                  ),
                  Expanded(
                    child: StrategyStat(
                      '工場の人員効果',
                      '${signedNumber(game.staffEfficiencyBonus('factory'))}% → ${signedNumber(game.staffEfficiencyBonusFor('factory', candidate))}%',
                    ),
                  ),
                ],
              ),
              if (game.researchers > 0 &&
                  candidate > game.researchers &&
                  game.facilityBonusPercent('lab') >=
                      game.facilityBonusCap('lab'))
                const Text(
                  '研究効率は現在の上限に達しているため、この増員だけでは工期を短縮できません。',
                  style: TextStyle(fontSize: 11, color: strategyCopper),
                ),
              if (game.industrialWorkers > 0 &&
                  candidate < game.researchers &&
                  game.facilityBonusPercent('factory') >=
                      game.facilityBonusCap('factory'))
                const Text(
                  '製造効率は現在の上限に達しているため、この増員だけでは工期を短縮できません。',
                  style: TextStyle(fontSize: 11, color: strategyCopper),
                ),
              if (game.reservedResearchers > 0 ||
                  game.reservedIndustrialWorkers > 0) ...[
                const SizedBox(height: 10),
                Text(
                  '作業中：研究 ${game.reservedResearchers}人・工業 ${game.reservedIndustrialWorkers}人。完了まで移動できません。',
                  style: const TextStyle(fontSize: 12, color: strategyCopper),
                ),
                TextButton.icon(
                  key: const Key('agency-open-operations'),
                  onPressed: widget.onOpenOperations,
                  icon: const Icon(Icons.reorder, size: 17),
                  label: const Text('設備・進行で反復と予約を確認'),
                ),
              ],
              ExpansionTile(
                key: const Key('staff-allocation-help'),
                tilePadding: EdgeInsets.zero,
                title: const Text('配分のしくみ', style: TextStyle(fontSize: 12)),
                children: const [
                  Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      '±で1人ずつ調整し、下のボタンで確定します。人員効果は設備上限を適用する前の値です。\n\n'
                      '作業中の人数と工期は完成まで固定され、変更は次の着手から反映されます。\n\n'
                      '無期限の反復中は、設備・進行で反復を終了してから現在の1回の完成を待つと再配分できます。設備の休止だけでは人員は解放されません。',
                      style: TextStyle(fontSize: 12, color: strategyMuted),
                    ),
                  ),
                ],
              ),
              if (reason != null)
                Text(
                  reason,
                  style: const TextStyle(fontSize: 12, color: strategyCopper),
                ),
              if (scrollConfirmation) ...[
                const SizedBox(height: 12),
                _staffConfirmation(candidate, reason),
              ],
              const SizedBox(height: 16),
              const Text(
                '専門職を育成する',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '${dollars(training.cost)} · 研究所 ${gameDuration(game.currentTaskDurationMs(training.id))} · ${GameContent.specialistTrainingCount}人増員',
                style: const TextStyle(fontSize: 12, color: strategyMint),
              ),
              const Text(
                '研究所を使って育成し、完成すると工業に加わります。',
                style: TextStyle(fontSize: 11, color: strategyMuted),
              ),
              if (trainingPlan != null)
                Text(
                  trainingPlan.status == 'running'
                      ? trainingPlan.stopReason.isNotEmpty
                            ? '育成停止中 · ${trainingPlan.stopReason}'
                            : '育成中 · 残り ${gameDuration(trainingPlan.remainingMs)}'
                      : '育成を予約済み · ${trainingPlan.stopReason}',
                  style: const TextStyle(fontSize: 12, color: strategyCopper),
                ),
              if (game.money < training.cost && trainingPlan == null)
                Text(
                  '着手にはあと ${dollars(training.cost - game.money)}が必要です。予約して資金を待てます。',
                  style: const TextStyle(fontSize: 11, color: strategyCopper),
                ),
              FilledButton.tonalIcon(
                key: const Key('queue-train_specialists'),
                onPressed:
                    widget.controller.busy ||
                        trainingPlan != null ||
                        game.specialistCount >= GameContent.maxSpecialists
                    ? null
                    : () => widget.controller.command(
                        (engine) => engine.enqueue(training.id),
                      ),
                icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                label: Text(
                  game.specialistCount >= GameContent.maxSpecialists
                      ? '人員上限に達しています'
                      : '専門職の育成を予約',
                ),
              ),
            ],
          ),
        ),
        if (!scrollConfirmation) _staffConfirmation(candidate, reason),
      ],
    );
  }

  Widget _staffConfirmation(int candidate, String? reason) => StrategyActionBar(
    message: candidate == game.researchers
        ? '現在の配分です'
        : '研究 $candidate人 / 工業 ${game.specialistCount - candidate}人に変更',
    child: FilledButton(
      key: const Key('confirm-staff-allocation'),
      onPressed:
          candidate == game.researchers ||
              reason != null ||
              widget.controller.busy
          ? null
          : () async {
              await widget.controller.command(
                (engine) => engine.assignResearchers(candidate),
              );
              if (mounted) setState(() => proposedResearchers = null);
            },
      child: const Text('人員配分を確定'),
    ),
  );

  Future<void> _confirmPartnership(
    PartnershipDefinition event,
    PartnershipChoice choice,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(choice.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(event.title, style: const TextStyle(color: strategyMint)),
            const SizedBox(height: 10),
            Text(choice.description),
            const SizedBox(height: 10),
            if (choice.funding > 0)
              StrategyFact('支援金', dollars(choice.funding)),
            for (final bonus in choice.efficiencyBonuses.entries)
              StrategyFact(
                GameContent.facilities[bonus.key]!.name,
                '効率 ${signedNumber(bonus.value)}%',
              ),
            StrategyFact(
              '協力の成果',
              '友好 ${signedNumber(choice.friendship)}点 / 宇宙支援貢献 ${signedNumber(choice.spaceContribution)}点',
            ),
            const SizedBox(height: 10),
            const Text(
              'この協定の選択は一度だけです。決定後は別の提案に変更できません。',
              style: TextStyle(color: strategyCopper, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: Key('cancel-partnership-${event.id}'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('比較に戻る'),
          ),
          FilledButton(
            key: Key('confirm-partnership-${event.id}-${choice.id}'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('この提案で決定'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await widget.controller.command(
      (engine) => engine.choosePartnership(event.id, choice.id),
    );
  }

  Widget _partnerships() => ListView(
    key: const Key('agency-partnerships'),
    padding: const EdgeInsets.all(14),
    children: [
      const StrategyHeading(
        '提携・支援の選択',
        '架空の協力機関による提案です。各協定は一度だけ選び、設備の強化か当面の資金を得ます。',
      ),
      for (final event in GameContent.partnerships.values) ...[
        Text(
          event.title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        Text(
          event.partner,
          style: const TextStyle(fontSize: 12, color: strategyMint),
        ),
        const SizedBox(height: 6),
        Text(
          event.description,
          style: const TextStyle(fontSize: 12, color: strategyMuted),
        ),
        if (game.partnershipLockReason(event.id) case final reason?)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              reason,
              style: const TextStyle(fontSize: 12, color: strategyCopper),
            ),
          ),
        for (final choice in event.choices)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: StrategyCard(
              selected: game.partnershipChoices[event.id] == choice.id,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    choice.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    choice.description,
                    style: const TextStyle(fontSize: 12, color: strategyMuted),
                  ),
                  StrategyFact(
                    '支援金',
                    choice.funding > 0
                        ? dollars(choice.funding)
                        : 'なし · 当面の資金は増えません',
                  ),
                  for (final bonus in choice.efficiencyBonuses.entries)
                    StrategyFact(
                      GameContent.facilities[bonus.key]!.name,
                      '効率 ${signedNumber(bonus.value)}%',
                    ),
                  StrategyFact(
                    '協力の成果',
                    '友好 ${signedNumber(choice.friendship)}点 / 宇宙支援貢献 ${signedNumber(choice.spaceContribution)}点',
                  ),
                  FilledButton.tonal(
                    key: Key('partnership-${event.id}-${choice.id}'),
                    onPressed:
                        widget.controller.busy ||
                            game.partnershipLockReason(event.id) != null
                        ? null
                        : () => _confirmPartnership(event, choice),
                    child: Text(
                      game.partnershipChoices[event.id] == choice.id
                          ? '選択済み'
                          : 'この提案を選ぶ',
                      semanticsLabel: '${event.title}：${choice.title}を選ぶ',
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 22),
      ],
    ],
  );
}
