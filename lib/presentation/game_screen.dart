import 'dart:async';

import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/game_state.dart';
import '../rendering/base_scene.dart';
import 'city_development.dart';
import 'facility_queue_card.dart';
import 'investment_comparison.dart';
import 'plan_forecast_dialog.dart';
import 'research_tree.dart';
import 'strategy_widgets.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.controller, this.sceneBuilder});
  final GameController controller;
  final Widget Function(bool, int, int, bool)? sceneBuilder;
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  bool earth = true;
  int tab = 0;
  int facilityTab = 0;
  String cityId = 'earth_delta';
  String researchId = 'life_support';
  InvestmentCandidate? savedInvestment;
  GameController get controller => widget.controller;
  GameState get game => controller.state;
  bool get _compactLandscape => MediaQuery.sizeOf(context).height < 450;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _header(),
              _navigation(),
              Expanded(
                child: switch (tab) {
                  0 => StrategySplit(
                    overview: _world(),
                    detail: _planetDetails(),
                  ),
                  1 => CityDevelopment(
                    controller: controller,
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
                      onSelected: (id) => setState(() => researchId = id),
                      requirementReasons:
                          controller.engine!.researchRequirementReasons,
                    ),
                    detail: _researchDetails(),
                  ),
                  _ => _facilities(),
                },
              ),
              _footer(),
            ],
          ),
        ),
      );
    },
  );

  Widget _header() => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1050;
      return Container(
        padding: EdgeInsets.symmetric(horizontal: wide ? 22 : 16, vertical: 9),
        decoration: const BoxDecoration(
          color: Color(0xff10202a),
          border: Border(bottom: BorderSide(color: strategyLine)),
        ),
        child: Row(
          children: [
            const Icon(Icons.public, color: strategyCopper, size: 25),
            const SizedBox(width: 10),
            Text(
              '火星開発計画',
              style: TextStyle(
                fontSize: wide ? 19 : 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 24),
            Text(
              '${game.money} Cr',
              key: const Key('money'),
              semanticsLabel: '資金 ${game.money} クレジット',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: strategyMint,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                wide
                    ? '税収 +${game.taxPerMinute}  −  維持費 ${game.upkeepPerMinute}  =  ${signedNumber(game.netPerMinute)} Cr/分'
                    : '収支 ${signedNumber(game.netPerMinute)} Cr/分',
                style: TextStyle(
                  color: game.netPerMinute < 0 ? strategyCopper : strategyMuted,
                  fontSize: 12,
                ),
              ),
            ),
            if (controller.devTools) ...[
              TextButton.icon(
                key: const Key('advance-time'),
                onPressed: controller.busy
                    ? null
                    : () => controller.advanceForDevelopment(),
                icon: const Icon(Icons.fast_forward, size: 16),
                label: const Text('開発 +5分', style: TextStyle(fontSize: 11)),
              ),
              PopupMenuButton<Duration>(
                key: const Key('development-time-menu'),
                tooltip: '開発用の時間送り',
                icon: const Icon(Icons.more_time, size: 20),
                onSelected: (duration) =>
                    controller.advanceForDevelopment(duration: duration),
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
            ] else if (wide)
              const Text(
                '端末内で自動保存',
                style: TextStyle(color: strategyMuted, fontSize: 11),
              ),
          ],
        ),
      );
    },
  );

  Widget _navigation() => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: strategyLine)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    child: Row(
      children: [
        for (final (index, entry) in [
          (Icons.public, '惑星マップ'),
          (Icons.location_city_outlined, '都市開発'),
          (Icons.account_tree_outlined, '研究ツリー'),
          (Icons.view_timeline_outlined, '設備・進行'),
        ].indexed)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: TextButton.icon(
                key: Key('navigation-$index'),
                onPressed: () => setState(() => tab = index),
                style: TextButton.styleFrom(
                  foregroundColor: tab == index ? strategyMint : strategyMuted,
                  backgroundColor: tab == index
                      ? const Color(0xff20383d)
                      : Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                icon: Icon(entry.$1, size: 18),
                label: Text(
                  entry.$2,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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

  Widget _world() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 9, 18, 0),
        child: Row(
          children: [
            for (final item in [('地球', true), ('火星', false)])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(item.$1),
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
            const Spacer(),
            const Text(
              '全球 → 都市 → 区画',
              style: TextStyle(fontSize: 11, color: strategyMuted),
            ),
          ],
        ),
      ),
      Expanded(
        child: Stack(
          children: [
            Positioned.fill(
              child:
                  widget.sceneBuilder?.call(
                    earth,
                    game.earthLevel,
                    game.marsHabitats,
                    game.marsKits > 0,
                  ) ??
                  BaseScene(
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
                          name: city.name,
                          latitude: city.latitude,
                          longitude: city.longitude,
                          development: _cityDevelopment(city),
                          isActive: game.cityUnlocked(city.id),
                        ),
                    ],
                    selectedCityId: cityId,
                    onCitySelected: _selectCity,
                  ),
            ),
            Positioned(
              left: 20,
              top: 12,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      earth ? '地球' : '火星',
                      style: TextStyle(
                        fontSize: _compactLandscape ? 18 : 27,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 4,
                      ),
                    ),
                    if (!_compactLandscape)
                      Text(
                        earth ? '産業と研究を育てる母星' : '閉鎖居住から、新しい都市へ',
                        style: const TextStyle(
                          fontSize: 12,
                          color: strategyMuted,
                        ),
                      ),
                  ],
                ),
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
                          ? '人口 ${game.population} 人'
                          : '居住者 ${game.marsResidents} 人',
                    ),
                    _tag(
                      earth
                          ? '輸送待ちキット ${game.earthKits}'
                          : '到着キット ${game.marsKits}',
                    ),
                    _tag(
                      earth
                          ? '税収 ${game.taxPerMinute} Cr/分'
                          : '居住施設 ${game.marsHabitats}',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _tag(String text) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xe9142630),
      border: Border.all(color: strategyLine),
      borderRadius: BorderRadius.circular(6),
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
        _nextGoal(),
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
          const StrategyHeading('都市を選ぶ', '惑星の都市を選んでから、地区の配置を計画します。'),
        for (final candidate in cities)
          Padding(
            padding: EdgeInsets.only(bottom: _compactLandscape ? 4 : 8),
            child: Material(
              color: candidate.id == cityId
                  ? const Color(0xff223d40)
                  : strategyPanel,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: candidate.id == cityId ? strategyMint : strategyLine,
                ),
              ),
              child: ListTile(
                key: Key('select-city-${candidate.id}'),
                dense: true,
                minTileHeight: _compactLandscape ? 44 : null,
                onTap: () => _selectCity(candidate.id),
                leading: Icon(
                  game.cityUnlocked(candidate.id)
                      ? Icons.location_city
                      : Icons.lock_outline,
                  color: game.cityUnlocked(candidate.id)
                      ? strategyMint
                      : strategyMuted,
                ),
                title: Text(
                  candidate.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: _compactLandscape
                    ? null
                    : Text(
                        game.cityUnlocked(candidate.id)
                            ? '${game.cityDevelopment(candidate.id).stageName} · 完成 ${game.cityDevelopment(candidate.id).completedPlots}/${candidate.plotCount} · 総Lv.${game.cityDevelopment(candidate.id).totalLevels}'
                            : game.cityLockReason(candidate.id) ?? '研究が必要',
                        style: const TextStyle(
                          fontSize: 11,
                          color: strategyMuted,
                        ),
                      ),
                trailing: const Icon(Icons.chevron_right, size: 18),
              ),
            ),
          ),
        const SizedBox(height: 14),
        Text(
          city.name,
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

  Widget _nextGoal() {
    final (
      title,
      description,
      destination,
    ) = !game.research.contains('life_support')
        ? ('生命維持を実証する', '最初の研究で居住キットの製造を解放。', 2)
        : !game.achievements.contains('first_landing')
        ? ('火星へ最初の設備を届ける', '工場で製造し、宇宙港から輸送します。', 3)
        : game.habitatChoice == null
        ? ('火星の居住方式を選ぶ', 'ドームか地下居住か。建設前の方針を決めます。', 3)
        : game.marsHabitats == 0
        ? ('最初の居住区を配置する', '火星の都市で区画を選び、居住先を建設します。', 1)
        : ('都市の能力を高める', '地形と隣接を活かし、次の研究と開発を支えます。', 1);
    void openPlan() => setState(() {
      tab = destination;
      if (destination == 3) facilityTab = 2;
      if (destination == 1 && game.marsHabitats == 0) {
        cityId = 'mars_arcadia';
        earth = false;
      }
    });
    if (_compactLandscape) {
      return TextButton(
        key: const Key('next-goal'),
        onPressed: openPlan,
        style: TextButton.styleFrom(
          foregroundColor: strategyMint,
          backgroundColor: const Color(0xff203d40),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('次の目標', style: TextStyle(fontSize: 10)),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, size: 18),
          ],
        ),
      );
    }
    return StrategyCard(
      selected: true,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '次の目標',
            style: TextStyle(
              color: strategyMint,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            description,
            style: const TextStyle(fontSize: 12, color: strategyMuted),
          ),
          const SizedBox(height: 4),
          TextButton(
            key: const Key('next-goal'),
            onPressed: openPlan,
            child: const Text('計画を確認する →'),
          ),
        ],
      ),
    );
  }

  Widget _researchDetails() {
    final task = GameContent.tasks[researchId]!;
    final requirements = controller.engine!.researchRequirements(task.id);
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
            padding: const EdgeInsets.all(18),
            children: [
              Text(
                '${task.researchBranch} / $status',
                style: const TextStyle(fontSize: 12, color: strategyMint),
              ),
              const SizedBox(height: 8),
              Text(
                task.name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                task.description,
                style: const TextStyle(fontSize: 13, color: strategyMuted),
              ),
              const SizedBox(height: 16),
              StrategyCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StrategyFact('研究費', '${task.cost} Cr'),
                    StrategyFact(
                      '研究期間',
                      gameDuration(game.currentTaskDurationMs(task.id)),
                    ),
                    StrategyFact(
                      '使用設備',
                      GameContent.facilities[task.facilityId]!.name,
                    ),
                    StrategyFact(
                      '研究効率',
                      '+${game.researchBonusPercent}% / 上限 ${game.facilityBonusCap('lab')}%',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '必要な研究・実証条件',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (requirements.isEmpty)
                const Text(
                  'なし · この研究から始められます',
                  style: TextStyle(fontSize: 12, color: strategyMint),
                ),
              for (final requirement in requirements)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
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
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${requirement.label}  ${requirement.current}/${requirement.required}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                '完成するとできること',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 7),
              Text(
                task.unlockSummary,
                style: const TextStyle(fontSize: 13, color: strategyMint),
              ),
              const SizedBox(height: 18),
              if (task.science.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _science(task),
                  icon: const Icon(Icons.menu_book_outlined, size: 17),
                  label: const Text('科学メモ・出典'),
                ),
            ],
          ),
        ),
        StrategyActionBar(
          message: status == '未解放'
              ? controller.engine!
                    .researchRequirementReasons(task.id)
                    .join(' / ')
              : null,
          child: FilledButton.icon(
            key: Key('queue-${task.id}'),
            onPressed:
                status == '研究済み' ||
                    status == '研究中' ||
                    status == '予約済み' ||
                    controller.busy
                ? null
                : () => _reserve(task.id),
            icon: const Icon(Icons.science_outlined, size: 18),
            label: Text(
              status == '研究済み' || status == '研究中' || status == '予約済み'
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
                        ? const Color(0xff223a3c)
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
              _taskCard('precision_contract'),
              _taskCard('batch_habitat_kit'),
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
              _taskCard('orbital_contract'),
              _taskCard('cargo_delivery'),
            ],
            _ => _journal(),
          },
        ),
      ),
    ],
  );

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

  List<Widget> _queueOverview() => [
    const StrategyHeading(
      '共用設備の稼働計画',
      '↑↓で予約順を変更。設備を休止すると、対応する地区の効果と維持費も停止します。',
    ),
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
    const Text(
      '順番を変えても支払済みの1回は続行します。先頭の予約が条件待ちの場合、その設備の後続も待機します。',
      style: TextStyle(color: strategyMuted, fontSize: 12),
    ),
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
              task.description,
              style: const TextStyle(color: strategyMuted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 22,
              runSpacing: 10,
              children: [
                StrategyStat('開始費用', '${task.cost} Cr'),
                StrategyStat(
                  '1回の所要時間',
                  gameDuration(game.currentTaskDurationMs(id)),
                ),
                if (task.reward > 0)
                  StrategyStat(
                    '完成時の受取',
                    '${task.reward} Cr',
                    color: strategyCopper,
                  ),
                if (task.outputResource != null)
                  StrategyStat('完成時の成果', '${task.outputAmount}基'),
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
          title: const Text('反復回数'),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                '${task.name}\n1回 ${task.cost} Cr · ${gameDuration(game.currentTaskDurationMs(id))}',
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
                '資金・資材不足では待機します。無期限の受注は設備を使い続けるため、設備・進行から終了できます。',
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
                    : () => controller.command(
                        (engine) => engine.chooseHabitat('dome'),
                      ),
                child: const Text('ドーム居住'),
              ),
              TextButton(
                key: const Key('choose-underground'),
                onPressed:
                    !game.achievements.contains('first_landing') ||
                        controller.busy
                    ? null
                    : () => controller.command(
                        (engine) => engine.chooseHabitat('underground'),
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
        child: Text('· $entry', style: const TextStyle(fontSize: 13)),
      ),
  ];

  Widget _footer() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
    decoration: const BoxDecoration(
      color: Color(0xff10202a),
      border: Border(top: BorderSide(color: strategyLine)),
    ),
    child: Text(
      controller.error ??
          '${controller.devTools ? '開発用セーブ  ·  ' : ''}${controller.notice}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        color: controller.error == null ? strategyMuted : Colors.orangeAccent,
      ),
    ),
  );

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
