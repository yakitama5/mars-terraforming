import 'package:flutter/material.dart';

import '../domain/game_state.dart';
import 'strategy_widgets.dart';

/// Persistent command resources, independent of the current map or order page.
class CommandHud extends StatelessWidget {
  const CommandHud({
    super.key,
    required this.game,
    required this.devTools,
    required this.busy,
    required this.onAdvance,
    required this.onAdvanceDuration,
  });

  final GameState game;
  final bool devTools;
  final bool busy;
  final VoidCallback onAdvance;
  final ValueChanged<Duration> onAdvanceDuration;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1100;
      final status = game.agencyStatus;
      return Container(
        key: const Key('command-resource-hud'),
        height: wide ? 54 : 48,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff20333a), Color(0xff111c25)],
          ),
          border: Border(bottom: BorderSide(color: Color(0xff697264))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 10),
              child: Row(
                children: [
                  const Icon(Icons.public, size: 23, color: strategyCopper),
                  if (wide) ...[
                    const SizedBox(width: 10),
                    const Text(
                      '火星開発計画',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              flex: 18,
              child: _Resource(
                label: '資金',
                value: dollars(game.money),
                valueKey: const Key('money'),
                description: '資金 ${dollars(game.money)}',
                color: strategyMint,
              ),
            ),
            Expanded(
              flex: 16,
              child: _Resource(
                label: '毎分収支',
                value: '${signedDollars(game.netPerMinute)}/分',
                description:
                    '税収 ${dollars(game.taxPerMinute)} − 維持費 ${dollars(game.upkeepPerMinute)} = ${signedDollars(game.netPerMinute)}/分',
                color: game.netPerMinute < 0 ? strategyCopper : strategyMint,
              ),
            ),
            for (final resource in [
              ('研究者', '${game.researchers}人'),
              ('工業員', '${game.industrialWorkers}人'),
              ('技術力', '${status.technology}'),
              ('知名度', '${status.fame}'),
              if (wide) ('友好度', '${status.friendship}'),
              if (wide) ('宇宙貢献', '${status.spaceContribution}'),
            ])
              Expanded(
                flex: 9,
                child: _Resource(label: resource.$1, value: resource.$2),
              ),
            if (devTools) ...[
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: TextButton.icon(
                  key: const Key('advance-time'),
                  onPressed: busy ? null : onAdvance,
                  icon: const Icon(Icons.fast_forward, size: 16),
                  label: const Text('開発 +5分', style: TextStyle(fontSize: 11)),
                ),
              ),
              PopupMenuButton<Duration>(
                key: const Key('development-time-menu'),
                tooltip: '開発用の時間送り',
                enabled: !busy,
                icon: const Icon(Icons.more_time, size: 20),
                onSelected: onAdvanceDuration,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: Duration(hours: 1),
                    child: Text('開発 +1時間'),
                  ),
                  PopupMenuItem(
                    value: Duration(days: 1),
                    child: Text('開発 +1日'),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _Resource extends StatelessWidget {
  const _Resource({
    required this.label,
    required this.value,
    this.description,
    this.valueKey,
    this.color = const Color(0xffe4e7e1),
  });

  final String label, value;
  final String? description;
  final Key? valueKey;
  final Color color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: description ?? '$label $value',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: strategyLine)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: strategyMuted),
          ),
          Text(
            value,
            key: valueKey,
            semanticsLabel: '$label $value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}
