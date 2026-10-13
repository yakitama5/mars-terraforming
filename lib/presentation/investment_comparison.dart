import 'package:flutter/material.dart';

import '../domain/game_content.dart';
import '../domain/game_state.dart';
import 'strategy_widgets.dart';

/// A comparison keeps the player's intended placement, never a stale quote.
class InvestmentCandidate {
  const InvestmentCandidate({
    required this.cityId,
    required this.plotIndex,
    required this.districtId,
    required this.targetLevel,
  });
  final String cityId, districtId;
  final int plotIndex, targetLevel;
  bool get upgrade => targetLevel > 1;
  String get title =>
      '${GameContent.cities[cityId]!.name} · 区画 ${plotIndex + 1}';
  String get action =>
      '${GameContent.districts[districtId]!.name} ${upgrade ? 'Lv.${targetLevel - 1} → $targetLevel' : '新設 Lv.1'}';

  DistrictPreview preview(GameState game) =>
      game.districtPreview(cityId, plotIndex, districtId, upgrade: upgrade);

  String? changedReason(GameState game) {
    if (targetLevel > GameContent.districts[districtId]!.maxLevel) {
      return 'この地区は最大レベルです。別の区画を選んでください。';
    }
    final current = game.districtAt(cityId, plotIndex);
    if (!upgrade && current != null) {
      return current.districtId == districtId
          ? 'この新設候補は完成済みです。増強を比較する場合は保存し直してください。'
          : 'この区画には別の地区が完成しています。候補を保存し直してください。';
    }
    if (upgrade &&
        (current == null ||
            current.districtId != districtId ||
            current.level != targetLevel - 1)) {
      return '保存後に地区の状態が変わりました。次の増強候補を保存し直してください。';
    }
    return null;
  }
}

class InvestmentComparison extends StatelessWidget {
  const InvestmentComparison({
    super.key,
    required this.game,
    required this.saved,
    required this.current,
  });
  final GameState game;
  final InvestmentCandidate saved, current;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(18),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '投資候補を比較',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  key: const Key('close-investment-comparison'),
                  tooltip: '比較を閉じる',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'どちらも今の都市・資金で見積もります。費用と設備の占有時間、空地と隣接効果を比べて、配置を選んでください。',
              style: TextStyle(color: strategyMuted, fontSize: 12),
            ),
          ),
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cards = [
                  _candidateCard(saved, '保存した候補', 'saved'),
                  _candidateCard(current, '現在の候補', 'current'),
                ];
                return SingleChildScrollView(
                  key: const Key('investment-comparison-scroll'),
                  padding: const EdgeInsets.all(16),
                  child: constraints.maxWidth >= 700
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 12),
                            Expanded(child: cards[1]),
                          ],
                        )
                      : Column(
                          children: [
                            cards[0],
                            const SizedBox(height: 12),
                            cards[1],
                          ],
                        ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  Widget _candidateCard(
    InvestmentCandidate candidate,
    String label,
    String id,
  ) {
    final changed = candidate.changedReason(game);
    final preview = candidate.preview(game);
    final plan = game.districtPlanAt(candidate.cityId, candidate.plotIndex);
    final city = GameContent.cities[candidate.cityId]!;
    final summary = game.cityDevelopment(city.id);
    return StrategyCard(
      key: Key('investment-comparison-$id'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: const TextStyle(color: strategyMint, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            candidate.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          Text(candidate.action, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            '${summary.stageName} · 完成 ${summary.completedPlots}/${city.plotCount}区画 · 総Lv.${summary.totalLevels}',
            style: const TextStyle(color: strategyMuted, fontSize: 11),
          ),
          const SizedBox(height: 12),
          if (changed != null)
            Text(changed, style: const TextStyle(color: strategyCopper))
          else ...[
            if (plan != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  plan.status == 'running'
                      ? '着工済み · 残り ${gameDuration(plan.remainingMs)}。下は新たに着工する場合の見積です。'
                      : '予約済み · ${plan.stopReason}',
                  style: const TextStyle(color: strategyCopper, fontSize: 12),
                ),
              ),
            InvestmentEstimate(game: game, preview: preview, cityId: city.id),
            const SizedBox(height: 8),
            for (final bonus in preview.bonuses)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  bonus,
                  style: const TextStyle(fontSize: 12, color: strategyMuted),
                ),
              ),
            if (preview.blockedReason != null)
              Text(
                preview.blockedReason!,
                style: const TextStyle(color: strategyCopper, fontSize: 12),
              )
            else if (game.money < preview.cost)
              Text(
                '資金待ち · あと ${preview.cost - game.money} Cr',
                style: const TextStyle(color: strategyCopper, fontSize: 12),
              )
            else if (city.planet == 'mars' && game.marsKits == 0)
              const Text(
                '到着キット待ち',
                style: TextStyle(color: strategyCopper, fontSize: 12),
              )
            else
              const Text(
                '予約可能 · 着工順は設備の予約で決まります',
                style: TextStyle(color: strategyMint, fontSize: 12),
              ),
          ],
        ],
      ),
    );
  }
}

/// All values, including the cap-adjusted deltas, come from the domain preview.
class InvestmentEstimate extends StatelessWidget {
  const InvestmentEstimate({
    super.key,
    required this.game,
    required this.preview,
    required this.cityId,
  });
  final GameState game;
  final DistrictPreview preview;
  final String cityId;

  @override
  Widget build(BuildContext context) {
    final city = GameContent.cities[cityId]!;
    final facilityId = city.planet == 'earth' ? 'factory' : 'mars';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StrategyFact('投資費合計', '${preview.cost} Cr'),
        StrategyFact('設備占有', '${gameDuration(preview.durationMs)} · 予約待ちを除く'),
        StrategyFact(
          '土地の追加',
          '${preview.additionalPlots}区画${preview.additionalPlots == 0 ? ' · 空地を温存' : ''}',
        ),
        StrategyFact(
          '純収支の変化',
          '${signedNumber(preview.netDeltaPerMinute)} Cr/分',
          color: preview.netDeltaPerMinute >= 0 ? strategyMint : strategyCopper,
        ),
        StrategyFact(
          '税収 / 維持費',
          '${signedNumber(preview.taxDeltaPerMinute)} / ${signedNumber(preview.upkeepDeltaPerMinute)} Cr/分',
        ),
        const SizedBox(height: 6),
        const Text(
          '完成後の効率変化（上限適用後）',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        for (final (label, actual, raw) in [
          ('研究', preview.researchBonusDelta, preview.rawResearchBonusDelta),
          ('製造', preview.factoryBonusDelta, preview.rawFactoryBonusDelta),
          ('輸送', preview.launchBonusDelta, preview.rawLaunchBonusDelta),
          ('火星建設', preview.marsBonusDelta, preview.rawMarsBonusDelta),
        ])
          if (actual != 0 || raw != 0)
            StrategyFact(
              label,
              '${signedNumber(actual)}%${actual != raw ? '（上限前 ${signedNumber(raw)}%）' : ''}',
            ),
        if (preview.rawResearchBonusDelta == 0 &&
            preview.rawFactoryBonusDelta == 0 &&
            preview.rawLaunchBonusDelta == 0 &&
            preview.rawMarsBonusDelta == 0)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 5),
            child: Text(
              'この候補では効率の変化はありません',
              style: TextStyle(fontSize: 12, color: strategyMuted),
            ),
          ),
        const SizedBox(height: 10),
        const Text(
          '費用・工期の内訳',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        StrategyFact('本体', '${preview.baseCost} Cr'),
        StrategyFact('都市整備負荷', '+${preview.developmentCost} Cr'),
        StrategyFact('初回開拓', '+${preview.setupCost} Cr'),
        Text(
          '素工期：本体 ${gameDuration(preview.baseDurationMs)} ＋ 都市整備 ${gameDuration(preview.developmentDurationMs)} ＋ 初回開拓 ${gameDuration(preview.setupDurationMs)}',
          style: const TextStyle(fontSize: 11, color: strategyMuted),
        ),
        StrategyFact(
          '建設設備',
          '${GameContent.facilities[facilityId]!.name} · 効率 +${game.facilityBonusPercent(facilityId)}%',
        ),
        if (city.planet == 'mars')
          StrategyFact('必要資材', '到着キット 1基 / 在庫 ${game.marsKits}基'),
      ],
    );
  }
}
