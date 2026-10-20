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
    required this.onOpenResources,
  });

  final GameState game;
  final bool devTools;
  final bool busy;
  final VoidCallback onAdvance;
  final ValueChanged<Duration> onAdvanceDuration;
  final VoidCallback onOpenResources;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1100;
      final compactActions = constraints.maxWidth < 1000;
      final status = game.agencyStatus;
      // Domain getters already separate equipment crews, paid work and the
      // researchers left in the main lab. Only combine their display totals.
      final usedResearchers =
          game.minAssignableResearchers +
          (game.facilities['lab'] == true ? game.labResearchers : 0);
      final usedIndustrialWorkers =
          game.developmentWorkers + game.reservedIndustrialWorkers;
      final industrialDepartment =
          game.industrialWorkers + game.developmentWorkers;
      return Container(
        key: const Key('command-resource-hud'),
        height: MediaQuery.textScalerOf(context).scale(14) > 18
            ? 64
            : (wide ? 54 : 52),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [strategyPanel, strategyBackground],
          ),
          border: Border(bottom: BorderSide(color: strategyLine)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.public, size: 23, color: strategyBlue),
                    if (wide) ...[
                      const SizedBox(width: 10),
                      const Text(
                        'Dear Mars',
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
                value: '${_hudNumber(game.money)}ドル',
                valueKey: const Key('money'),
                description: '資金 ${dollars(game.money)}',
                color: strategyMint,
                onTap: onOpenResources,
              ),
            ),
            Expanded(
              flex: 16,
              child: _Resource(
                label: game.netPerMinute < 0 ? '毎分収支 · 赤字' : '毎分収支',
                value: game.netPerMinute.abs() < 10000
                    ? '${signedDollars(game.netPerMinute)}/分'
                    : '${game.netPerMinute > 0 ? '+' : ''}${_hudNumber(game.netPerMinute)}ドル/分',
                description:
                    '税収 ${dollars(game.taxPerMinute)} − 維持費 ${dollars(game.upkeepPerMinute)} = ${signedDollars(game.netPerMinute)}/分',
                color: game.netPerMinute < 0 ? strategyDanger : strategyBenefit,
                onTap: onOpenResources,
              ),
            ),
            Expanded(
              flex: 13,
              child: _Resource(
                label: wide ? '研究ポイント' : '研究RP',
                value: '${_hudNumber(game.researchPoints, fraction: true)} RP',
                valueKey: const Key('hud-research-points'),
                description:
                    '研究ポイント ${game.researchPoints.toStringAsFixed(1)} RP · 毎分 ${game.researchPointsPerMinute.toStringAsFixed(1)} RP',
                color: strategyBenefit,
                onTap: onOpenResources,
              ),
            ),
            Expanded(
              flex: 12,
              child: _Resource(
                label: '研究者',
                value:
                    '${_hudNumber(usedResearchers)}/${_hudNumber(game.researchers)}',
                valueKey: const Key('hud-researchers'),
                description:
                    '研究者 使用中 $usedResearchers人 / 研究部門 ${game.researchers}人。研究所・専門設備の配属と支払済み研究で確保した人員',
                onTap: onOpenResources,
              ),
            ),
            Expanded(
              flex: 12,
              child: _Resource(
                label: '工業員',
                value:
                    '${_hudNumber(usedIndustrialWorkers)}/${_hudNumber(industrialDepartment)}',
                valueKey: const Key('hud-industrial-workers'),
                description:
                    '工業員 使用中 $usedIndustrialWorkers人 / 工業部門 $industrialDepartment人。専門設備の配属と支払済み製造・建設で確保した人員',
                onTap: onOpenResources,
              ),
            ),
            for (final resource in [
              if (wide) ('技術力', '${status.technology}'),
              if (wide) ('知名度', '${status.fame}'),
            ])
              Expanded(
                flex: 9,
                child: _Resource(
                  label: resource.$1,
                  value: resource.$2,
                  onTap: onOpenResources,
                ),
              ),
            if (compactActions)
              IconButton(
                key: const Key('open-resources'),
                tooltip: '国力と収支',
                onPressed: onOpenResources,
                icon: const Icon(Icons.bar_chart, size: 20),
              )
            else
              TextButton.icon(
                key: const Key('open-resources'),
                onPressed: onOpenResources,
                icon: const Icon(Icons.bar_chart, size: 18),
                label: const Text('国力', style: TextStyle(fontSize: 12)),
              ),
            if (devTools) ...[
              if (compactActions)
                IconButton(
                  key: const Key('advance-time'),
                  tooltip: '開発 +5分',
                  onPressed: busy ? null : onAdvance,
                  icon: const Icon(Icons.fast_forward, size: 20),
                )
              else
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
    this.color = strategyText,
    required this.onTap,
  });

  final String label, value;
  final String? description;
  final Key? valueKey;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: description ?? '$label $value',
    child: InkWell(
      onTap: onTap,
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
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  key: valueKey,
                  semanticsLabel: description ?? '$label $value',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// Keep the HUD readable while exact totals remain in tooltips and semantics.
// Truncate abbreviated values so the bank never appears to hold more RP.
String _hudNumber(num value, {bool fraction = false}) {
  for (final unit in [(1000000000000, '兆'), (100000000, '億'), (10000, '万')]) {
    if (value.abs() < unit.$1) continue;
    final scaled = (value / unit.$1 * 10).truncate() / 10;
    return '${scaled.toStringAsFixed(1)}${unit.$2}';
  }
  return fraction
      ? ((value * 10).truncate() / 10).toStringAsFixed(1)
      : formatInteger(value.toInt());
}
