import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import 'strategy_widgets.dart';
import 'city_buildings.dart';

/// Applications are purchased and operated after knowledge has been unlocked.
/// Only owned knowledge is listed, so this view cannot expose future branches.
class ResearchDevelopments extends StatefulWidget {
  const ResearchDevelopments({
    super.key,
    required this.controller,
    required this.onReserveOperation,
    this.onOpenMap,
  });

  final GameController controller;
  final ValueChanged<String> onReserveOperation;
  final void Function(String technologyId, String cityId)? onOpenMap;

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
          '解放した設計を都市へ導入します。施設の能力・維持費・役割を比べて、次の投資を選びます。',
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

  Widget _mapDevelopment(ResearchTechnology technology) {
    final game = widget.controller.state;
    final id = technology.id;
    final definition = GameContent.mapBuildingDefinitions[id]!;
    final cities = GameContent.cities.values
        .where(
          (city) =>
              definition.allowedPlanets.contains(city.planet) &&
              game.cityUnlocked(city.id),
        )
        .toList();
    final proposed = proposedCities[id];
    final selectedCity = cities.any((city) => city.id == proposed)
        ? proposed
        : cities.firstOrNull?.id;
    final existing = selectedCity == null
        ? null
        : preferredMapBuilding(
            game
                .cityBuildings(selectedCity)
                .where((building) => building.technologyId == id),
          );
    return StrategyCard(
      key: Key('development-$id'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                mapBuildingIcon(definition.catalogId),
                color: mapBuildingAccent(definition),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  definition.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '研究：${technology.name}',
            style: const TextStyle(fontSize: 11, color: strategyMint),
          ),
          const SizedBox(height: 8),
          Text(definition.description, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            definition.occupiesWholePlot ? '大型設備・1区画を専有' : '通常設備・1区画に2施設まで',
            style: const TextStyle(fontSize: 12, color: strategyCopper),
          ),
          if (existing == null) ...[
            StrategyFact('建設費', dollars(GameContent.developmentCost(id))),
            StrategyFact(
              '稼働時の維持費',
              '${dollars(GameContent.developmentUpkeepPerMinute(id))}/分',
            ),
          ] else
            Text(
              existing.workState == 'none'
                  ? '保有済み・稼働と仕事は地図で操作'
                  : existing.workLabel,
              style: const TextStyle(fontSize: 12, color: strategyMint),
            ),
          const SizedBox(height: 8),
          if (cities.isNotEmpty)
            DropdownButtonFormField<String>(
              key: ValueKey('development-city-$id-$selectedCity'),
              initialValue: selectedCity,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '建設・運営する都市'),
              items: [
                for (final city in cities)
                  DropdownMenuItem(
                    value: city.id,
                    child: Text(game.cityName(city.id)),
                  ),
              ],
              onChanged: widget.controller.busy
                  ? null
                  : (value) => setState(() {
                      if (value != null) proposedCities[id] = value;
                    }),
            )
          else
            const Text(
              '対応する都市を開設すると建設できます。',
              style: TextStyle(fontSize: 12, color: strategyCopper),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              key: Key('open-building-map-$id'),
              onPressed:
                  widget.controller.busy ||
                      selectedCity == null ||
                      widget.onOpenMap == null
                  ? null
                  : () => widget.onOpenMap!(id, selectedCity),
              icon: const Icon(Icons.place_outlined, size: 18),
              label: Text(existing == null ? '地図で建設位置を選ぶ' : '地図で建物を確認'),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '地図で区画と位置を選び、費用・適地を確認して着工します。',
            style: TextStyle(fontSize: 11, color: strategyMuted),
          ),
        ],
      ),
    );
  }

  Widget _development(ResearchTechnology technology) {
    final controller = widget.controller;
    final game = controller.state;
    final id = technology.id;
    if (GameContent.mapBuildingDefinitions.containsKey(id)) {
      return _mapDevelopment(technology);
    }
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
              ],
            ),
            const SizedBox(height: 10),
            if (!owned &&
                activePlan == null &&
                game.money < game.taskCost(task))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  game.taskCost(task) > game.moneyCapacity
                      ? '必要な導入費が資金の保有上限を超えています。人口を増やして資金の保有上限を広げましょう。'
                      : '必要な導入費を蓄えてから開始できます。',
                  key: Key('development-funding-reason-$id'),
                  style: const TextStyle(fontSize: 12, color: strategyCopper),
                ),
              ),
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
                  label: const Text('導入を開始'),
                ),
              ),
            ],
            if (activePlan != null)
              Text(
                activePlan.status == 'running'
                    ? '導入中 · ${gameDuration(activePlan.remainingMs)}'
                    : '要着手 · ${activePlan.stopReason}',
                style: const TextStyle(fontSize: 12, color: strategyCopper),
              ),
            if (activePlan?.requiresManualStart == true)
              FilledButton.tonalIcon(
                key: Key('start-development-${activePlan!.id}'),
                onPressed: controller.busy
                    ? null
                    : () => controller.command(
                        (engine) => engine.startPlan(activePlan.id),
                      ),
                icon: const Icon(Icons.play_arrow_outlined, size: 18),
                label: const Text('導入を開始'),
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
                      ? '維持費を使い、設備が働いています。'
                      : enabled
                      ? '共用設備・電力などの稼働条件を確認してください。'
                      : '設備の稼働と維持費を止めています。',
                  style: const TextStyle(fontSize: 12),
                ),
                value: enabled,
                onChanged: controller.busy
                    ? null
                    : (value) => controller.command(
                        (engine) => engine.setDevelopmentEnabled(id, value),
                      ),
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
                StrategyFact('1回の開始費用', dollars(game.taskCost(operation))),
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
