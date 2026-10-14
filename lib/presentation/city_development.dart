import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/game_state.dart';
import '../rendering/city_scene.dart';
import 'city_scene_data.dart';
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
          game.districtAt(oldWidget.cityId, selectedPlot)?.districtId ??
          selectedDistrict ??
          widget.savedInvestment?.districtId;
      selectedPlot = 12;
      selectedDistrict = available.any((item) => item.id == previousDistrict)
          ? previousDistrict
          : null;
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
            width: constraints.maxWidth > 1100 ? 350 : 296,
            child: _detail(),
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
            selectedPlot: selectedPlot,
            adjacentPlots: city.adjacentPlots(selectedPlot).toSet(),
            renderScene: widget.renderScene,
            onPlotSelected: (index) => setState(() {
              selectedDistrict =
                  game.districtAt(city.id, selectedPlot)?.districtId ??
                  selectedDistrict;
              selectedPlot = index;
              showInspector = true;
            }),
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
                  key: const Key('district-work-status'),
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
                TextButton.icon(
                  onPressed: () => widget.onOpenResearch(
                    city.requiredResearch ?? 'life_support',
                  ),
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('必要な研究を見る'),
                ),
                const SizedBox(height: 12),
              ],
              if (existing == null && reserved == null) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final item in districts)
                      ChoiceChip(
                        key: Key('district-option-${item.id}'),
                        label: Text(
                          item.name,
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: selected == item.id,
                        showCheckmark: false,
                        onSelected: (_) =>
                            setState(() => selectedDistrict = item.id),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
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
                    : () => widget.onSaveInvestment(candidate),
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
                            : () => showDialog<void>(
                                context: context,
                                builder: (context) => ListenableBuilder(
                                  listenable: widget.controller,
                                  builder: (context, _) => InvestmentComparison(
                                    game: widget.controller.state,
                                    saved: saved,
                                    current: candidate,
                                  ),
                                ),
                              ),
                        icon: const Icon(Icons.compare_arrows, size: 18),
                        label: const Text('候補を比較'),
                      ),
                      TextButton(
                        key: const Key('clear-investment'),
                        onPressed: () => widget.onSaveInvestment(null),
                        child: const Text('比較候補を解除'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (definition.requiredResearch != null)
                StrategyFact(
                  '必要研究',
                  GameContent.tasks[definition.requiredResearch]!.name,
                ),
              if (definition.requiredResearch != null &&
                  !game.research.contains(definition.requiredResearch))
                TextButton.icon(
                  onPressed: () =>
                      widget.onOpenResearch(definition.requiredResearch!),
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
                    key: const Key('district-blocked-reason'),
                    style: const TextStyle(color: strategyCopper, fontSize: 12),
                  ),
                ),
              if (preview.isValid && game.money < preview.cost)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '資金不足 · 予約後、必要な資金が貯まるまで着工を待ちます。'
                    '${city.planet == 'earth' ? ' 先頭の建設が資金待ちだと、後ろの受注も停止します。受注を先にして資金を準備できます。' : ''}',
                    key: const Key('district-funding-warning'),
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
        StrategyActionBar(
          message:
              preview.blockedReason ??
              (game.money < preview.cost
                  ? '資金が貯まるまで着工を待機します'
                  : city.planet == 'mars' && game.marsKits == 0
                  ? '到着キットが揃うまで着工を待機します'
                  : '${dollars(preview.cost)} · ${gameDuration(preview.durationMs)}'),
          child: plan != null && widget.onOpenOperations != null
              ? OutlinedButton.icon(
                  key: const Key('district-open-operations'),
                  onPressed: widget.onOpenOperations,
                  icon: const Icon(Icons.view_timeline_outlined, size: 18),
                  label: const Text('設備・進行で確認'),
                )
              : FilledButton.icon(
                  key: const Key('confirm-district'),
                  onPressed: !preview.isValid || widget.controller.busy
                      ? null
                      : () => widget.controller.command(
                          (engine) => existing == null
                              ? engine.enqueueDistrict(
                                  city.id,
                                  selectedPlot,
                                  selected,
                                )
                              : engine.upgradeDistrict(city.id, selectedPlot),
                        ),
                  icon: const Icon(Icons.construction, size: 18),
                  label: Text(existing == null ? 'この区画に建設を予約' : 'この地区を強化する'),
                ),
        ),
      ],
    );
  }
}
