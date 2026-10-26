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
                (0, 'foundation', '都市基盤'),
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
        Expanded(child: section == 0 ? _foundation() : _partnerships()),
      ],
    ),
  );

  Widget _metrics() {
    final status = game.agencyStatus;
    final metrics = <(String, String, String, String, IconData)>[
      (
        '資金',
        '${dollars(game.money)} / ${dollars(game.moneyCapacity)}',
        '建設・製造・都市運営に使う資金。人口に応じて保有上限が広がります。',
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
        '総人口',
        '${game.totalPopulation}人',
        '研究と投資を支える都市の規模。',
        '全都市の実際の住民数です。人口が増えると、RPと資金の保有上限が広がります。',
        Icons.location_city_outlined,
      ),
      (
        '共通RP',
        '${game.researchPoints.toStringAsFixed(1)} / ${game.researchPointCapacity} RP',
        '全分野の技術解放に使う研究ポイント。',
        '稼働中の研究施設から毎時${game.researchPointsPerHour.toStringAsFixed(1)}RPを生産します。都市条件と必要RPがそろえば、その場で解放できます。',
        Icons.auto_awesome_outlined,
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
        const StrategyHeading('機関を育てる', '都市基盤と提携を育て、研究と都市開発を進めます。'),
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

  Widget _foundation() => ListView(
    key: const Key('agency-foundation'),
    padding: const EdgeInsets.all(14),
    children: [
      const StrategyHeading('都市の基盤', '人口を増やすと保有上限が広がります。\n施設への投資で生産能力を伸ばせます。'),
      StrategyCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StrategyFact('総人口', '${game.totalPopulation}人'),
            StrategyFact(
              '資金（ドル）',
              '${formatInteger(game.money)} / ${formatInteger(game.moneyCapacity)}',
            ),
            StrategyFact(
              '共通RP',
              '${game.researchPoints.toStringAsFixed(1)} / ${game.researchPointCapacity} RP',
            ),
            StrategyFact(
              '研究能力',
              '${game.researchPointsPerHour.toStringAsFixed(1)} RP/時',
            ),
            const SizedBox(height: 8),
            Text(
              game.isMoneyAtCapacity || game.isResearchAtCapacity
                  ? '保有上限に達した資源は追加の蓄積を止めています。研究や建設へ使うか、都市の人口を増やしましょう。'
                  : '人口を増やすと保有上限が広がります。研究施設を増やすとRPの生産能力が上がります。',
              style: const TextStyle(fontSize: 12, color: strategyMuted),
            ),
            const SizedBox(height: 10),
            const Text(
              '施設は電力・資材・維持費を賄って運営します。都市と施設への投資で生産能力を高めましょう。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const Key('foundation-open-operations'),
        onPressed: widget.onOpenOperations,
        icon: const Icon(Icons.factory_outlined, size: 17),
        label: const Text('施設の稼働と進行を確認'),
      ),
    ],
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
      for (final event in GameContent.partnerships.values.where(
        (event) =>
            event.requiredResearch == null ||
            game.isResearchDiscovered(event.requiredResearch!) ||
            game.partnershipChoices.containsKey(event.id),
      )) ...[
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
