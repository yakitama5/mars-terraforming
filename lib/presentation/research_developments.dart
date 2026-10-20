import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import 'strategy_widgets.dart';

/// Applications are purchased and operated after knowledge has been unlocked.
/// Only owned knowledge is listed, so this view cannot expose future branches.
class ResearchDevelopments extends StatefulWidget {
  const ResearchDevelopments({
    super.key,
    required this.controller,
    required this.onReserveOperation,
  });

  final GameController controller;
  final ValueChanged<String> onReserveOperation;

  @override
  State<ResearchDevelopments> createState() => _ResearchDevelopmentsState();
}

class _ResearchDevelopmentsState extends State<ResearchDevelopments> {
  ResearchField? field;
  final Map<String, String> proposedCities = {};

  @override
  Widget build(BuildContext context) {
    final game = widget.controller.state;
    final technologies = ResearchCatalog.purchasableTechnologies
        .where((technology) => game.research.contains(technology.id))
        .where((technology) => field == null || technology.field == field)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StrategyHeading(
          '研究を街と航路へ',
          '解放した設計を都市へ導入します。完成後に稼働と人員を決め、受注・輸送・研究へ配分します。',
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: const Text('解放した設計'),
              selected: field == null,
              onSelected: (_) => setState(() => field = null),
            ),
            for (final value in ResearchField.values)
              ChoiceChip(
                label: Text(value.label),
                selected: field == value,
                onSelected: (_) => setState(() => field = value),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (technologies.isEmpty)
          const StrategyCard(child: Text('研究で技術を解放すると、ここに施設や機体の導入計画が届きます。')),
        for (final technology in technologies)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _development(technology),
          ),
      ],
    );
  }

  Widget _development(ResearchTechnology technology) {
    final controller = widget.controller;
    final game = controller.state;
    final id = technology.id;
    final taskId = GameContent.developmentTaskId(id);
    final task = GameContent.tasks[taskId]!;
    final owned = game.developments.contains(id);
    final activePlan = game.plans
        .where((plan) => plan.taskId == taskId && !plan.isFinished)
        .firstOrNull;
    final enabled = game.developmentEnabled[id] ?? false;
    final cities = GameContent.cities.values
        .where((city) => city.planet == GameContent.developmentPlanet(id))
        .where((city) => game.cityUnlocked(city.id))
        .toList();
    final proposed = proposedCities[id];
    final selectedCity = cities.any((city) => city.id == proposed)
        ? proposed
        : cities.firstOrNull?.id;
    final builtCity = game.developmentCityIds[id];
    final assigned = game.developmentResearchers[id] ?? 0;
    final capacity = GameContent.developmentResearchCapacity(id);
    final operationId = GameContent.developmentOperationTaskId(id);
    final operation = GameContent.tasks[operationId];
    return StrategyCard(
      key: Key('development-$id'),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    technology.field.assetPath,
                    width: 58,
                    height: 58,
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    excludeFromSemantics: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${technology.field.label} · ${technology.unlockKind.label}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: strategyMuted,
                        ),
                      ),
                      Text(
                        technology.unlockName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '研究：${technology.name}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: strategyMint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              GameContent.developmentScopeLabel(id),
              style: const TextStyle(fontSize: 12, color: strategyCopper),
            ),
            const SizedBox(height: 6),
            Text(
              technology.unlockDescription,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              GameContent.developmentBenefitLabel(id),
              style: const TextStyle(fontSize: 13, color: strategyMint),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                if (!owned) StrategyStat('導入費', dollars(task.cost)),
                if (!owned)
                  StrategyStat(
                    '設備を使う時間',
                    gameDuration(
                      activePlan?.status == 'running'
                          ? activePlan!.remainingMs
                          : game.currentTaskDurationMs(taskId),
                    ),
                  ),
                StrategyStat(
                  '稼働時の維持費',
                  '${dollars(GameContent.developmentUpkeepPerMinute(id))}/分',
                ),
                StrategyStat(
                  '稼働に使う工業員',
                  '${GameContent.developmentCrewRequirement(id)}人',
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!owned && activePlan == null) ...[
              if (cities.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey('development-city-$id-$selectedCity'),
                  initialValue: selectedCity,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '導入先の都市'),
                  items: [
                    for (final city in cities)
                      DropdownMenuItem(
                        value: city.id,
                        child: Text(game.cityName(city.id)),
                      ),
                  ],
                  onChanged: controller.busy
                      ? null
                      : (value) => setState(() {
                          if (value != null) proposedCities[id] = value;
                        }),
                )
              else
                const Text(
                  '対応する都市が開設されると導入できます。',
                  style: TextStyle(color: strategyCopper, fontSize: 12),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  key: Key('build-development-$id'),
                  onPressed: controller.busy || selectedCity == null
                      ? null
                      : () => controller.command(
                          (engine) => engine.enqueueDevelopment(
                            id,
                            cityId: selectedCity,
                          ),
                        ),
                  icon: const Icon(Icons.construction_outlined, size: 18),
                  label: const Text('導入を予約'),
                ),
              ),
            ],
            if (activePlan != null)
              Text(
                activePlan.status == 'running'
                    ? '導入中 · ${gameDuration(activePlan.remainingMs)}'
                    : '導入を予約済み · ${activePlan.stopReason}',
                style: const TextStyle(fontSize: 12, color: strategyCopper),
              ),
            if (owned) ...[
              if (builtCity != null)
                Text(
                  '導入先：${game.cityName(builtCity)}',
                  style: const TextStyle(fontSize: 12),
                ),
              SwitchListTile.adaptive(
                key: Key('enable-development-$id'),
                contentPadding: EdgeInsets.zero,
                title: Text(enabled ? '稼働する' : '休止中'),
                subtitle: Text(
                  game.isDevelopmentOperational(id)
                      ? '人員と維持費を使い、設備が働いています。'
                      : enabled
                      ? '人員・共用設備などの稼働条件を確認してください。'
                      : '維持費と稼働人員の割当を止めています。',
                  style: const TextStyle(fontSize: 12),
                ),
                value: enabled,
                onChanged: controller.busy
                    ? null
                    : (value) => controller.command(
                        (engine) => engine.setDevelopmentEnabled(id, value),
                      ),
              ),
              if (capacity > 0)
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('実験に配分：$assigned人 / 設備枠$capacity人'),
                    IconButton(
                      key: Key('development-research-minus-$id'),
                      tooltip: '実験担当を1人減らす',
                      onPressed: controller.busy || assigned <= 0
                          ? null
                          : () => controller.command(
                              (engine) => engine.assignDevelopmentResearchers(
                                id,
                                assigned - 1,
                              ),
                            ),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    IconButton(
                      key: Key('development-research-plus-$id'),
                      tooltip: '研究所から実験担当を1人配分',
                      onPressed:
                          controller.busy ||
                              !game.isDevelopmentOperational(id) ||
                              assigned >= capacity
                          ? null
                          : () => controller.command(
                              (engine) => engine.assignDevelopmentResearchers(
                                id,
                                assigned + 1,
                              ),
                            ),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              if (operation != null) ...[
                const SizedBox(height: 8),
                Text(
                  operation.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                StrategyFact('1回の開始費用', dollars(operation.cost)),
                StrategyFact(
                  '共用設備を使う時間',
                  gameDuration(game.currentTaskDurationMs(operationId)),
                ),
                if (operation.reward > 0)
                  StrategyFact('完了時の受取', dollars(operation.reward)),
                if (operation.inputResource != null)
                  StrategyFact(
                    '出発時に確保',
                    '${GameContent.resourceNames[operation.inputResource]} ${operation.inputAmount}基',
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    key: Key('operate-development-$id'),
                    onPressed:
                        controller.busy || !game.isDevelopmentOperational(id)
                        ? null
                        : () => widget.onReserveOperation(operationId),
                    icon: const Icon(Icons.play_arrow_outlined, size: 18),
                    label: const Text('この設備で計画を予約'),
                  ),
                ),
              ],
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('方式の特徴と運営上の負担', style: TextStyle(fontSize: 12)),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    technology.tradeoff,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
