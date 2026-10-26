import 'dart:async';

import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/contextual_tips.dart';
import '../domain/game_state.dart';
import '../domain/research_flavor.dart';
import '../rendering/base_scene.dart';
import 'city_development.dart';
import 'first_run_tutorial.dart';
import 'mission_sound.dart';
import 'command_hud.dart';
import 'completion_center.dart';
import 'contextual_tips.dart';
import 'agency_management.dart';
import 'early_development_guide.dart';
import 'mission_opening.dart';
import 'colony_endings.dart';
import 'facility_queue_card.dart';
import 'investment_comparison.dart';
import 'habitat_choice_dialog.dart';
import 'plan_forecast_dialog.dart';
import 'research_tree.dart';
import 'research_display.dart';
import 'research_developments.dart';
import 'resource_overview_dialog.dart';
import 'strategy_widgets.dart';
import 'title_scene_data.dart';
import 'title_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.controller,
    this.sceneBuilder,
    this.renderScene = true,
    this.showIntroduction = true,
    this.showTitle = true,
  });
  final GameController controller;
  final bool renderScene;
  final bool showIntroduction;
  final bool showTitle;
  final Widget Function(bool, int, int, bool)? sceneBuilder;
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  // This belongs to the running app, never the saved world: every cold launch
  // presents the title, while resume and ordinary controller updates do not.
  bool _titleDismissed = false;
  String planet = 'earth';
  bool get earth => planet == 'earth';
  int tab = 0;
  int facilityTab = 0;
  int agencySection = 0;
  String cityId = 'earth_delta';
  String? researchId;
  String? mapBuildingId;
  int mapBuildingRequest = 0;
  final researchScroll = ScrollController(keepScrollOffset: false);
  InvestmentCandidate? savedInvestment;
  final facilityKeys = {
    for (final id in GameContent.facilities.keys) id: GlobalKey(),
  };
  GameController get controller => widget.controller;
  GameState get game => controller.state;
  String? get visibleResearchId =>
      researchId != null && game.isResearchDiscovered(researchId!)
      ? researchId
      : null;
  bool get _firstRunActive =>
      widget.showIntroduction &&
      game.openingSeen &&
      game.firstRunTutorial != FirstRunTutorialStep.completed;
  bool get _compactLandscape => MediaQuery.sizeOf(context).height < 450;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    researchScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(controller.resume());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(controller.save());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.engine == null) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: controller.error == null
                  ? const CircularProgressIndicator()
                  : Semantics(liveRegion: true, child: Text(controller.error!)),
            ),
          ),
        );
      }
      if (widget.showTitle && !_titleDismissed) {
        return TitleScreen(
          game: game,
          renderScene: widget.renderScene,
          onStart: () => setState(() => _titleDismissed = true),
        );
      }
      if (widget.showIntroduction &&
          (!game.openingSeen || controller.finishingOpening)) {
        return MissionOpening(
          controller: controller,
          renderScene: widget.renderScene,
        );
      }
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              ExcludeFocus(
                excluding: _firstRunActive,
                child: AbsorbPointer(
                  absorbing: _firstRunActive,
                  child: _header(),
                ),
              ),
              Expanded(
                child: _firstRunActive
                    ? FirstRunTutorial(
                        controller: controller,
                        renderScene:
                            widget.renderScene && widget.sceneBuilder == null,
                        onComplete: () {
                          if (!mounted) return;
                          setState(() {
                            cityId = 'earth_delta';
                            planet = 'earth';
                            tab = 1;
                          });
                          _showGuidance();
                        },
                      )
                    : switch (tab) {
                        0 => StrategySplit(
                          overview: _world(),
                          detail: _planetDetails(),
                        ),
                        1 => CityDevelopment(
                          key: ValueKey('city-development-$mapBuildingRequest'),
                          controller: controller,
                          renderScene:
                              widget.renderScene && widget.sceneBuilder == null,
                          onOpenGlobe: () => setState(() => tab = 0),
                          onOpenOperations: () => setState(() {
                            facilityTab = 0;
                            tab = 3;
                          }),
                          cityId: cityId,
                          initialMapBuildingId: mapBuildingId,
                          onCityChanged: _selectCity,
                          savedInvestment: savedInvestment,
                          onSaveInvestment: (candidate) => setState(() {
                            savedInvestment = candidate;
                          }),
                          onOpenResearch: (id) => setState(() {
                            researchId = id;
                            tab = 2;
                          }),
                        ),
                        2 => StrategySplit(
                          overview: ResearchTree(
                            game: game,
                            selectedId: visibleResearchId,
                            onSelected: _selectResearch,
                            onSelectionCleared: () =>
                                setState(() => researchId = null),
                            requirementReasons:
                                controller.engine!.researchRequirementReasons,
                          ),
                          detail: visibleResearchId == null
                              ? null
                              : _researchDetails(),
                        ),
                        3 => _facilities(),
                        _ => AgencyManagement(
                          controller: controller,
                          section: agencySection,
                          onSectionChanged: (section) =>
                              setState(() => agencySection = section),
                          onOpenOperations: () => setState(() {
                            facilityTab = 0;
                            tab = 3;
                          }),
                        ),
                      },
              ),
              if (!_firstRunActive) _navigation(),
              _footer(),
            ],
          ),
        ),
      );
    },
  );

  Widget _header() => CommandHud(
    game: game,
    devTools: controller.devTools,
    busy: controller.busy,
    onAdvance: () => controller.advanceForDevelopment(),
    onAdvanceDuration: (duration) =>
        controller.advanceForDevelopment(duration: duration),
    onOpenResources: () => showDialog<void>(
      context: context,
      builder: (_) => ResourceOverviewDialog(
        controller: controller,
        onOpenAgency: () => setState(() {
          agencySection = 0;
          tab = 4;
        }),
      ),
    ),
  );

  Widget _navigation() => Container(
    key: const Key('strategy-command-dock'),
    height: _compactLandscape ? 46 : 56,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [strategyPanel, strategySurface],
      ),
      border: Border(top: BorderSide(color: strategyLine)),
    ),
    child: Row(
      children: [
        if (MediaQuery.sizeOf(context).width >= 1100)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 22),
            child: Text(
              '開発指令',
              style: TextStyle(
                fontSize: 12,
                color: strategyCopper,
                letterSpacing: 3,
              ),
            ),
          ),
        for (final (index, entry) in [
          (Icons.public, '惑星マップ'),
          (Icons.location_city_outlined, '都市開発'),
          (Icons.account_tree_outlined, '研究ツリー'),
          (Icons.view_timeline_outlined, '設備・進行'),
          (Icons.groups_outlined, '機関運営'),
        ].indexed)
          Expanded(
            child: Semantics(
              selected: tab == index,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tab == index ? strategySelected : Colors.transparent,
                  border: Border(
                    top: BorderSide(
                      color: tab == index ? strategyBlue : Colors.transparent,
                      width: 2,
                    ),
                    right: const BorderSide(color: strategyLine),
                  ),
                ),
                child: SizedBox.expand(
                  child: TextButton.icon(
                    key: Key('navigation-$index'),
                    onPressed: () => setState(() {
                      if (index == 2 && tab != 2) researchId = null;
                      if (index != 1) mapBuildingId = null;
                      tab = index;
                    }),
                    style: TextButton.styleFrom(
                      foregroundColor: tab == index
                          ? strategyBlue
                          : strategyMuted,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      shape: const RoundedRectangleBorder(),
                    ),
                    icon:
                        MediaQuery.sizeOf(context).width < 800 ||
                            MediaQuery.textScalerOf(context).scale(14) > 18
                        ? null
                        : Icon(entry.$1, size: 19),
                    label: Text(
                      entry.$2,
                      style: TextStyle(
                        fontSize: _compactLandscape ? 12 : 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  void _selectCity(String id) => setState(() {
    if (!game.planetUnlocked(GameContent.cities[id]!.planet)) return;
    cityId = id;
    planet = GameContent.cities[id]!.planet;
    mapBuildingId = null;
  });

  void _openMapBuilding(String technologyId, String targetCity) => setState(() {
    cityId = targetCity;
    planet = GameContent.cities[targetCity]!.planet;
    mapBuildingId = technologyId;
    mapBuildingRequest++;
    tab = 1;
  });

  int _cityDevelopment(CityDefinition city) {
    final placed = game.districts.values
        .where((district) => district.cityId == city.id)
        .fold(0, (sum, district) => sum + district.level);
    final buildings = game
        .cityBuildings(city.id)
        .where(
          (building) =>
              building.technologyId != 'base_lab' &&
              !building.legacySite &&
              building.plotIndex >= 0 &&
              !building.underConstruction,
        )
        .map((building) => building.id)
        .toSet()
        .length;
    final developed = placed + buildings;
    if (city.id == 'earth_delta') return developed + game.earthLevel;
    if (city.id == 'mars_arcadia') {
      final locatedHabitats = game.districts.values
          .where((district) => district.districtId == 'mars_habitat')
          .length;
      return developed +
          (game.marsHabitats - locatedHabitats).clamp(0, game.marsHabitats);
    }
    return developed;
  }

  Widget _world() => Stack(
    key: const Key('planet-command-map'),
    children: [
      Positioned.fill(
        child:
            widget.sceneBuilder?.call(
              earth,
              game.earthLevel,
              game.marsHabitats,
              game.marsKits > 0,
            ) ??
            (widget.renderScene
                ? BaseScene(
                    earth: earth,
                    moon: planet == 'moon',
                    earthLevel: game.earthLevel,
                    marsHabitats: game.marsHabitats,
                    marsSnapshot: buildTitleSceneSnapshot(game),
                    hasCargo: planet == 'moon'
                        ? game.moonKits > 0
                        : game.marsKits > 0,
                    cities: [
                      for (final city in GameContent.cities.values.where(
                        (city) => city.planet == planet,
                      ))
                        SceneCity(
                          id: city.id,
                          name: game.cityName(city.id),
                          latitude: city.latitude,
                          longitude: city.longitude,
                          development: _cityDevelopment(city),
                          isActive: game.cityUnlocked(city.id),
                        ),
                    ],
                    selectedCityId: cityId,
                    onCitySelected: _selectCity,
                  )
                : const ColoredBox(color: strategyBackground)),
      ),
      Positioned(
        left: 18,
        top: 12,
        right: 12,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${planetLabel(planet)}圏',
                      style: TextStyle(
                        fontSize: _compactLandscape ? 19 : 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 4,
                        shadows: const [Shadow(blurRadius: 5)],
                      ),
                    ),
                    Text(
                      '全球 / ${game.cityName(cityId)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: strategyMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (final item in [
              'earth',
              'moon',
              'mars',
            ].where(game.planetUnlocked))
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 66,
                    minHeight: 44,
                  ),
                  child: ChoiceChip(
                    key: Key('select-planet-$item'),
                    label: SizedBox(
                      width: 32,
                      child: Text(
                        planetLabel(item),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                      ),
                    ),
                    selected: planet == item,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      planet = item;
                      cityId = GameContent.cities.values
                          .firstWhere((city) => city.planet == planet)
                          .id;
                    }),
                  ),
                ),
              ),
          ],
        ),
      ),
      Positioned(
        left: 18,
        right: 18,
        bottom: 12,
        child: IgnorePointer(
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _tag(
                planet == 'moon'
                    ? '月面施設 ${game.cityDevelopment(cityId).completedPlots}'
                    : earth
                    ? '人口 ${formatInteger(game.population)} 人'
                    : '居住者 ${formatInteger(game.marsResidents)} 人',
              ),
              _tag(
                earth
                    ? '輸送待ちキット ${game.earthKits}'
                    : '到着キット ${planet == 'moon' ? game.moonKits : game.marsKits}',
              ),
              _tag(
                planet == 'moon'
                    ? '打上げ費用 −${game.launchCostReductionPercent}%'
                    : earth
                    ? '税収 ${dollars(game.taxPerMinute)}/分'
                    : '居住施設 ${game.marsHabitats}',
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _tag(String text) => DecoratedBox(
    decoration: BoxDecoration(
      color: strategyPanel,
      border: Border.all(color: strategyLine),
      borderRadius: BorderRadius.circular(2),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    ),
  );

  Widget _planetDetails() {
    final city = GameContent.cities[cityId]!;
    final cities = GameContent.cities.values.where(
      (candidate) => candidate.planet == planet,
    );
    return ListView(
      key: const Key('planet-detail'),
      padding: _compactLandscape
          ? const EdgeInsets.fromLTRB(14, 10, 14, 12)
          : const EdgeInsets.all(18),
      children: [
        if (!_compactLandscape && !game.tutorialHidden) _nextGoal(),
        if (!_compactLandscape && game.tipsEnabled) ...[
          const SizedBox(height: 8),
          _contextualTips(),
        ],
        SizedBox(height: _compactLandscape ? 8 : 20),
        if (_compactLandscape)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              '都市を選ぶ',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          )
        else
          const StrategyHeading('都市一覧', '都市を選び、地形と施設を見ながら開発を指揮します。'),
        for (final candidate in cities) _cityCommandRow(candidate),
        if (_compactLandscape) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('open-city'),
            onPressed: () => setState(() => tab = 1),
            icon: const Icon(Icons.grid_view, size: 18),
            label: const Text('都市を開く・区画を計画'),
          ),
          const SizedBox(height: 8),
          if (!game.tutorialHidden) _nextGoal(),
          if (game.tipsEnabled) ...[
            const SizedBox(height: 8),
            _contextualTips(),
          ],
        ],
        if (!_compactLandscape) ...[
          const SizedBox(height: 14),
          Text(
            game.cityName(city.id),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            city.description,
            style: const TextStyle(color: strategyMuted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            '${game.cityDevelopment(city.id).stageName} · 完成 ${game.cityDevelopment(city.id).completedPlots}/${city.plotCount}区画 · 総Lv.${game.cityDevelopment(city.id).totalLevels}',
            key: const Key('planet-city-development'),
            style: const TextStyle(color: strategyMint, fontSize: 12),
          ),
          if (game.cityDevelopment(city.id).nextStageAtTotalLevels
              case final next?)
            Text(
              '次の発展段階まで あと ${next - game.cityDevelopment(city.id).totalLevels} Lvの建設・増強',
              style: const TextStyle(color: strategyMuted, fontSize: 11),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('open-city'),
            onPressed: () => setState(() => tab = 1),
            icon: const Icon(Icons.grid_view, size: 18),
            label: const Text('都市を開く・区画を計画'),
          ),
        ],
        if (!game.planetUnlocked('mars')) ...[
          const SizedBox(height: 12),
          Text(
            game.planetUnlocked('moon')
                ? '次の目標：月面拠点と月面打ち上げ基地を整え、火星探査機を打ち上げる。'
                : '次の目標：共用宇宙港で衛星を打ち上げ、月への航路を開く。',
            key: const Key('next-destination-goal'),
            style: const TextStyle(fontSize: 12, color: strategyMint),
          ),
          TextButton.icon(
            key: const Key('open-space-progression'),
            onPressed: () => setState(() {
              tab = 3;
              facilityTab = 2;
            }),
            icon: const Icon(Icons.rocket_launch_outlined, size: 18),
            label: const Text('打ち上げ・月面計画を開く'),
          ),
        ],
        if (planet == 'mars')
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              '現在は閉鎖居住の開発段階です。火星の屋外はまだ居住できません。',
              style: TextStyle(fontSize: 11, color: strategyMuted),
            ),
          ),
      ],
    );
  }

  Widget _cityCommandRow(CityDefinition city) {
    final selected = city.id == cityId;
    final unlocked = game.cityUnlocked(city.id);
    final development = game.cityDevelopment(city.id);
    return Material(
      color: selected ? strategySelected : strategySurface,
      child: InkWell(
        key: Key('select-city-${city.id}'),
        onTap: () => _selectCity(city.id),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? strategyBlue : Colors.transparent,
                width: 3,
              ),
              bottom: const BorderSide(color: strategyLine),
            ),
          ),
          child: Row(
            children: [
              Icon(
                unlocked ? Icons.location_city : Icons.lock_outline,
                size: 18,
                color: unlocked ? strategyMint : strategyMuted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.cityName(city.id),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (!_compactLandscape)
                      Text(
                        unlocked
                            ? '${development.stageName} · 総Lv.${development.totalLevels}'
                            : game.cityLockReason(city.id) ?? '研究が必要',
                        style: const TextStyle(
                          fontSize: 11,
                          color: strategyMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (unlocked)
                Text(
                  '${development.completedPlots}/${city.plotCount}',
                  style: const TextStyle(fontSize: 12, color: strategyMuted),
                ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 16, color: strategyMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nextGoal({bool closeDialog = false}) => EarlyDevelopmentGuide(
    controller: controller,
    compact: _compactLandscape,
    onResearch: (id) => _guideNavigation(closeDialog, () {
      researchId = id;
      tab = 2;
    }),
    onCity: (id) => _guideNavigation(closeDialog, () {
      cityId = id;
      planet = GameContent.cities[id]!.planet;
      tab = 1;
    }),
    onOperations: (section, {String? facilityId}) =>
        _guideNavigation(closeDialog, () {
          facilityTab = section;
          tab = 3;
          if (section == 0 && facilityId != null) _focusFacility(facilityId);
        }),
    onAgency: (section) => _guideNavigation(closeDialog, () {
      agencySection = section;
      tab = 4;
    }),
  );

  void _selectResearch(String id) {
    if (!game.isResearchDiscovered(id)) return;
    setState(() => researchId = id);
    if (researchScroll.hasClients) researchScroll.jumpTo(0);
  }

  Widget _researchDetails() {
    final id = visibleResearchId;
    if (id == null || !game.isResearchDiscovered(id)) {
      return const Center(child: Text('研究を進めると、新しい着想が見つかります。'));
    }
    final task = GameContent.tasks[id]!;
    final technology = GameContent.researchTechnologies[id]!;
    final activePlan = game.plans
        .where((plan) => plan.taskId == id && !plan.isFinished)
        .firstOrNull;
    final legacyRunning = activePlan?.status == 'running';
    final researched = game.research.contains(id);
    final status = researchStatus(
      game,
      task,
      controller.engine!.researchRequirementReasons(id),
    );
    final requiredPoints = GameContent.researchPointCost(id);
    final canUnlock = game.researchPoints >= requiredPoints;
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const Key('research-detail'),
            controller: researchScroll,
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('研究詳細', style: TextStyle(fontSize: 12)),
                  ),
                  IconButton(
                    key: const Key('close-research-detail'),
                    tooltip: '研究詳細を閉じる',
                    onPressed: () => setState(() => researchId = null),
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(108),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        technology.field.assetPath,
                        fit: BoxFit.cover,
                        alignment: Alignment.centerRight,
                        excludeFromSemantics: true,
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xF0081427), Color(0x70081427)],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${technology.field.label} / ${technology.branch} · $status',
                              style: const TextStyle(
                                fontSize: 11,
                                color: strategyMint,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              task.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              StrategyCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '解放される設計',
                      style: TextStyle(fontSize: 11, color: strategyMuted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      researchUnlockSummary(game, task),
                      key: const Key('research-unlocks'),
                      style: const TextStyle(fontSize: 14, color: strategyMint),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '解放後、導入する都市と設備・人員への投資を決めます。',
                      style: TextStyle(fontSize: 11, color: strategyMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (legacyRunning) ...[
                const Text(
                  '更新前に支払った研究を続行しています。RPの追加消費はありません。',
                  style: TextStyle(fontSize: 12, color: strategyCopper),
                ),
                StrategyFact('残り時間', gameDuration(activePlan!.remainingMs)),
              ] else ...[
                StrategyFact('必要RP', '$requiredPoints RP'),
                StrategyFact(
                  '保有RP',
                  '${game.researchPoints.toStringAsFixed(1)} RP',
                ),
                StrategyFact(
                  'RP生産',
                  '${game.researchPointsPerMinute.toStringAsFixed(1)} RP/分',
                ),
                const Text(
                  '必要なRPで必ず解放。解放後に追加の研究待機はありません。',
                  style: TextStyle(fontSize: 12, color: strategyMuted),
                ),
                if (!researched && !canUnlock)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      game.researchWaitMs(id) == null
                          ? '研究施設に人員を配分するとRPを生産できます。'
                          : '今の生産を続けた場合、必要量まで約${gameDuration(game.researchWaitMs(id)!)}。予約済み研究の消費は別です。',
                      style: const TextStyle(
                        fontSize: 12,
                        color: strategyCopper,
                      ),
                    ),
                  ),
              ],
              if (activePlan != null)
                TextButton.icon(
                  key: const Key('research-open-queue'),
                  onPressed: () {
                    setState(() {
                      tab = 3;
                      facilityTab = 0;
                    });
                    _focusFacility('lab');
                  },
                  icon: const Icon(Icons.view_timeline_outlined, size: 17),
                  label: const Text('研究の予約を確認'),
                ),
              if (researched &&
                  GameContent.mapBuildingDefinitions.containsKey(id))
                FilledButton.tonalIcon(
                  key: Key('research-map-building-$id'),
                  onPressed: () {
                    final definition = GameContent.mapBuildingDefinitions[id]!;
                    final city = GameContent.cities.values
                        .where(
                          (city) =>
                              definition.allowedPlanets.contains(city.planet) &&
                              game.cityUnlocked(city.id),
                        )
                        .firstOrNull;
                    if (city != null) {
                      _openMapBuilding(id, city.id);
                    } else {
                      setState(() {
                        tab = 3;
                        facilityTab = 4;
                      });
                    }
                  },
                  icon: const Icon(Icons.place_outlined, size: 17),
                  label: const Text('解放した施設を地図で建設'),
                ),
              TextButton.icon(
                key: const Key('research-parallel-city'),
                onPressed: () => setState(() {
                  cityId = 'earth_delta';
                  planet = 'earth';
                  mapBuildingId = null;
                  tab = 1;
                }),
                icon: const Icon(Icons.location_city_outlined, size: 17),
                label: const Text('都市で研究と収入の基盤を育てる'),
              ),
              TextButton.icon(
                key: const Key('research-agency'),
                onPressed: () => setState(() {
                  agencySection = 0;
                  tab = 4;
                }),
                icon: const Icon(Icons.groups_outlined, size: 17),
                label: const Text('研究者を配分する'),
              ),
              ExpansionTile(
                key: ValueKey('research-explanation-$id'),
                tilePadding: EdgeInsets.zero,
                title: const Text('運用の特徴', style: TextStyle(fontSize: 12)),
                children: [
                  Text(
                    technology.tradeoff,
                    style: const TextStyle(fontSize: 12, color: strategyMuted),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              StrategyCard(
                key: Key('research-flavor-$id'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '未来の一景',
                      style: TextStyle(fontSize: 12, color: strategyCopper),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ResearchFlavor.forTechnology(id),
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.7,
                        color: strategyText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        StrategyActionBar(
          message: !researched && !legacyRunning && !canUnlock
              ? '予約すると、順番と必要なRPが揃った時に解放します。'
              : null,
          child: FilledButton.icon(
            key: Key('queue-$id'),
            onPressed: controller.busy || activePlan != null
                ? null
                : researched
                ? () => setState(() {
                    tab = 3;
                    facilityTab = 4;
                  })
                : canUnlock
                ? () =>
                      controller.command((engine) => engine.unlockResearch(id))
                : () => _reserve(id),
            icon: Icon(
              researched ? Icons.construction_outlined : Icons.auto_awesome,
              size: 18,
            ),
            label: Text(
              activePlan != null
                  ? status
                  : researched
                  ? '施設・機体の導入へ'
                  : canUnlock
                  ? '技術を解放する'
                  : 'RPの蓄積を待って解放',
              semanticsLabel: researched
                  ? '${task.name}の導入計画を見る'
                  : '${task.name}を解放',
            ),
          ),
        ),
      ],
    );
  }

  Widget _facilities() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          children: [
            for (final (index, label) in [
              '稼働状況',
              '製造・受注',
              '輸送・居住',
              '開発記録',
              '技術の導入',
            ].indexed)
              Expanded(
                child: TextButton(
                  key: Key('operations-$index'),
                  onPressed: () => setState(() => facilityTab = index),
                  style: TextButton.styleFrom(
                    foregroundColor: facilityTab == index
                        ? strategyMint
                        : strategyMuted,
                    backgroundColor: facilityTab == index
                        ? strategySelected
                        : Colors.transparent,
                  ),
                  child: Text(label, style: const TextStyle(fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: ListView(
          key: ValueKey('operations-list-$facilityTab'),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          children: switch (facilityTab) {
            0 => _queueOverview(),
            1 => [
              const StrategyHeading(
                '地球の産業計画',
                '受注で運転資金を得ながら、月・火星向けの製造に共用工場を配分します。',
              ),
              _taskCard('factory_contract'),
              _taskCard('habitat_kit'),
              ..._advancedTasks(['precision_contract', 'batch_habitat_kit']),
              _cityShortcut('地球の住宅や産業を増やす', 'earth_delta'),
            ],
            2 => [
              const StrategyHeading(
                '地球から月、そして火星へ',
                '初打ち上げで月へ。月面の拠点と打ち上げ基地を整え、火星への航路を開きます。',
              ),
              _taskCard('launch_contract'),
              if (game.planetUnlocked('moon')) ...[
                _taskCard('moon_delivery'),
                _cityShortcut('月面の拠点・打ち上げ基地を建設', 'moon_south_pole'),
                if (!game.planetUnlocked('mars')) _taskCard('mars_probe'),
              ],
              if (game.planetUnlocked('mars')) ...[
                _taskCard('mars_delivery'),
                if (game.habitatChoice == null) _branch(),
                _cityShortcut('火星の居住区を配置する', 'mars_arcadia'),
                ..._advancedTasks(['cargo_delivery']),
              ],
              ..._advancedTasks(['orbital_contract']),
              StrategyFact('打ち上げ費用の削減', '−${game.launchCostReductionPercent}%'),
              const Text(
                '稼働中の月面設備や地球の宇宙エレベーターで、次に出発する輸送の費用を抑えます。建設費と維持費も見比べましょう。',
                style: TextStyle(fontSize: 12, color: strategyMuted),
              ),
            ],
            4 => [
              ResearchDevelopments(
                controller: controller,
                onReserveOperation: _reserve,
                onOpenMap: _openMapBuilding,
              ),
            ],
            _ => _journal(),
          },
        ),
      ),
    ],
  );

  List<Widget> _advancedTasks(List<String> ids) => [
    for (final id in ids)
      if (GameContent.tasks[id]!.prerequisiteIds.every(game.research.contains))
        _taskCard(id),
  ];

  Widget _cityShortcut(String label, String id) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: OutlinedButton.icon(
      onPressed: () => setState(() {
        cityId = id;
        planet = GameContent.cities[id]!.planet;
        tab = 1;
      }),
      icon: const Icon(Icons.location_city_outlined),
      label: Text(label),
    ),
  );

  void _focusFacility(String? id) {
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || tab != 3 || facilityTab != 0) return;
      final target = facilityKeys[id]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
        );
      }
    });
  }

  List<Widget> _queueOverview() => [
    const StrategyHeading(
      '共用設備の稼働計画',
      '↑↓で予約順を変更。設備を休止すると、対応する地区の効果と維持費も停止します。',
    ),
    Text(
      '有効な計画 ${game.activePlanCount}/${GameContent.maxActivePlans}件 · 研究・建設・反復予約を含みます',
      key: const Key('active-plan-count'),
      style: const TextStyle(fontSize: 12, color: strategyMuted),
    ),
    const SizedBox(height: 8),
    Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: const Key('open-plan-forecast'),
        onPressed: controller.busy
            ? null
            : () => showDialog<void>(
                context: context,
                builder: (_) => PlanForecastDialog(controller: controller),
              ),
        icon: const Icon(Icons.update, size: 18),
        label: const Text('予約の見通し'),
      ),
    ),
    const SizedBox(height: 12),
    LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000 ? 2 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final id in GameContent.facilities.keys.where(
              (id) => !['moon', 'mars'].contains(id) || game.planetUnlocked(id),
            ))
              SizedBox(
                width: width,
                child: FacilityQueueCard(
                  key: facilityKeys[id],
                  controller: controller,
                  facilityId: id,
                ),
              ),
          ],
        );
      },
    ),
    const SizedBox(height: 16),
    if (game.habitatChoice == null &&
        game.achievements.contains('first_landing'))
      _branch(),
    const QueueRulesDisclosure(),
  ];

  Widget _taskCard(String id) {
    final task = GameContent.tasks[id]!;
    final spaceReason = game.spaceTaskLockReason(task);
    final needs = <String>[
      for (final requirement in task.prerequisiteIds)
        '${GameContent.tasks[requirement]!.name}${game.research.contains(requirement) ? ' ✓' : '（未完了）'}',
      if (task.inputResource != null)
        '${GameContent.resourceNames[task.inputResource]} ${task.inputAmount}基',
      if (task.requiresHabitatChoice)
        game.habitatChoice == null ? '居住方式の選択（未選択）' : '居住方式を選択済み',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StrategyCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  task.facilityId == 'launch'
                      ? Icons.rocket_launch_outlined
                      : Icons.precision_manufacturing_outlined,
                  color: strategyCopper,
                  size: 21,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    task.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _tag(GameContent.facilities[task.facilityId]!.name),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              ['mars_delivery', 'cargo_delivery'].contains(task.id)
                  ? '輸送船「${game.rocketName}」で、${game.cityName('mars_arcadia')}へ。${task.description}'
                  : task.description,
              style: const TextStyle(color: strategyMuted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 22,
              runSpacing: 10,
              children: [
                StrategyStat('開始費用', dollars(game.taskCost(task))),
                if (game.taskCost(task) < task.cost)
                  StrategyStat(
                    '基準からの削減',
                    '${dollars(task.cost - game.taskCost(task))} / 回',
                  ),
                StrategyStat(
                  '1回の所要時間',
                  gameDuration(game.currentTaskDurationMs(id)),
                ),
                if (task.reward > 0)
                  StrategyStat(
                    '完成時の受取',
                    dollars(task.reward),
                    color: strategyCopper,
                  ),
                if (task.outputResource != null)
                  StrategyStat(
                    '完成時の成果',
                    '${GameContent.resourceNames[task.outputResource]} ${task.outputAmount}基',
                  ),
              ],
            ),
            if (needs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '開始条件  ${needs.join(' / ')}',
                  style: const TextStyle(fontSize: 12, color: strategyMuted),
                ),
              ),
            if (spaceReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  spaceReason,
                  key: Key('space-condition-$id'),
                  style: const TextStyle(fontSize: 12, color: strategyCopper),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                FilledButton.tonal(
                  key: Key('queue-$id'),
                  onPressed: controller.busy ? null : () => _reserve(id),
                  child: Text('予約する', semanticsLabel: '${task.name}を予約'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reserve(String id) async {
    int? repeats = 1;
    final task = GameContent.tasks[id]!;
    if (!task.unique && id != 'mars_probe') {
      final result = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('実行回数を選ぶ'),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                '${task.name}\n1回 ${dollars(game.taskCost(task))} · ${gameDuration(game.currentTaskDurationMs(id))}',
                style: const TextStyle(color: strategyMuted, fontSize: 13),
              ),
            ),
            for (final (value, label) in [
              (1, '1回'),
              (3, '3回'),
              (-1, '無期限・分岐まで'),
            ])
              SimpleDialogOption(
                key: Key('repeat-$value'),
                onPressed: () => Navigator.pop(context, value),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(label),
                ),
              ),
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '費用は1回ずつ着手時に支払います。無期限の反復は、設備・進行で終了できます。',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
      if (result == null) return;
      repeats = result == -1 ? null : result;
    }
    await controller.command((engine) => engine.enqueue(id, repeats: repeats));
    if (mounted) {
      setState(() {
        tab = 3;
        facilityTab = 0;
      });
      _focusFacility(task.facilityId);
    }
  }

  Widget _branch() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: StrategyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '居住方式を選ぶ',
            style: TextStyle(
              color: strategyCopper,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            '初輸送後に一度だけ選択します。ドームは平地、地下居住はクレーターで居住地区の効果が高まります。都市の地形を見て方針を決めましょう。',
            style: TextStyle(fontSize: 12, color: strategyMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: [
              TextButton(
                key: const Key('choose-dome'),
                onPressed:
                    !game.achievements.contains('first_landing') ||
                        controller.busy
                    ? null
                    : () => confirmHabitatChoice(context, controller, 'dome'),
                child: const Text('ドーム居住'),
              ),
              TextButton(
                key: const Key('choose-underground'),
                onPressed:
                    !game.achievements.contains('first_landing') ||
                        controller.busy
                    ? null
                    : () => confirmHabitatChoice(
                        context,
                        controller,
                        'underground',
                      ),
                child: const Text('地下居住'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  List<Widget> _journal() => [
    const StrategyHeading('開発の記録', '都市と研究の成果を振り返ります。閉鎖居住の実績と全球の居住可能化は別の到達点です。'),
    Wrap(
      spacing: 32,
      runSpacing: 12,
      children: [
        StrategyStat('地球人口', '${game.population} 人'),
        StrategyStat('火星居住者', '${game.marsResidents} 人'),
        StrategyStat('達成記録', '${game.achievements.length} 件'),
      ],
    ),
    const SizedBox(height: 18),
    for (final entry in game.log.reversed)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '· ${legacyCurrencyLabel(entry)}',
          style: const TextStyle(fontSize: 13),
        ),
      ),
  ];

  void _guideNavigation(bool closeDialog, VoidCallback action) {
    if (closeDialog) Navigator.pop(context);
    setState(action);
  }

  Widget _contextualTips({bool closeDialog = false}) => ContextualTipsPanel(
    game: game,
    compact: _compactLandscape,
    dismissedIds: game.dismissedTipIds,
    onDismiss: (id) => controller.command((engine) {
      engine.state.dismissedTipIds.add(id);
      return null;
    }),
    onOpen: (tip) => _guideNavigation(closeDialog, () {
      switch (tip.destination) {
        case ContextualTipDestination.operations:
          tab = 3;
          facilityTab = tip.operationsSection.index;
          if (facilityTab == 0) _focusFacility(tip.facilityId);
        case ContextualTipDestination.research:
          researchId = tip.taskId ?? 'life_support';
          tab = 2;
        case ContextualTipDestination.city:
          cityId = tip.cityId ?? 'earth_delta';
          planet = GameContent.cities[cityId]!.planet;
          tab = 1;
        case ContextualTipDestination.agency:
          agencySection = tip.agencySection.index;
          tab = 4;
      }
    }),
  );

  void _showGuidance() => showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => AlertDialog(
        title: const Text('開発ガイド・Tips'),
        content: SizedBox(
          width: 560,
          child: controller.engine == null
              ? const Text('保存状態を確認してください。')
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (controller.error != null)
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '表示設定を保存できていません。',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: strategyCopper,
                                ),
                              ),
                            ),
                            TextButton(
                              key: const Key('retry-guidance-save'),
                              onPressed: controller.busy
                                  ? null
                                  : controller.save,
                              child: const Text('再保存'),
                            ),
                          ],
                        ),
                      _nextGoal(closeDialog: true),
                      if (game.tipsEnabled) ...[
                        const SizedBox(height: 12),
                        _contextualTips(closeDialog: true),
                      ],
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            key: const Key('edit-mission-names'),
                            onPressed: controller.busy
                                ? null
                                : () => showMissionNames(context, controller),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('都市・ロケットの名前'),
                          ),
                          TextButton.icon(
                            key: const Key('open-colony-endings'),
                            onPressed: () =>
                                showColonyEndings(context, game: game),
                            icon: const Icon(
                              Icons.auto_stories_outlined,
                              size: 16,
                            ),
                            label: const Text('物語の記録'),
                          ),
                          TextButton.icon(
                            key: const Key('replay-opening'),
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (replayContext) => Dialog.fullscreen(
                                child: MissionOpening(
                                  renderScene: widget.renderScene,
                                  controller: controller,
                                  replay: true,
                                  onClose: () => Navigator.pop(replayContext),
                                ),
                              ),
                            ),
                            icon: const Icon(
                              Icons.play_circle_outline,
                              size: 16,
                            ),
                            label: const Text('物語を振り返る'),
                          ),
                        ],
                      ),
                      ExpansionTile(
                        key: const Key('guidance-display-settings'),
                        tilePadding: EdgeInsets.zero,
                        title: const Text(
                          'ガイドの表示設定',
                          style: TextStyle(fontSize: 13),
                        ),
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              '惑星マップに導入ガイドを表示',
                              style: TextStyle(fontSize: 13),
                            ),
                            value: !game.tutorialHidden,
                            onChanged: controller.busy
                                ? null
                                : (value) => controller.command((engine) {
                                    engine.state.tutorialHidden = !value;
                                    return null;
                                  }),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              '状況に応じたTipsを表示',
                              style: TextStyle(fontSize: 13),
                            ),
                            value: game.tipsEnabled,
                            onChanged: controller.busy
                                ? null
                                : (value) => controller.command((engine) {
                                    engine.state.tipsEnabled = value;
                                    return null;
                                  }),
                          ),
                          TextButton(
                            key: const Key('restore-dismissed-tips'),
                            onPressed:
                                controller.busy || game.dismissedTipIds.isEmpty
                                ? null
                                : () => controller.command((engine) {
                                    engine.state.dismissedTipIds.clear();
                                    return '非表示にしたTipsを戻しました';
                                  }),
                            child: const Text('非表示にしたTipsを戻す'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    ),
  );

  void _showCompletions() => showDialog<void>(
    context: context,
    builder: (_) => CompletionCenter(
      controller: controller,
      onOpen: (notice) => setState(() {
        final plan = game.plans
            .where((plan) => plan.id == notice.planId)
            .firstOrNull;
        final instanceId = plan?.buildingInstanceId;
        if (instanceId != null) {
          cityId =
              game.developmentCityIds[instanceId] ?? plan!.developmentCityId!;
          planet = GameContent.cities[cityId]!.planet;
          mapBuildingId = game.developmentTechnologyId(instanceId);
          mapBuildingRequest++;
          tab = 1;
        } else if (notice.cityId != null) {
          cityId = notice.cityId!;
          planet = GameContent.cities[cityId]!.planet;
          tab = 1;
        } else if (notice.definition.unique) {
          researchId = notice.taskId;
          tab = 2;
        } else {
          facilityTab = 0;
          tab = 3;
          _focusFacility(notice.definition.facilityId);
        }
      }),
    ),
  );

  Widget _footer() {
    final unread = game.unreadCompletionNotices.toList();
    final message =
        controller.error ??
        controller.commandNotice ??
        (game.completionBannersEnabled && unread.isNotEmpty
            ? unread.last.title
            : '${controller.devTools ? '開発用セーブ  ·  ' : ''}${controller.notice}');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: strategySurface,
        border: Border(top: BorderSide(color: strategyLine)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: message,
              child: Semantics(
                liveRegion:
                    controller.error != null ||
                    controller.commandNotice != null ||
                    (game.completionBannersEnabled && unread.isNotEmpty),
                child: Text(
                  message,
                  key: const Key('status-message'),
                  maxLines: controller.commandNotice == null ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: controller.error == null
                        ? strategyMuted
                        : Colors.orangeAccent,
                  ),
                ),
              ),
            ),
          ),
          if (_firstRunActive)
            ValueListenableBuilder<bool>(
              valueListenable: missionSoundEnabled,
              builder: (context, enabled, _) => IconButton(
                key: const Key('tutorial-sound-toggle'),
                tooltip: enabled ? '音声をオフ' : '音声をオン',
                onPressed: () => missionSoundEnabled.value = !enabled,
                icon: Icon(
                  enabled ? Icons.volume_up : Icons.volume_off,
                  size: 20,
                ),
              ),
            ),
          if (controller.error != null)
            TextButton(
              key: const Key('retry-game-save'),
              onPressed: controller.busy ? null : controller.save,
              child: const Text('再保存'),
            ),
          if (!_firstRunActive)
            TextButton.icon(
              key: const Key('open-guidance'),
              onPressed: _showGuidance,
              icon: const Icon(Icons.help_outline, size: 17),
              label: const Text('ガイド', style: TextStyle(fontSize: 11)),
            ),
          if (!_firstRunActive)
            TextButton.icon(
              key: const Key('open-completions'),
              onPressed: _showCompletions,
              icon: Icon(
                unread.isEmpty
                    ? Icons.notifications_none
                    : Icons.notifications_active_outlined,
                size: 17,
              ),
              label: Text(
                '通知${unread.isEmpty ? '' : ' ${unread.length}'}',
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
