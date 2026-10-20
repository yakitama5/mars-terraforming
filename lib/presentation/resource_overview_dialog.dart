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
                      StrategyFact('資金', dollars(game.money)),
                      StrategyFact(
                        '毎分収支',
                        '${signedDollars(game.netPerMinute)}/分',
                      ),
                      StrategyFact('税収', '${dollars(game.taxPerMinute)}/分'),
                      StrategyFact('維持費', '${dollars(game.upkeepPerMinute)}/分'),
                      const Text(
                        '受注の報酬と、建設・製造・育成の開始費用は毎分収支に含みません。研究施設の維持費は含みます。',
                        style: TextStyle(fontSize: 12, color: strategyMuted),
                      ),
                      const Divider(),
                      StrategyFact(
                        '共通研究ポイント',
                        '${game.researchPoints.toStringAsFixed(1)} RP',
                      ),
                      StrategyFact(
                        '研究ポイントの生産',
                        '${game.researchPointsPerMinute.toStringAsFixed(1)} RP/分',
                      ),
                      const Text(
                        '研究者を配置した稼働施設でRPを蓄えます。技術の解放には共通RPを使い、設備の建設・製造には別途投資します。',
                        style: TextStyle(fontSize: 12, color: strategyMuted),
                      ),
                      const SizedBox(height: 10),
                      StrategyFact(
                        '研究者 / 工業員',
                        '${game.researchers}人 / ${game.industrialWorkers}人',
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
              child: const Text('人員・提携を開く'),
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
