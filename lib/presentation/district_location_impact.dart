import 'package:flutter/material.dart';

import '../domain/game_content.dart';
import '../domain/game_state.dart';
import 'strategy_widgets.dart';

/// Explains the domain's placement result without reproducing its rules.
class DistrictLocationImpact extends StatelessWidget {
  const DistrictLocationImpact({
    super.key,
    required this.game,
    required this.cityId,
    required this.plotIndex,
    required this.preview,
    this.expanded = false,
  });
  final GameState game;
  final String cityId;
  final int plotIndex;
  final DistrictPreview preview;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final city = GameContent.cities[cityId]!;
    final terrain = GameContent.terrainNames[city.terrainAt(plotIndex)]!;
    final neighbors = [
      for (final plot in city.adjacentPlots(plotIndex))
        ?game.districtAt(cityId, plot),
    ];
    final capped =
        preview.researchBonusDelta != preview.rawResearchBonusDelta ||
        preview.factoryBonusDelta != preview.rawFactoryBonusDelta ||
        preview.launchBonusDelta != preview.rawLaunchBonusDelta ||
        preview.marsBonusDelta != preview.rawMarsBonusDelta;
    final explanation = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '辺を共有する最大6区画が隣接。完成した稼働地区同士で効果が生まれます。',
          style: TextStyle(fontSize: 11, color: strategyMuted),
        ),
        const SizedBox(height: 6),
        if (neighbors.isEmpty)
          const Text('隣接する完成地区なし', style: TextStyle(fontSize: 11))
        else
          for (final district in neighbors)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '区画 ${district.plotIndex + 1} · ${GameContent.districts[district.districtId]!.name} Lv.${district.level}'
                '${game.facilities[GameContent.districts[district.districtId]!.operatingFacilityId] == true ? '' : '（休止中）'}',
                style: const TextStyle(fontSize: 11, color: strategyMuted),
              ),
            ),
        const SizedBox(height: 4),
        const Text(
          '周辺地区の変化も含む内訳です。効率は上限適用前。上の完成後効果へ加算する必要はありません。',
          style: TextStyle(fontSize: 11, color: strategyMuted),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (expanded) ...[
          const Text(
            '土地・隣接の効果',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
        ],
        _effectRow('土地 · $terrain', preview.terrainEffects, 'terrain'),
        const SizedBox(height: 6),
        _effectRow('隣接', preview.adjacencyEffects, 'adjacency'),
        if (preview.bonuses.any((bonus) => bonus.startsWith('設備休止中'))) ...[
          const SizedBox(height: 6),
          const StrategyOutcome(
            '設備休止中 · 再開すると効果が有効',
            tone: StrategyTone.warning,
            fontSize: 11,
          ),
        ],
        if (capped) ...[
          const SizedBox(height: 6),
          const StrategyOutcome(
            '効率上限あり · 有効分は上の完成後効果を確認',
            tone: StrategyTone.warning,
            fontSize: 11,
          ),
        ],
        if (expanded) ...[
          const SizedBox(height: 10),
          explanation,
        ] else
          Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              key: const Key('location-impact-explanation'),
              tilePadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              minTileHeight: 40,
              title: const Text('隣接区画と効果の見方', style: TextStyle(fontSize: 11)),
              children: [explanation],
            ),
          ),
      ],
    );
  }

  Widget _effectRow(String title, DistrictEffects effects, String id) => Column(
    key: Key('location-impact-$id'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: const TextStyle(fontSize: 11, color: strategyMuted)),
      if (effects.isEmpty)
        const Text(
          '追加効果なし',
          style: TextStyle(fontSize: 12, color: strategyMuted),
        )
      else
        for (final (label, value, unit) in [
          ('税収', effects.tax, 'ドル/分'),
          ('研究', effects.research, '%'),
          ('製造', effects.factory, '%'),
          ('輸送', effects.launch, '%'),
          ('火星建設', effects.mars, '%'),
        ])
          if (value != 0)
            StrategyOutcome(
              '$label ${signedNumber(value)}$unit',
              tone: value > 0 ? StrategyTone.benefit : StrategyTone.loss,
            ),
    ],
  );
}
