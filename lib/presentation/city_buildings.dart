import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/game_state.dart';
import 'research_theme.dart';
import 'strategy_widgets.dart';

Color mapBuildingAccent(MapBuildingDefinition definition) =>
    definition.isBaseLab
    ? strategyBlue
    : GameContent.researchTechnologies[definition.id]?.field.color ??
          strategyBlue;

IconData mapBuildingIcon(String catalogId) => switch (catalogId) {
  'B01' => Icons.grass,
  'B13' => Icons.fact_check_outlined,
  'R01' => Icons.biotech,
  'R05' => Icons.water_drop_outlined,
  'R07' => Icons.water,
  'R15' => Icons.precision_manufacturing_outlined,
  'E09' => Icons.battery_charging_full,
  'E10' => Icons.science_outlined,
  'E13' => Icons.electrical_services,
  'M08' => Icons.build_circle_outlined,
  'M25' => Icons.rocket_launch_outlined,
  'M13' => Icons.nightlight_outlined,
  _ => Icons.science_outlined,
};

CityBuildingSnapshot? preferredMapBuilding(
  Iterable<CityBuildingSnapshot> buildings,
) =>
    buildings.where((building) => building.underConstruction).firstOrNull ??
    buildings.firstOrNull;

class MapBuildingChoice extends StatelessWidget {
  const MapBuildingChoice({
    super.key,
    required this.definition,
    required this.controller,
    required this.cityId,
    required this.onSelected,
  });
  final MapBuildingDefinition definition;
  final GameController controller;
  final String cityId;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final game = controller.state;
    final existing = preferredMapBuilding(
      game
          .cityBuildings(cityId)
          .where((building) => building.technologyId == definition.id),
    );
    final owned =
        definition.isBaseLab ||
        (existing != null && game.developments.contains(existing.id));
    final preview = game.buildingPreview(
      definition.id,
      cityId: cityId,
      plotIndex: 12,
      slotIndex: 0,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: OutlinedButton(
        key: Key('building-option-${definition.id}'),
        onPressed: onSelected,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          foregroundColor: strategyText,
          side: BorderSide(
            color: mapBuildingAccent(definition).withValues(alpha: .45),
          ),
        ),
        child: Row(
          children: [
            Icon(
              mapBuildingIcon(definition.catalogId),
              color: mapBuildingAccent(definition),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    definition.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    existing != null
                        ? existing.workState == 'none'
                              ? '保有済み・地図で確認'
                              : existing.workLabel.isEmpty
                              ? '工事を予約済み'
                              : existing.workLabel
                        : owned
                        ? '保有済み・配置先を選ぶ'
                        : '${dollars(preview.cost)}・${gameDuration(preview.durationMs)}',
                    style: const TextStyle(color: strategyMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

class CityBuildingSupply extends StatelessWidget {
  const CityBuildingSupply({
    super.key,
    required this.game,
    required this.cityId,
  });
  final GameState game;
  final String cityId;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 4,
    children: [
      Text(
        '電力 ${game.cityPowerSupply(cityId)} / 需要 ${game.cityPowerDemand(cityId)}',
        style: const TextStyle(fontSize: 11, color: strategyMint),
      ),
      Text(
        '蓄電 ${game.cityBatteryCharge(cityId)}',
        style: const TextStyle(fontSize: 11, color: strategyMuted),
      ),
      for (final resource in GameContent.buildingResourceNames.entries)
        if (game.cityStock(cityId, resource.key) > 0)
          Text(
            '${resource.value} ${game.cityStock(cityId, resource.key)}',
            style: const TextStyle(fontSize: 11, color: strategyMuted),
          ),
    ],
  );
}

class MapBuildingInspector extends StatelessWidget {
  const MapBuildingInspector({
    super.key,
    required this.controller,
    required this.definition,
    required this.cityId,
    required this.building,
    required this.hasPlotSelection,
    required this.plotIndex,
    required this.slotIndex,
    required this.availableSlots,
    required this.moving,
    required this.onSlotSelected,
    required this.onConfirm,
    required this.onCancel,
    required this.onRelocate,
    required this.workTargetPlot,
    required this.onWorkTargetSelected,
  });
  final GameController controller;
  final MapBuildingDefinition definition;
  final String cityId;
  final CityBuildingSnapshot? building;
  final bool hasPlotSelection, moving;
  final int plotIndex, slotIndex;
  final Set<int> availableSlots;
  final ValueChanged<int> onSlotSelected;
  final VoidCallback onConfirm, onCancel, onRelocate;
  final int workTargetPlot;
  final ValueChanged<int> onWorkTargetSelected;

  @override
  Widget build(BuildContext context) {
    final game = controller.state;
    final id = definition.id;
    final owned =
        definition.isBaseLab ||
        (building != null && game.developments.contains(building!.id));
    final reserving = building != null && building!.workState != 'none';
    final placement = moving || (!owned && !reserving);
    final preview = game.buildingPreview(
      moving ? building?.id ?? id : id,
      cityId: cityId,
      plotIndex: plotIndex,
      slotIndex: slotIndex,
      relocation: moving,
    );
    final accent = mapBuildingAccent(definition);
    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              key: const Key('building-inspector'),
              padding: const EdgeInsets.all(12),
              children: [
                Row(
                  children: [
                    Icon(mapBuildingIcon(definition.catalogId), color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        definition.name,
                        key: Key('building-title-$id'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  definition.description,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                if (placement) ...[
                  Text(
                    moving ? '保有している設備の配置を変更' : '地図へ建設',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasPlotSelection
                        ? '区画 ${plotIndex + 1} の建設位置を選択'
                        : '地図上の区画を選んでください。',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (hasPlotSelection)
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final slot in [0, 1])
                          if (!definition.occupiesWholePlot || slot == 0)
                            ChoiceChip(
                              key: Key('building-slot-$slot'),
                              label: Text(
                                definition.occupiesWholePlot
                                    ? '区画を専有'
                                    : '位置 ${slot + 1}',
                              ),
                              selected: slotIndex == slot,
                              onSelected: availableSlots.contains(slot)
                                  ? (_) => onSlotSelected(slot)
                                  : null,
                            ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  StrategyFact(moving ? '移設費' : '建設費', dollars(preview.cost)),
                  if (preview.resourceId != null) ...[
                    Text(
                      '${GameContent.resourceNames[preview.resourceId]}：必要 ${preview.requiredKits}基・現在 ${preview.availableKits}基',
                      key: const Key('building-kit-requirement'),
                      style: const TextStyle(fontSize: 12, color: strategyMint),
                    ),
                    if (preview.availableKits < preview.requiredKits)
                      const Text(
                        '着工時に現地キットを使います。予約して通常便の到着を待てます。',
                        key: Key('building-kit-wait'),
                        style: TextStyle(fontSize: 11, color: strategyCopper),
                      ),
                  ],
                  StrategyFact('工期', gameDuration(preview.durationMs)),
                  StrategyFact(
                    '稼働時の維持費',
                    '${dollars(preview.upkeepPerMinute)}/分',
                  ),
                  if (hasPlotSelection && preview.blockedReason != null)
                    Text(
                      preview.blockedReason!,
                      key: const Key('building-blocked-reason'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: strategyCopper,
                      ),
                    ),
                  if (hasPlotSelection &&
                      preview.isValid &&
                      game.money < preview.cost)
                    const Text(
                      '資金がそろうまで予約は待機します。受注と建設の順番も確認しましょう。',
                      style: TextStyle(fontSize: 12, color: strategyCopper),
                    ),
                ] else ...[
                  Text(
                    building?.legacySite == true ||
                            (building?.plotIndex ?? -1) < 0
                        ? definition.isBaseLab
                              ? '都市本部・既存の研究所'
                              : '既存敷地・支払済みの設備'
                        : '区画 ${(building?.plotIndex ?? 0) + 1}・位置 ${(building?.slotIndex ?? 0) + 1}',
                    style: const TextStyle(fontSize: 12, color: strategyMuted),
                  ),
                  if (reserving)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        building!.workLabel.isEmpty
                            ? '工事中'
                            : building!.workLabel,
                        key: const Key('building-work-status'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: strategyCopper,
                        ),
                      ),
                    ),
                  if (owned) ...[
                    const SizedBox(height: 8),
                    if (building?.underConstruction != true)
                      _operations(game)
                    else
                      const Text(
                        '移設の完了後に配属と仕事を操作できます。',
                        style: TextStyle(fontSize: 12, color: strategyMuted),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: Key('relocate-building-$id'),
                      onPressed: controller.busy || reserving
                          ? null
                          : onRelocate,
                      icon: const Icon(Icons.open_with, size: 17),
                      label: Text(
                        building?.legacySite == true ? '地図へ配置する' : '配置を変更する',
                      ),
                    ),
                  ],
                ],
                const Divider(),
                const Text(
                  'この都市の供給と在庫',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                CityBuildingSupply(game: game, cityId: cityId),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: strategyLine)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (placement)
                  FilledButton.icon(
                    key: const Key('confirm-map-building'),
                    onPressed:
                        controller.busy ||
                            !hasPlotSelection ||
                            !preview.isValid ||
                            !availableSlots.contains(slotIndex)
                        ? null
                        : onConfirm,
                    icon: const Icon(Icons.construction, size: 17),
                    label: Text(moving ? '移設を予約' : '建設を予約'),
                  ),
                TextButton(
                  key: const Key('cancel-map-building'),
                  onPressed: onCancel,
                  child: Text(placement ? '施設一覧に戻る' : '別の施設を選ぶ'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _operations(GameState game) {
    final technologyId = definition.id;
    final id = building?.id ?? technologyId;
    final base = definition.isBaseLab;
    final enabled = base
        ? game.facilities['lab'] == true
        : game.developmentEnabled[id] == true;
    final assigned = base
        ? game.researchers
        : game.developmentResearchers[id] ?? 0;
    final capacity = base
        ? game.specialistCount
        : game.developmentResearchCapacityFor(id);
    final work = game.buildingWorkTasks(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          key: Key('enable-map-building-$id'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(enabled ? '稼働中' : '休止中'),
          value: enabled,
          subtitle: Text(
            base
                ? '本部の研究者が共通RPを生産します。'
                : building?.operational == true
                ? '担当者と維持費を使っています。'
                : '稼働条件と人員を確認してください。',
            style: const TextStyle(fontSize: 11),
          ),
          onChanged: controller.busy
              ? null
              : (value) => controller.command(
                  (engine) => base
                      ? engine.setFacilityEnabled('lab', value)
                      : engine.setDevelopmentEnabled(id, value),
                ),
        ),
        if (capacity > 0) ...[
          Text(
            base
                ? '研究部門 $assigned人（本部 ${game.labResearchers}人）'
                : '実験へ配分 $assigned / $capacity人',
            style: const TextStyle(fontSize: 12),
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                key: Key('map-building-research-minus-$id'),
                tooltip: '研究者を1人減らす',
                onPressed: controller.busy || assigned <= 0
                    ? null
                    : () => controller.command(
                        (engine) => base
                            ? engine.assignResearchers(assigned - 1)
                            : engine.assignDevelopmentResearchers(
                                id,
                                assigned - 1,
                              ),
                      ),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              IconButton(
                key: Key('map-building-research-plus-$id'),
                tooltip: '研究者を1人配分',
                onPressed: controller.busy || !enabled || assigned >= capacity
                    ? null
                    : () => controller.command(
                        (engine) => base
                            ? engine.assignResearchers(assigned + 1)
                            : engine.assignDevelopmentResearchers(
                                id,
                                assigned + 1,
                              ),
                      ),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          Text(
            '全施設の共通RP ${game.researchPointsPerMinute.toStringAsFixed(1)} RP/分',
            key: const Key('map-building-common-rp'),
            style: const TextStyle(fontSize: 11, color: strategyMint),
          ),
        ],
        if (work.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            'この施設の仕事',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          for (final task in work) _work(game, task),
        ],
      ],
    );
  }

  Widget _work(GameState game, TaskDefinition task) {
    final id = building?.id ?? definition.id;
    final surveying = task.id == 'building_survey';
    final reason = game.buildingWorkLockReason(
      id,
      task.id,
      targetPlotIndex: surveying ? workTargetPlot : null,
    );
    final active = game.plans
        .where(
          (plan) =>
              plan.taskId == task.id &&
              plan.buildingInstanceId == id &&
              !plan.isFinished,
        )
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            task.name,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(task.description, style: const TextStyle(fontSize: 11)),
          if (surveying) ...[
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              key: ValueKey('building-survey-target-$id-$workTargetPlot'),
              initialValue: workTargetPlot,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '調査する区画'),
              items: [
                for (
                  var plot = 0;
                  plot < GameContent.cities[cityId]!.plotCount;
                  plot++
                )
                  DropdownMenuItem(
                    value: plot,
                    child: Text(
                      '区画 ${plot + 1}・${GameContent.terrainNames[GameContent.cities[cityId]!.terrainAt(plot)]}${game.isSiteSurveyed(cityId, plot) ? '（調査済み）' : ''}',
                    ),
                  ),
              ],
              onChanged: controller.busy || active != null
                  ? null
                  : (value) {
                      if (value != null) onWorkTargetSelected(value);
                    },
            ),
            const SizedBox(height: 6),
          ],
          Text(
            _workSummary(game, id, task),
            style: const TextStyle(fontSize: 11, color: strategyMint),
          ),
          Text(
            '開始 ${dollars(game.taskCost(task))}・${gameDuration(game.currentTaskDurationMs(task.id))}${task.reward > 0 ? '・完了 ${dollars(task.reward)}' : ''}',
            style: const TextStyle(fontSize: 11, color: strategyMuted),
          ),
          if (active != null)
            Text(
              active.stopReason.isNotEmpty
                  ? active.stopReason
                  : active.status == 'running'
                  ? '進行中・残り ${gameDuration(active.remainingMs)}'
                  : '予約済み',
              style: const TextStyle(fontSize: 11, color: strategyCopper),
            )
          else if (reason != null)
            Text(
              reason,
              key: Key('building-work-reason-${task.id}'),
              style: const TextStyle(fontSize: 11, color: strategyCopper),
            ),
          if (surveying && game.isSiteSurveyed(cityId, workTargetPlot))
            Text(
              game.siteSurveyReport(cityId, workTargetPlot),
              key: const Key('building-survey-record'),
              style: const TextStyle(fontSize: 11, color: strategyMint),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: Key('reserve-building-work-${task.id}'),
                  onPressed: controller.busy || active != null || reason != null
                      ? null
                      : () => controller.command(
                          (engine) => engine.enqueueBuildingWork(
                            id,
                            task.id,
                            targetPlotIndex: surveying ? workTargetPlot : null,
                          ),
                        ),
                  icon: const Icon(Icons.play_arrow_outlined, size: 16),
                  label: const Text('1回予約'),
                ),
              ),
              if (['', 'charge', 'mineIce'].contains(task.workAction))
                PopupMenuButton<String>(
                  key: Key('repeat-building-work-${task.id}'),
                  tooltip: '回数を指定して予約',
                  enabled: !controller.busy && active == null && reason == null,
                  onSelected: (value) => controller.command(
                    (engine) => engine.enqueueBuildingWork(
                      id,
                      task.id,
                      repeats: value == 'unlimited' ? null : int.parse(value),
                    ),
                  ),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: '5',
                      key: Key('reserve-building-work-${task.id}-5'),
                      child: const Text('5回予約'),
                    ),
                    PopupMenuItem(
                      value: 'unlimited',
                      key: Key('reserve-building-work-${task.id}-unlimited'),
                      child: const Text('条件が整う間は反復'),
                    ),
                  ],
                  icon: const Icon(Icons.repeat, size: 18),
                ),
            ],
          ),
          if (['', 'charge', 'mineIce'].contains(task.workAction))
            const Text(
              '反復は入力・資金・保管枠が不足すると待機します。',
              style: TextStyle(fontSize: 10, color: strategyMuted),
            ),
        ],
      ),
    );
  }

  String _workSummary(GameState game, String id, TaskDefinition task) {
    final inputs = game.buildingLocalInputs(id, task);
    final outputs = game.buildingLocalOutputs(id, task);
    String resources(Map<String, int> values) => values.entries
        .map(
          (entry) =>
              '${GameContent.buildingResourceNames[entry.key]} ${entry.value}',
        )
        .join(' / ');
    return [
      if (inputs.isNotEmpty) '入力：${resources(inputs)}',
      if (task.inputResource != null)
        '搬出：${GameContent.resourceNames[task.inputResource]} ${task.inputAmount}',
      if (outputs.isNotEmpty) '出力：${resources(outputs)}',
      if (task.outputResource != null)
        '搬入：${GameContent.resourceNames[task.outputResource]} ${task.outputAmount}',
      if (task.powerDemand > 0) '工程電力 ${task.powerDemand}',
    ].join('。');
  }
}
