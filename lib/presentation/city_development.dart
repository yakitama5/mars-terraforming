import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/game_state.dart';
import '../rendering/city_scene.dart';
import 'city_scene_data.dart';
import 'city_facility_palette.dart';
import 'investment_comparison.dart';
import 'strategy_widgets.dart';

class CityDevelopment extends StatefulWidget {
  const CityDevelopment({
    super.key,
    required this.controller,
    required this.cityId,
    required this.onCityChanged,
    required this.onOpenResearch,
    required this.onSaveInvestment,
    this.savedInvestment,
    this.renderScene = true,
    this.onOpenGlobe,
    this.onOpenOperations,
  });
  final GameController controller;
  final bool renderScene;
  final VoidCallback? onOpenGlobe, onOpenOperations;
  final String cityId;
  final ValueChanged<String> onCityChanged;
  final ValueChanged<String> onOpenResearch;
  final InvestmentCandidate? savedInvestment;
  final ValueChanged<InvestmentCandidate?> onSaveInvestment;

  @override
  State<CityDevelopment> createState() => _CityDevelopmentState();
}

class _CityDevelopmentState extends State<CityDevelopment> {
  int selectedPlot = 12;
  bool showInspector = true;
  bool choosingFacility = true;
  bool placementMode = false;
  bool hasPlotSelection = false;
  String? selectedDistrict;
  GameState get game => widget.controller.state;
  CityDefinition get city => GameContent.cities[widget.cityId]!;
  List<DistrictDefinition> get available => GameContent.districts.values
      .where((district) => district.planet == city.planet)
      .toList();

  @override
  void didUpdateWidget(covariant CityDevelopment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cityId != widget.cityId) {
      final previousDistrict =
          selectedDistrict ??
          game.districtAt(oldWidget.cityId, selectedPlot)?.districtId ??
          widget.savedInvestment?.districtId;
      selectedPlot = 12;
      hasPlotSelection = false;
      selectedDistrict = available.any((item) => item.id == previousDistrict)
          ? previousDistrict
          : null;
      placementMode = selectedDistrict != null;
      choosingFacility = selectedDistrict == null;
      showInspector = true;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _overview()),
        if (showInspector) ...[
          const VerticalDivider(width: 1, color: strategyLine),
          SizedBox(
            width: constraints.maxWidth > 1100 ? 308 : 280,
            child: ColoredBox(
              color: const Color(0xff102129),
              child: choosingFacility
                  ? CityFacilityPalette(
                      districts: available,
                      selectedId: selectedDistrict,
                      onSelected: _chooseFacility,
                      lockReason: _facilityLockReason,
                    )
                  : _inspector(),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _overview() {
    final development = game.cityDevelopment(city.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: const BoxDecoration(
            color: Color(0xff10212b),
            border: Border(bottom: BorderSide(color: strategyLine)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (widget.onOpenGlobe != null)
                IconButton(
                  key: const Key('city-to-globe'),
                  tooltip: '惑星全体へ戻る',
                  onPressed: widget.onOpenGlobe,
                  icon: const Icon(Icons.public, size: 19),
                ),
              Text(
                city.planet == 'earth' ? '地球 / ' : '火星 / ',
                style: const TextStyle(color: strategyMuted, fontSize: 12),
              ),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const Key('city-selector'),
                    value: city.id,
                    isExpanded: true,
                    items: [
                      for (final item in GameContent.cities.values)
                        DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            item.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) widget.onCityChanged(value);
                    },
                  ),
                ),
              ),
              IconButton(
                key: const Key('city-inspector-toggle'),
                tooltip: showInspector ? '地図を広く表示' : '区画の詳細を表示',
                onPressed: () => setState(() => showInspector = !showInspector),
                icon: Icon(
                  showInspector ? Icons.open_in_full : Icons.close_fullscreen,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: CityScene(
            key: ValueKey('city-scene-${city.id}'),
            cityId: city.id,
            cityName: city.name,
            earth: city.planet == 'earth',
            columns: city.width,
            rows: city.height,
            plots: scenePlotsForCity(game, city),
            selectedPlot: hasPlotSelection ? selectedPlot : -1,
            adjacentPlots: hasPlotSelection
                ? city.adjacentPlots(selectedPlot).toSet()
                : const {},
            constructionMode: placementMode,
            buildablePlots: _buildablePlots,
            renderScene: widget.renderScene,
            onPlotSelected: _selectPlot,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: const BoxDecoration(
            color: Color(0xff10212b),
            border: Border(top: BorderSide(color: strategyLine)),
          ),
          child: Text(
            '${development.stageName} · 完成 ${development.completedPlots}/${city.plotCount}区画 · 総Lv.${development.totalLevels} · 未予約空地 ${development.availablePlots}',
            key: const Key('city-development-summary'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: strategyMint, fontSize: 11),
          ),
        ),
      ],
    );
  }

  String? _facilityLockReason(DistrictDefinition definition) {
    if (!game.cityUnlocked(city.id)) return game.cityLockReason(city.id);
    final research = definition.requiredResearch;
    if (research != null && !game.research.contains(research)) {
      return '前提研究：${GameContent.tasks[research]!.name}';
    }
    if (definition.id == 'mars_habitat' && game.habitatChoice == null) {
      return '居住方式を選択してください';
    }
    return null;
  }

  bool get _needsFirstDelivery =>
      city.planet == 'mars' && !game.achievements.contains('first_landing');

  String? _requiredResearch(
    DistrictDefinition definition,
    DistrictState? existing,
  ) {
    // A first landing unlocks Mars before city-specific research is checked.
    if (_needsFirstDelivery) return null;
    final candidates = [
      ?city.requiredResearch,
      ?definition.requiredResearch,
      if (existing != null && existing.level < definition.maxLevel)
        definition.researchForUpgrade(existing.level + 1),
    ];
    return candidates.where((id) => !game.research.contains(id)).firstOrNull;
  }

  Set<int> get _buildablePlots => !placementMode || selectedDistrict == null
      ? const {}
      : {
          for (var index = 0; index < city.plotCount; index++)
            if (game.districtAt(city.id, index) == null &&
                game.districtPlanAt(city.id, index) == null &&
                game.districtPreview(city.id, index, selectedDistrict!).isValid)
              index,
        };

  void _chooseFacility(String id) => setState(() {
    selectedDistrict = id;
    choosingFacility = false;
    placementMode = true;
    showInspector = true;
    if (game.districtAt(city.id, selectedPlot) != null ||
        game.districtPlanAt(city.id, selectedPlot) != null) {
      hasPlotSelection = false;
    }
  });

  void _selectPlot(int index) => setState(() {
    selectedPlot = index;
    hasPlotSelection = true;
    showInspector = true;
    final existing = game.districtAt(city.id, index);
    final reserved = game.districtPlanAt(city.id, index);
    if (existing != null || reserved != null) {
      placementMode = false;
      choosingFacility = false;
    } else if (selectedDistrict != null) {
      placementMode = true;
      choosingFacility = false;
    } else {
      choosingFacility = true;
    }
  });

  void _cancelPlacement() => setState(() {
    placementMode = false;
    hasPlotSelection = false;
    choosingFacility = true;
  });

  Widget _inspector() {
    final existing = hasPlotSelection
        ? game.districtAt(city.id, selectedPlot)
        : null;
    final plan = hasPlotSelection
        ? game.districtPlanAt(city.id, selectedPlot)
        : null;
    final id =
        existing?.districtId ??
        plan?.definition.districtId ??
        selectedDistrict ??
        available.first.id;
    final definition = GameContent.districts[id]!;
    final maxLevel = existing != null && existing.level >= definition.maxLevel;
    final requiredResearch = _requiredResearch(definition, existing);
    final preview = game.districtPreview(
      city.id,
      selectedPlot,
      id,
      upgrade: existing != null,
    );
    final terrain = GameContent.terrainNames[city.terrainAt(selectedPlot)];
    final reason = hasPlotSelection
        ? preview.blockedReason
        : _facilityLockReason(definition);
    final effects = [
      if (preview.researchBonusDelta != 0)
        '研究 ${signedNumber(preview.researchBonusDelta)}%',
      if (preview.factoryBonusDelta != 0)
        '製造 ${signedNumber(preview.factoryBonusDelta)}%',
      if (preview.launchBonusDelta != 0)
        '輸送 ${signedNumber(preview.launchBonusDelta)}%',
      if (preview.marsBonusDelta != 0)
        '火星建設 ${signedNumber(preview.marsBonusDelta)}%',
    ];
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const Key('district-inspector'),
            padding: const EdgeInsets.all(12),
            children: [
              Row(
                children: [
                  Icon(districtIcon(id), color: strategyCopper, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${definition.name}${existing == null ? '' : ' Lv.${existing.level}'}',
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
                hasPlotSelection
                    ? '区画 ${selectedPlot + 1}  ·  $terrain'
                    : '2  地図で建設する区画を選択',
                key: const Key('placement-step'),
                style: const TextStyle(
                  color: strategyMint,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              if (plan != null)
                _workStatus(plan)
              else if (maxLevel)
                const SizedBox.shrink()
              else if (hasPlotSelection) ...[
                Row(
                  children: [
                    Expanded(
                      child: StrategyStat('投資費用', dollars(preview.cost)),
                    ),
                    Expanded(
                      child: StrategyStat(
                        '設備占有',
                        gameDuration(preview.durationMs),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '完成後の純収支 ${signedDollars(preview.netDeltaPerMinute)}/分',
                  style: const TextStyle(color: strategyMint, fontSize: 12),
                ),
                if (effects.isNotEmpty)
                  Text(
                    effects.join(' · '),
                    style: const TextStyle(fontSize: 12, color: strategyMint),
                  ),
                const SizedBox(height: 8),
                const Text(
                  '立地・隣接ボーナス',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                for (final bonus in preview.bonuses)
                  Text(
                    bonus,
                    style: const TextStyle(fontSize: 11, color: strategyMuted),
                  ),
                if (preview.isValid && game.money < preview.cost)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '資金不足 · 予約後は資金が貯まるまで着工待ち。後続の受注も待つため、設備の順番を確認してください。',
                      key: Key('district-funding-warning'),
                      style: TextStyle(fontSize: 11, color: strategyCopper),
                    ),
                  ),
              ] else ...[
                Text(districtPurpose(id), style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 6),
                Text(
                  '基準 ${dollars(definition.cost)} · ${gameDuration(definition.durationSeconds * 1000)}',
                  style: const TextStyle(fontSize: 12, color: strategyMuted),
                ),
                const SizedBox(height: 8),
                Text(
                  reason ??
                      '明るい六角が配置できる空地です（${_buildablePlots.length}区画）。場所を選ぶと費用と隣接効果が分かります。',
                  style: TextStyle(
                    fontSize: 12,
                    color: reason == null ? strategyMint : strategyCopper,
                  ),
                ),
              ],
              if (requiredResearch != null)
                TextButton.icon(
                  key: const Key('district-required-research'),
                  onPressed: () => widget.onOpenResearch(requiredResearch),
                  icon: const Icon(Icons.account_tree_outlined, size: 16),
                  label: const Text('必要な研究を確認'),
                ),
              if (_needsFirstDelivery && widget.onOpenOperations != null)
                TextButton.icon(
                  key: const Key('district-required-delivery'),
                  onPressed: widget.onOpenOperations,
                  icon: const Icon(Icons.rocket_launch_outlined, size: 16),
                  label: const Text('輸送の準備を確認'),
                ),
              if (id == 'mars_habitat' && game.habitatChoice == null)
                Wrap(
                  children: [
                    for (final choice in [
                      ('dome', 'ドーム居住'),
                      ('underground', '地下居住'),
                    ])
                      TextButton(
                        key: Key('choose-${choice.$1}'),
                        onPressed:
                            !game.achievements.contains('first_landing') ||
                                widget.controller.busy
                            ? null
                            : () => widget.controller.command(
                                (engine) => engine.chooseHabitat(choice.$1),
                              ),
                        child: Text(choice.$2),
                      ),
                  ],
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 8),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: strategyLine)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasPlotSelection && plan == null && reason != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    reason,
                    key: const Key('district-blocked-reason'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: strategyCopper),
                  ),
                ),
              if (plan != null && widget.onOpenOperations != null)
                OutlinedButton.icon(
                  key: const Key('district-open-operations'),
                  onPressed: widget.onOpenOperations,
                  icon: const Icon(Icons.view_timeline_outlined, size: 17),
                  label: const Text('設備・進行で確認'),
                )
              else
                FilledButton.icon(
                  key: const Key('confirm-district'),
                  onPressed:
                      !hasPlotSelection ||
                          !preview.isValid ||
                          widget.controller.busy
                      ? null
                      : () async {
                          final targetCity = city.id;
                          final targetPlot = selectedPlot;
                          final controller = widget.controller;
                          await controller.command(
                            (engine) => existing == null
                                ? engine.enqueueDistrict(
                                    targetCity,
                                    targetPlot,
                                    id,
                                  )
                                : engine.upgradeDistrict(
                                    targetCity,
                                    targetPlot,
                                  ),
                          );
                          if (!mounted) return;
                          // A save conflict stops the controller and clears its
                          // engine before the parent removes this screen.
                          final state = controller.engine?.state;
                          if (city.id == targetCity &&
                              selectedPlot == targetPlot &&
                              state?.districtPlanAt(targetCity, targetPlot) !=
                                  null) {
                            setState(() => placementMode = false);
                          }
                        },
                  icon: const Icon(Icons.construction, size: 17),
                  label: Text(existing == null ? 'この区画に建設を予約' : 'この地区を強化する'),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: const Key('city-change-facility'),
                      onPressed: () => setState(() {
                        choosingFacility = true;
                        placementMode = false;
                      }),
                      child: const Text(
                        '施設を変更',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      key: const Key('city-cancel-placement'),
                      onPressed: _cancelPlacement,
                      child: Text(
                        placementMode ? '配置をやめる' : '施設一覧へ',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  if (hasPlotSelection)
                    IconButton(
                      key: const Key('city-open-details'),
                      tooltip: '費用・効果と投資比較',
                      onPressed: _openDetails,
                      icon: const ExcludeSemantics(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.subject, size: 17),
                            Text('詳細', style: TextStyle(fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _workStatus(PlannedTask plan) => Column(
    key: const Key('district-work-status'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        plan.stopReason.isNotEmpty
            ? '待機・停止中 · ${plan.stopReason}'
            : plan.status == 'running'
            ? '建設中'
            : '建設予約',
        style: const TextStyle(color: strategyCopper),
      ),
      if (plan.status == 'running') ...[
        const SizedBox(height: 6),
        LinearProgressIndicator(value: plan.progress.clamp(0, 1)),
        const SizedBox(height: 6),
        Text('残り ${gameDuration(plan.remainingMs)}'),
        const Text(
          '着工費は確保済み',
          style: TextStyle(fontSize: 11, color: strategyMuted),
        ),
      ],
    ],
  );

  Future<void> _openDetails() => showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '費用・効果と投資比較',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('close-district-details'),
                    tooltip: '地図へ戻る',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: strategyLine),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (_, _) => widget.controller.engine == null
                    ? Padding(
                        key: const Key('district-detail-stopped'),
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          widget.controller.error ??
                              '進行を停止しています。地図へ戻って状態を確認してください。',
                        ),
                      )
                    : _detail(),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _detail() {
    final existing = game.districtAt(city.id, selectedPlot);
    final districts = available;
    final reserved = game.districtPlanAt(city.id, selectedPlot);
    final selected =
        existing?.districtId ??
        reserved?.definition.districtId ??
        (districts.any((item) => item.id == selectedDistrict)
            ? selectedDistrict!
            : districts.first.id);
    final definition = GameContent.districts[selected]!;
    final maxLevel = existing != null && existing.level >= definition.maxLevel;
    final requiredResearch = _requiredResearch(definition, existing);
    final investmentResearch = existing != null && !maxLevel
        ? definition.researchForUpgrade(existing.level + 1)
        : definition.requiredResearch;
    final preview = game.districtPreview(
      city.id,
      selectedPlot,
      selected,
      upgrade: existing != null,
    );
    final candidate = InvestmentCandidate(
      cityId: city.id,
      plotIndex: selectedPlot,
      districtId: selected,
      targetLevel: preview.targetLevel,
    );
    final plans = game.plans.where(
      (plan) =>
          plan.cityId == city.id &&
          plan.plotIndex == selectedPlot &&
          !plan.isFinished,
    );
    final plan = plans.firstOrNull;
    final terrain =
        GameContent.terrainNames[city.terrainAt(selectedPlot)] ??
        city.terrainAt(selectedPlot);
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const Key('district-detail'),
            padding: const EdgeInsets.all(14),
            children: [
              StrategyHeading(
                '区画 ${selectedPlot + 1}  ·  $terrain',
                reserved != null
                    ? 'この区画の予約と工事状況を確認します。'
                    : existing == null
                    ? '地形と隣接効果を確認し、この場所に建設します。'
                    : '完成した地区を強化し、都市の能力を高めます。',
              ),
              if (plan != null) ...[
                StrategyCard(
                  key: const Key('district-work-status-detail'),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        plan.stopReason.isNotEmpty
                            ? '待機・停止中'
                            : plan.status == 'running'
                            ? '建設中'
                            : '建設予約',
                        style: const TextStyle(
                          color: strategyCopper,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (plan.stopReason.isNotEmpty) Text(plan.stopReason),
                      if (plan.status == 'running') ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: plan.progress.clamp(0, 1),
                        ),
                        const SizedBox(height: 6),
                        Text('残り ${gameDuration(plan.remainingMs)}'),
                        const Text(
                          '着工費は確保済みです。工期は着工時の条件で進みます。',
                          style: TextStyle(fontSize: 11, color: strategyMuted),
                        ),
                      ] else
                        const Text(
                          '設備の順番と必要条件が揃うと、費用を確保して着工します。',
                          style: TextStyle(fontSize: 11, color: strategyMuted),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (!game.cityUnlocked(city.id)) ...[
                StrategyCard(
                  child: Text(
                    game.cityLockReason(city.id) ?? '都市の開発条件を満たしていません',
                    style: const TextStyle(color: strategyCopper),
                  ),
                ),
                if (_needsFirstDelivery && widget.onOpenOperations != null)
                  TextButton.icon(
                    key: const Key('district-required-delivery-detail'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onOpenOperations!();
                    },
                    icon: const Icon(Icons.rocket_launch_outlined),
                    label: const Text('輸送の準備を確認'),
                  ),
                const SizedBox(height: 12),
              ],
              Text(
                '${definition.name}${existing == null
                    ? ''
                    : existing.level >= definition.maxLevel
                    ? ' Lv.${existing.level}（最大）'
                    : ' Lv.${existing.level} → ${existing.level + 1}'}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                definition.description,
                style: const TextStyle(fontSize: 12, color: strategyMuted),
              ),
              const SizedBox(height: 12),
              if (maxLevel)
                const StrategyCard(
                  child: Text('この地区は最大レベルです。別の区画への展開を検討してください。'),
                )
              else if (plan == null) ...[
                StrategyCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '建設前の見積もり',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: strategyMint,
                        ),
                      ),
                      StrategyFact('現在の資金', dollars(game.money)),
                      InvestmentEstimate(
                        game: game,
                        preview: preview,
                        cityId: city.id,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '立地・隣接ボーナス',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                for (final bonus in preview.bonuses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '＋ $bonus',
                      style: const TextStyle(fontSize: 12, color: strategyMint),
                    ),
                  ),
                if (preview.bonuses.isEmpty)
                  const Text(
                    'この配置で追加の立地効果はありません。隣の区画も比較できます。',
                    style: TextStyle(fontSize: 12, color: strategyMuted),
                  ),
              ],
              OutlinedButton.icon(
                key: const Key('save-investment'),
                onPressed: maxLevel || plan != null
                    ? null
                    : () {
                        widget.onSaveInvestment(candidate);
                        Navigator.of(context).pop();
                      },
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: const Text('比較に保存'),
              ),
              if (widget.savedInvestment case final saved?) ...[
                const SizedBox(height: 8),
                StrategyCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '保存した候補',
                        style: TextStyle(color: strategyMint, fontSize: 11),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${saved.title}\n${saved.action}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        '別の区画・都市を選ぶと、現在の候補と比較できます。',
                        style: TextStyle(color: strategyMuted, fontSize: 11),
                      ),
                      TextButton.icon(
                        key: const Key('compare-investments'),
                        onPressed: maxLevel || plan != null
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                showDialog<void>(
                                  context: context,
                                  builder: (context) => ListenableBuilder(
                                    listenable: widget.controller,
                                    builder: (context, _) =>
                                        widget.controller.engine == null
                                        ? AlertDialog(
                                            key: const Key(
                                              'investment-comparison-stopped',
                                            ),
                                            title: const Text('進行を停止しました'),
                                            content: Text(
                                              widget.controller.error ??
                                                  '保存状態を確認してください。',
                                            ),
                                            actions: [
                                              TextButton(
                                                key: const Key(
                                                  'close-investment-comparison',
                                                ),
                                                onPressed: () =>
                                                    Navigator.of(context).pop(),
                                                child: const Text('地図へ戻る'),
                                              ),
                                            ],
                                          )
                                        : InvestmentComparison(
                                            game: widget.controller.state,
                                            saved: saved,
                                            current: candidate,
                                          ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.compare_arrows, size: 18),
                        label: const Text('候補を比較'),
                      ),
                      TextButton(
                        key: const Key('clear-investment'),
                        onPressed: () {
                          widget.onSaveInvestment(null);
                          Navigator.of(context).pop();
                        },
                        child: const Text('比較候補を解除'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (investmentResearch != null)
                StrategyFact(
                  '必要研究',
                  GameContent.tasks[investmentResearch]!.name,
                ),
              if (requiredResearch != null)
                TextButton.icon(
                  key: const Key('district-required-research-detail'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onOpenResearch(requiredResearch);
                  },
                  icon: const Icon(Icons.account_tree_outlined, size: 17),
                  label: const Text('必要な研究を確認'),
                ),
              if (definition.id == 'mars_habitat' &&
                  game.habitatChoice == null) ...[
                const SizedBox(height: 12),
                const Text(
                  '居住方式を選ぶ',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: strategyCopper,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'ドームは平地、地下居住はクレーターで効果が高まります。この方針は一度だけ選択します。',
                  style: TextStyle(fontSize: 12, color: strategyMuted),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      key: const Key('choose-dome'),
                      onPressed:
                          !game.achievements.contains('first_landing') ||
                              widget.controller.busy
                          ? null
                          : () => widget.controller.command(
                              (engine) => engine.chooseHabitat('dome'),
                            ),
                      child: const Text('ドーム居住'),
                    ),
                    TextButton(
                      key: const Key('choose-underground'),
                      onPressed:
                          !game.achievements.contains('first_landing') ||
                              widget.controller.busy
                          ? null
                          : () => widget.controller.command(
                              (engine) => engine.chooseHabitat('underground'),
                            ),
                      child: const Text('地下居住'),
                    ),
                  ],
                ),
              ],
              if (preview.blockedReason != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    preview.blockedReason!,
                    key: const Key('district-blocked-reason-detail'),
                    style: const TextStyle(color: strategyCopper, fontSize: 12),
                  ),
                ),
              if (preview.isValid && game.money < preview.cost)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '資金不足 · 予約後、必要な資金が貯まるまで着工を待ちます。'
                    '${city.planet == 'earth' ? ' 先頭の建設が資金待ちだと、後ろの受注も停止します。受注を先にして資金を準備できます。' : ''}',
                    key: const Key('district-funding-warning-detail'),
                    style: const TextStyle(fontSize: 12, color: strategyCopper),
                  ),
                ),
              if (preview.isValid &&
                  city.planet == 'mars' &&
                  game.marsKits == 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '資材不足 · キットが到着するまで着工を待ちます。',
                    style: TextStyle(fontSize: 12, color: strategyCopper),
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                '着工すると地図に工事現場が現れ、完成・増強で建物が変わります。費用は着工時に確保します。',
                style: TextStyle(color: strategyMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
