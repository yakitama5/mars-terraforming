import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import 'strategy_widgets.dart';

class ResourceOverviewDialog extends StatelessWidget {
  const ResourceOverviewDialog({
    super.key,
    required this.controller,
    required this.onOpenAgency,
  });

  final GameController controller;
  final VoidCallback onOpenAgency;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final game = controller.engine?.state;
      return AlertDialog(
        title: const Text('国力と収支'),
        content: SizedBox(
          width: 480,
          child: game == null
              ? const Text('保存状態を確認してください。')
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StrategyFact(
                        '資金',
                        '${dollars(game.money)} / ${dollars(game.moneyCapacity)}',
                      ),
                      StrategyFact(
                        '毎分収支',
                        '${signedDollars(game.netPerMinute)}/分',
                      ),
                      StrategyFact('税収', '${dollars(game.taxPerMinute)}/分'),
                      StrategyFact('維持費', '${dollars(game.upkeepPerMinute)}/分'),
                      if (game.planetUnlocked('moon')) ...[
                        StrategyFact('月面の居住キット', '${game.moonKits} 基'),
                        StrategyFact(
                          '打ち上げ費用の削減',
                          '−${game.launchCostReductionPercent}%',
                        ),
                      ],
                      const Text(
                        '受注の報酬と建設・製造の開始費用は毎分収支に含みません。維持費は上限到達後も通常どおり支払います。',
                        style: TextStyle(fontSize: 12, color: strategyMuted),
                      ),
                      const Divider(),
                      StrategyFact(
                        '共通研究ポイント',
                        '${game.researchPoints.toStringAsFixed(1)} / ${game.researchPointCapacity} RP',
                      ),
                      StrategyFact(
                        '研究ポイントの生産',
                        '${game.researchPointsPerHour.toStringAsFixed(1)} RP/時',
                      ),
                      const Text(
                        '稼働中の研究施設がRPを生産します。必要RPと都市条件がそろうと、その場で技術を解放できます。',
                        style: TextStyle(fontSize: 12, color: strategyMuted),
                      ),
                      const SizedBox(height: 10),
                      StrategyFact('総人口', '${game.totalPopulation}人'),
                      const Text(
                        '人口に応じて資金とRPの保有上限が広がります。人口減少や更新で上限を超えた分は保持し、追加の蓄積だけを止めます。',
                        style: TextStyle(fontSize: 12, color: strategyMuted),
                      ),
                      StrategyFact('技術力', '${game.agencyStatus.technology}'),
                      StrategyFact('知名度', '${game.agencyStatus.fame}'),
                      StrategyFact('友好度', '${game.agencyStatus.friendship}'),
                      StrategyFact(
                        '宇宙貢献',
                        '${game.agencyStatus.spaceContribution}',
                      ),
                      const Text(
                        '研究・都市開発・提携で国力が育ち、新しい協力先が見つかります。',
                        style: TextStyle(fontSize: 12, color: strategyMuted),
                      ),
                    ],
                  ),
                ),
        ),
        actions: [
          if (game != null)
            TextButton(
              key: const Key('resources-open-agency'),
              onPressed: () {
                Navigator.pop(context);
                onOpenAgency();
              },
              child: const Text('都市基盤・提携を開く'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      );
    },
  );
}
