import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/game_state.dart';
import '../rendering/city_scene.dart';
import 'city_scene_data.dart';
import 'city_facility_palette.dart';
import 'district_location_impact.dart';
import 'first_run_coach.dart';
import 'habitat_choice_dialog.dart';
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
    this.guidedFirstBuild = false,
  });
  final GameController controller;
  final bool renderScene;
  final bool guidedFirstBuild;
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
  bool get _narrowTutorial =>
      widget.guidedFirstBuild && MediaQuery.sizeOf(context).width < 650;
  String get _tutorialInstruction => switch (game.firstRunTutorial) {
    FirstRunTutorialStep.placeHousing =>
      selectedDistrict == null
          ? (_narrowTutorial ? '下の「住宅地区」を選択。' : '右の「住宅地区」を選択。')
          : !hasPlotSelection
          ? '海沿いの光る空地をタップ。'
          : '右下の「建設を予約」へ。',
    FirstRunTutorialStep.finishConstruction => '右のボタンで頼んでください。',
    _ => '上の数字を見て、研究へ。',
  };
  List<DistrictDefinition> get available => GameContent.districts.values
      .where((district) => district.planet == city.planet)
      .toList();

  @override
  void initState() {
    super.initState();
    _restoreTutorialPlot();
  }

  void _restoreTutorialPlot() {
    if (!widget.guidedFirstBuild) return;
    final plan = game.plans
        .where((plan) => plan.id == game.firstRunTutorialPlanId)
        .firstOrNull;
    if (plan?.plotIndex case final plot?) {
      selectedPlot = plot;
      hasPlotSelection = true;
      selectedDistrict = 'housing';
      choosingFacility = false;
      placementMode = false;
    }
  }

  @override
  void didUpdateWidget(covariant CityDevelopment oldWidget) {
    super.didUpdateWidget(oldWidget);
    _restoreTutorialPlot();
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
            width: constraints.maxWidth > 1100
                ? 308
                : constraints.maxWidth < 650
                ? constraints.maxWidth * .44
                : 280,
            child: ColoredBox(
              color: strategySurface,
              child: _narrowTutorial
                  ? Column(
                      children: [
                        FirstRunCoach(
                          step: game.firstRunTutorial,
                          instruction: _tutorialInstruction,
                          portraitVisible: false,
                        ),
                        Expanded(child: _rightPanel()),
                      ],
                    )
                  : _rightPanel(),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _rightPanel() {
    if (widget.guidedFirstBuild) {
      if (game.firstRunTutorial != FirstRunTutorialStep.placeHousing) {
        return _tutorialResult();
      }
      if (choosingFacility) {
        return ListView(
          padding: const EdgeInsets.all(10),
          children: [
            FilledButton.icon(
              key: const Key('district-option-housing'),
              onPressed: () => _chooseFacility('housing'),
              icon: const Icon(Icons.apartment),
              label: const Text('住宅地区'),
            ),
            const Text(
              '人口と税収を増やす',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: strategyMuted),
            ),
          ],
        );
      }
      return _tutorialPlacementInspector();
    }
    return choosingFacility
        ? CityFacilityPalette(
            districts: available,
            selectedId: selectedDistrict,
            onSelected: _chooseFacility,
            lockReason: _facilityLockReason,
          )
        : _inspector();
  }

  Widget _overview() {
    final development = game.cityDevelopment(city.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.guidedFirstBuild)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 8, 5),
            child: Text(
              game.cityName(city.id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          )
        else
          Container(
            decoration: const BoxDecoration(
              color: strategySurface,
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
                              game.cityName(item.id),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                  onPressed: () =>
                      setState(() => showInspector = !showInspector),
                  icon: Icon(
                    showInspector ? Icons.open_in_full : Icons.close_fullscreen,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              CityScene(
                key: ValueKey('city-scene-${city.id}'),
                cityId: city.id,
                cityName: game.cityName(city.id),
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
                onPlotSelected:
                    widget.guidedFirstBuild &&
                        (game.firstRunTutorial !=
                                FirstRunTutorialStep.placeHousing ||
                            selectedDistrict == null)
                    ? (_) {}
                    : _selectPlot,
              ),
              if (_narrowTutorial)
                Positioned(
                  left: 0,
                  bottom: 0,
                  width: 130,
                  height: 130,
                  child: FirstRunPortrait(
                    step: game.firstRunTutorial,
                    size: 130,
                  ),
                ),
            ],
          ),
        ),
        if (widget.guidedFirstBuild && !_narrowTutorial)
          FirstRunCoach(
            step: game.firstRunTutorial,
            instruction: _tutorialInstruction,
          )
        else if (!widget.guidedFirstBuild)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: const BoxDecoration(
              color: strategySurface,
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
    if (!game.cityUnlocked(city.id)) {
      return _discoverySafeReason(
        game.cityLockReason(city.id),
        city.requiredResearch,
      );
    }
    final research = definition.requiredResearch;
    if (research != null && !game.research.contains(research)) {
      return _discoverySafeReason(
        '前提研究：${GameContent.tasks[research]!.name}',
        research,
      );
    }
    if (definition.id == 'mars_habitat' && game.habitatChoice == null) {
      return '居住方式を選択してください';
    }
    return null;
  }

  String? _discoverySafeReason(String? reason, String? researchId) {
    if (reason == null ||
        researchId == null ||
        game.isResearchDiscovered(researchId)) {
      return reason;
    }
    final name = GameContent.tasks[researchId]?.name;
    return name != null && reason.contains(name)
        ? '研究を進めて新しい手掛かりを探してください'
        : reason;
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
                game
                    .districtPreview(city.id, index, selectedDistrict!)
                    .isValid &&
                (!widget.guidedFirstBuild || city.terrainAt(index) == 'coast'))
              index,
        };

  void _chooseFacility(String id) => setState(() {
    if (widget.guidedFirstBuild && id != 'housing') return;
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
    if (widget.guidedFirstBuild &&
        (game.firstRunTutorial != FirstRunTutorialStep.placeHousing ||
            selectedDistrict == null ||
            !_buildablePlots.contains(index))) {
      return;
    }
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
    final candidate = InvestmentCandidate(
      cityId: city.id,
      plotIndex: selectedPlot,
      districtId: id,
      targetLevel: preview.targetLevel,
    );
    final canCompare = hasPlotSelection && plan == null && !maxLevel;
    final saved = widget.savedInvestment;
    final isSaved = saved != null && _sameInvestment(saved, candidate);
    final terrain = GameContent.terrainNames[city.terrainAt(selectedPlot)];
    final reason = _discoverySafeReason(
      hasPlotSelection
          ? preview.blockedReason
          : _facilityLockReason(definition),
      requiredResearch,
    );
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
              DistrictSelectionHeading(
                districtId: id,
                title:
                    '${definition.name}${existing == null ? '' : ' Lv.${existing.level}'}',
              ),
              const SizedBox(height: 6),
              Text(
                hasPlotSelection
                    ? '区画 ${selectedPlot + 1}  ·  $terrain'
                    : '2  地図で建設する区画を選択',
                key: const Key('placement-step'),
                style: TextStyle(
                  color: districtAccent(id),
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
                      child: StrategyStat(
                        '投資費用',
                        dollars(preview.cost),
                        color: districtAccent(id),
                      ),
                    ),
                    Expanded(
                      child: StrategyStat(
                        '工期',
                        gameDuration(preview.durationMs),
                        color: districtAccent(id),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '完成後',
                  style: TextStyle(fontSize: 11, color: strategyMuted),
                ),
                StrategyOutcome(
                  '収支 ${signedDollars(preview.netDeltaPerMinute)}/分',
                  tone: preview.netDeltaPerMinute > 0
                      ? StrategyTone.benefit
                      : preview.netDeltaPerMinute < 0
                      ? StrategyTone.loss
                      : StrategyTone.neutral,
                ),
                if (effects.isNotEmpty)
                  Text(
                    effects.join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: strategyBenefit,
                    ),
                  ),
                const SizedBox(height: 8),
                if (!widget.guidedFirstBuild)
                  DistrictLocationImpact(
                    game: game,
                    cityId: city.id,
                    plotIndex: selectedPlot,
                    preview: preview,
                  ),
                if (preview.isValid && game.money < preview.cost)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '資金待ちで予約できます。後続の受注も待つため、設備の順番に注意。',
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
                      '六角の空地を選択（${_buildablePlots.length}区画）。費用と土地の効果を比べられます。',
                  style: TextStyle(
                    fontSize: 12,
                    color: reason == null ? strategyMint : strategyCopper,
                  ),
                ),
              ],
              if (!widget.guidedFirstBuild && requiredResearch != null)
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
                            : () => confirmHabitatChoice(
                                context,
                                widget.controller,
                                choice.$1,
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
          decoration: BoxDecoration(
            color: districtPanelTint(id),
            border: Border(
              top: BorderSide(color: districtAccent(id).withValues(alpha: .4)),
            ),
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
                          widget.controller.busy ||
                          (widget.guidedFirstBuild &&
                              widget.controller.error != null)
                      ? null
                      : () => _confirmDistrict(id, existing),
                  icon: const Icon(Icons.construction, size: 17),
                  label: Text(
                    existing == null ? '建設を予約' : '地区を強化',
                    semanticsLabel: existing == null
                        ? 'この区画に建設を予約'
                        : 'この地区を強化する',
                  ),
                ),
              if (!widget.guidedFirstBuild)
                Row(
                  children: [
                    _toolbarAction(
                      id: 'city-change-facility',
                      icon: Icons.grid_view_outlined,
                      label: existing != null || plan != null ? '新設' : '用途',
                      tooltip: '建設する施設を選ぶ',
                      onPressed: () => setState(() {
                        choosingFacility = true;
                        placementMode = false;
                      }),
                    ),
                    if (placementMode)
                      _toolbarAction(
                        id: 'city-cancel-placement',
                        icon: Icons.close,
                        label: '解除',
                        tooltip: '配置をやめる',
                        onPressed: _cancelPlacement,
                      ),
                    if (canCompare)
                      _toolbarAction(
                        id: 'city-save-investment',
                        icon: isSaved
                            ? Icons.bookmark
                            : Icons.bookmark_add_outlined,
                        label: isSaved ? '保存済' : '保存',
                        tooltip: isSaved ? 'この比較候補は保存済み' : 'この候補を比較に保存',
                        onPressed: isSaved
                            ? null
                            : () => widget.onSaveInvestment(candidate),
                      ),
                    if (canCompare && saved != null)
                      _toolbarAction(
                        id: 'city-compare-investments',
                        icon: Icons.compare_arrows,
                        label: '比較',
                        tooltip: '保存した候補と比較',
                        onPressed: isSaved
                            ? null
                            : () => _showInvestmentComparison(saved, candidate),
                      ),
                    if (hasPlotSelection)
                      _toolbarAction(
                        id: 'city-open-details',
                        icon: Icons.subject,
                        label: '詳細',
                        tooltip: '費用・効果と投資比較',
                        onPressed: _openDetails,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDistrict(String id, DistrictState? existing) async {
    final targetCity = city.id;
    final targetPlot = selectedPlot;
    final controller = widget.controller;
    await controller.command(
      (engine) => existing == null
          ? engine.enqueueDistrict(targetCity, targetPlot, id)
          : engine.upgradeDistrict(targetCity, targetPlot),
    );
    if (!mounted) return;
    // A save conflict stops the controller and clears its
    // engine before the parent removes this screen.
    final state = controller.engine?.state;
    if (city.id == targetCity &&
        selectedPlot == targetPlot &&
        state?.districtPlanAt(targetCity, targetPlot) != null) {
      setState(() => placementMode = false);
    }
  }

  Widget _tutorialPlacementInspector() {
    final preview = game.districtPreview(city.id, selectedPlot, 'housing');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: const Key('district-inspector'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              if (!hasPlotSelection) ...[
                const Text(
                  '海沿いの光る区画を選択',
                  style: TextStyle(fontSize: 13, color: strategyBlue),
                ),
                const SizedBox(height: 6),
                OutlinedButton(
                  key: const Key('tutorial-select-coast'),
                  onPressed: () => _selectPlot(1),
                  child: const Text('区画 2（海岸）を選択'),
                ),
              ] else ...[
                Text(
                  '区画 ${selectedPlot + 1} · 海岸',
                  style: const TextStyle(fontSize: 12, color: strategyBlue),
                ),
                StrategyFact('費用', dollars(preview.cost)),
                StrategyOutcome(
                  '収支の増加 ${signedDollars(preview.netDeltaPerMinute)}/分',
                  tone: StrategyTone.benefit,
                ),
                Text(
                  '通常 ${gameDuration(preview.durationMs)} · 今回はルナが短縮',
                  style: const TextStyle(fontSize: 12, color: strategyMuted),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: FilledButton.icon(
            key: const Key('confirm-district'),
            onPressed:
                !hasPlotSelection ||
                    !preview.isValid ||
                    widget.controller.busy ||
                    widget.controller.error != null
                ? null
                : () => _confirmDistrict('housing', null),
            icon: const Icon(Icons.construction, size: 17),
            label: const Text('建設を予約'),
          ),
        ),
      ],
    );
  }

  Widget _tutorialResult() {
    final completing =
        game.firstRunTutorial == FirstRunTutorialStep.finishConstruction;
    final plan = game.plans
        .where((plan) => plan.id == game.firstRunTutorialPlanId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: const Key('first-run-result'),
            padding: const EdgeInsets.all(14),
            children: [
              Text(
                completing ? '住宅を建設中' : '住宅が完成！',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (completing) ...[
                if (plan != null) _workStatus(plan),
                const SizedBox(height: 8),
                const Text(
                  '最初の1棟だけ、ルナが工期を短縮します。次からは通常の時間で完成します。',
                  style: TextStyle(fontSize: 13),
                ),
              ] else ...[
                StrategyFact('毎分の税収', dollars(game.taxPerMinute)),
                StrategyFact('毎分の維持費', dollars(game.upkeepPerMinute)),
                StrategyOutcome(
                  '収支 ${signedDollars(game.netPerMinute)}/分',
                  tone: game.netPerMinute >= 0
                      ? StrategyTone.benefit
                      : StrategyTone.loss,
                ),
                const SizedBox(height: 10),
                const Text(
                  '収支がプラスなら、待っている間も資金が増えます。この収入で研究を進めましょう。',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: FilledButton.icon(
            key: Key(
              completing
                  ? 'tutorial-complete-construction'
                  : 'tutorial-continue-income',
            ),
            onPressed: widget.controller.busy || widget.controller.error != null
                ? null
                : () async {
                    if (completing) {
                      await widget.controller.completeTutorialConstruction();
                    } else {
                      await widget.controller.continueFirstRunTutorial();
                    }
                  },
            icon: Icon(
              completing ? Icons.auto_fix_high : Icons.arrow_forward,
              size: 18,
            ),
            label: Text(completing ? 'ルナに完成を頼む' : '研究へ進む'),
          ),
        ),
      ],
    );
  }

  Widget _toolbarAction({
    required String id,
    required IconData icon,
    required String label,
    required String tooltip,
    VoidCallback? onPressed,
  }) => Expanded(
    child: Semantics(
      label: tooltip,
      button: true,
      enabled: onPressed != null,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: TextButton(
          key: Key(id),
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17),
              Text(label, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
      ),
    ),
  );

  bool _sameInvestment(InvestmentCandidate a, InvestmentCandidate b) =>
      a.cityId == b.cityId &&
      a.plotIndex == b.plotIndex &&
      a.districtId == b.districtId &&
      a.targetLevel == b.targetLevel;

  Future<void> _showInvestmentComparison(
    InvestmentCandidate saved,
    InvestmentCandidate current,
  ) => showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => widget.controller.engine == null
          ? AlertDialog(
              key: const Key('investment-comparison-stopped'),
              title: const Text('進行を停止しました'),
              content: Text(widget.controller.error ?? '保存状態を確認してください。'),
              actions: [
                TextButton(
                  key: const Key('close-investment-comparison'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('地図へ戻る'),
                ),
              ],
            )
          : InvestmentComparison(
              game: widget.controller.state,
              saved: saved,
              current: current,
            ),
    ),
  );

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
                    _discoverySafeReason(
                          game.cityLockReason(city.id),
                          city.requiredResearch,
                        ) ??
                        '都市の開発条件を満たしていません',
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
              DistrictSelectionHeading(
                districtId: selected,
                title:
                    '${definition.name}${existing == null
                        ? ''
                        : existing.level >= definition.maxLevel
                        ? ' Lv.${existing.level}（最大）'
                        : ' Lv.${existing.level} → ${existing.level + 1}'}',
                fontSize: 18,
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
                      Text(
                        '建設前の見積もり',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: districtAccent(selected),
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
                DistrictLocationImpact(
                  game: game,
                  cityId: city.id,
                  plotIndex: selectedPlot,
                  preview: preview,
                  expanded: true,
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
                        '${saved.titleFor(game)}\n${saved.action}',
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
                                _showInvestmentComparison(saved, candidate);
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
                  game.isResearchDiscovered(investmentResearch)
                      ? GameContent.tasks[investmentResearch]!.name
                      : '研究を進めると判明します',
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
                          : () => confirmHabitatChoice(
                              context,
                              widget.controller,
                              'dome',
                            ),
                      child: const Text('ドーム居住'),
                    ),
                    TextButton(
                      key: const Key('choose-underground'),
                      onPressed:
                          !game.achievements.contains('first_landing') ||
                              widget.controller.busy
                          ? null
                          : () => confirmHabitatChoice(
                              context,
                              widget.controller,
                              'underground',
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
                    _discoverySafeReason(
                      preview.blockedReason,
                      requiredResearch,
                    )!,
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
