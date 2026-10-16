import 'dart:async';

import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/contextual_tips.dart';
import '../domain/game_state.dart';
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
import 'resource_overview_dialog.dart';
import 'strategy_widgets.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.controller,
    this.sceneBuilder,
    this.renderScene = true,
    this.showIntroduction = true,
  });
  final GameController controller;
  final bool renderScene;
  final bool showIntroduction;
  final Widget Function(bool, int, int, bool)? sceneBuilder;
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  bool earth = true;
  int tab = 0;
  int facilityTab = 0;
  int agencySection = 0;
  String cityId = 'earth_delta';
  String researchId = 'life_support';
  final researchScroll = ScrollController(keepScrollOffset: false);
  InvestmentCandidate? savedInvestment;
  final facilityKeys = {
    for (final id in GameContent.facilities.keys) id: GlobalKey(),
  };
  GameController get controller => widget.controller;
  GameState get game => controller.state;
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
                            earth = true;
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
                          controller: controller,
                          renderScene:
                              widget.renderScene && widget.sceneBuilder == null,
                          onOpenGlobe: () => setState(() => tab = 0),
                          onOpenOperations: () => setState(() {
                            facilityTab = 0;
                            tab = 3;
                          }),
                          cityId: cityId,
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
                            selectedId: researchId,
                            onSelected: _selectResearch,
                            requirementReasons:
                                controller.engine!.researchRequirementReasons,
                          ),
                          detail: _researchDetails(),
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
                    onPressed: () => setState(() => tab = index),
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
    cityId = id;
    earth = GameContent.cities[id]!.planet == 'earth';
  });

  int _cityDevelopment(CityDefinition city) {
    final placed = game.districts.values
        .where((district) => district.cityId == city.id)
        .fold(0, (sum, district) => sum + district.level);
    if (city.id == 'earth_delta') return placed + game.earthLevel;
    if (city.id == 'mars_arcadia') {
      final locatedHabitats = game.districts.values
          .where((district) => district.districtId == 'mars_habitat')
          .length;
      return placed +
          (game.marsHabitats - locatedHabitats).clamp(0, game.marsHabitats);
    }
    return placed;
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
                    earthLevel: game.earthLevel,
                    marsHabitats: game.marsHabitats,
                    hasCargo: game.marsKits > 0,
                    cities: [
                      for (final city in GameContent.cities.values.where(
                        (city) => city.planet == (earth ? 'earth' : 'mars'),
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
                      earth ? '地球圏' : '火星圏',
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
            for (final item in [('地球', true), ('火星', false)])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 66,
                    minHeight: 44,
                  ),
                  child: ChoiceChip(
                    label: SizedBox(
                      width: 32,
                      child: Text(
                        item.$1,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                      ),
                    ),
                    selected: earth == item.$2,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      earth = item.$2;
                      cityId = GameContent.cities.values
                          .firstWhere(
                            (city) => city.planet == (earth ? 'earth' : 'mars'),
                          )
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
                earth
                    ? '人口 ${formatInteger(game.population)} 人'
                    : '居住者 ${formatInteger(game.marsResidents)} 人',
              ),
              _tag(
                earth ? '輸送待ちキット ${game.earthKits}' : '到着キット ${game.marsKits}',
              ),
              _tag(
                earth
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
      (candidate) => candidate.planet == (earth ? 'earth' : 'mars'),
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
        if (!earth)
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
      earth = GameContent.cities[id]!.planet == 'earth';
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
    setState(() => researchId = id);
    if (researchScroll.hasClients) researchScroll.jumpTo(0);
  }

  Widget _researchDetails() {
    final task = GameContent.tasks[researchId]!;
    final requirements = controller.engine!.researchRequirements(task.id);
    final activePlan = game.plans
        .where((plan) => plan.taskId == task.id && !plan.isFinished)
        .firstOrNull;
    final status = researchStatus(
      game,
      task,
      controller.engine!.researchRequirementReasons(task.id),
    );
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const Key('research-detail'),
            controller: researchScroll,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${task.researchBranch} / $status',
                style: const TextStyle(fontSize: 12, color: strategyMint),
              ),
              const SizedBox(height: 6),
              Text(
                task.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              StrategyCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '完成すると',
                      style: TextStyle(fontSize: 11, color: strategyMuted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      researchUnlockSummary(game, task),
                      key: const Key('research-unlocks'),
                      style: const TextStyle(fontSize: 14, color: strategyMint),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              StrategyFact(
                activePlan?.status == 'running' ? '支払済み' : '研究費',
                dollars(task.cost),
              ),
              StrategyFact(
                activePlan?.status == 'running' ? '残り時間' : '研究期間',
                gameDuration(
                  activePlan?.status == 'running'
                      ? activePlan!.remainingMs
                      : game.currentTaskDurationMs(task.id),
                ),
              ),
              if (requirements.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  '開始に必要な条件',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                for (final requirement in requirements)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(
                          requirement.isMet
                              ? Icons.check_circle_outline
                              : Icons.lock_outline,
                          size: 16,
                          color: requirement.isMet
                              ? strategyMint
                              : strategyCopper,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${requirement.label}  ${requirement.current}/${requirement.required}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final id in task.prerequisiteIds.where(
                  (id) => !game.research.contains(id),
                ))
                  TextButton.icon(
                    key: Key('research-prerequisite-$id'),
                    onPressed: () => _selectResearch(id),
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: Text('${GameContent.tasks[id]!.name}を見る'),
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
              TextButton.icon(
                key: const Key('research-parallel-city'),
                onPressed: () => setState(() {
                  cityId = 'earth_delta';
                  earth = true;
                  tab = 1;
                }),
                icon: const Icon(Icons.location_city_outlined, size: 17),
                label: const Text('待ち時間に都市を開発'),
              ),
              ExpansionTile(
                key: ValueKey('research-explanation-${task.id}'),
                tilePadding: EdgeInsets.zero,
                title: const Text('研究の詳細・科学メモ', style: TextStyle(fontSize: 12)),
                children: [
                  Text(
                    task.description,
                    style: const TextStyle(fontSize: 13, color: strategyMuted),
                  ),
                  const SizedBox(height: 10),
                  StrategyFact(
                    '使用設備',
                    GameContent.facilities[task.facilityId]!.name,
                  ),
                  StrategyFact(
                    '研究効率',
                    '${signedNumber(game.researchBonusPercent)}% / 上限 ${game.facilityBonusCap('lab')}%',
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
                  if (task.science.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _science(task),
                      icon: const Icon(Icons.menu_book_outlined, size: 17),
                      label: const Text('科学メモ・出典'),
                    ),
                ],
              ),
            ],
          ),
        ),
        StrategyActionBar(
          message: status == '未解放' ? '予約できます。条件が揃うと開始します。' : null,
          child: FilledButton.icon(
            key: Key('queue-${task.id}'),
            onPressed: status == '研究済み' || activePlan != null || controller.busy
                ? null
                : () => _reserve(task.id),
            icon: const Icon(Icons.science_outlined, size: 18),
            label: Text(
              activePlan != null
                  ? status
                  : status == '研究済み'
                  ? status
                  : '研究を予約する',
              semanticsLabel: '${task.name}を予約',
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
                '受注で運転資金を得ながら、火星向けの製造に共用工場を配分します。',
              ),
              _taskCard('factory_contract'),
              _taskCard('habitat_kit'),
              ..._advancedTasks(['precision_contract', 'batch_habitat_kit']),
              _cityShortcut('地球の住宅や産業を増やす', 'earth_delta'),
            ],
            2 => [
              const StrategyHeading(
                '地球から火星へ',
                '設備を輸送し、火星の都市に居住区を配置します。住民は建設完成時に入居します。',
              ),
              _taskCard('mars_delivery'),
              if (game.habitatChoice == null) _branch(),
              _cityShortcut('火星の居住区を配置する', 'mars_arcadia'),
              _taskCard('launch_contract'),
              ..._advancedTasks(['orbital_contract', 'cargo_delivery']),
            ],
            _ => _journal(),
          },
        ),
      ),
    ],
  );

  List<Widget> _advancedTasks(List<String> ids) {
    final available = ids
        .where(
          (id) => GameContent.tasks[id]!.prerequisiteIds.every(
            game.research.contains,
          ),
        )
        .toList();
    final locked = ids.where((id) => !available.contains(id)).toList();
    return [
      for (final id in available) _taskCard(id),
      if (locked.isNotEmpty)
        ExpansionTile(
          key: ValueKey('future-tasks-$facilityTab'),
          title: Text(
            '研究で広がる計画（${locked.length}）',
            style: const TextStyle(fontSize: 13),
          ),
          children: [for (final id in locked) _taskCard(id)],
        ),
    ];
  }

  Widget _cityShortcut(String label, String id) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: OutlinedButton.icon(
      onPressed: () => setState(() {
        cityId = id;
        earth = GameContent.cities[id]!.planet == 'earth';
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
            for (final id in GameContent.facilities.keys)
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
                StrategyStat('開始費用', dollars(task.cost)),
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
            const SizedBox(height: 8),
            Row(
              children: [
                if (task.science.isNotEmpty)
                  TextButton(
                    onPressed: () => _science(task),
                    child: const Text('科学メモ'),
                  ),
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
    if (!task.unique) {
      final result = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('実行回数を選ぶ'),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                '${task.name}\n1回 ${dollars(task.cost)} · ${gameDuration(game.currentTaskDurationMs(id))}',
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
          earth = GameContent.cities[cityId]!.planet == 'earth';
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
        if (notice.cityId != null) {
          cityId = notice.cityId!;
          earth = GameContent.cities[cityId]!.planet == 'earth';
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

  void _science(TaskDefinition task) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${task.name} / 科学メモ'),
      content: SingleChildScrollView(child: SelectableText(task.science)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('閉じる'),
        ),
      ],
    ),
  );
}
