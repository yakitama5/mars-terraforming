import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/game_state.dart';
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
  });
  final GameController controller;
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
  Widget build(BuildContext context) =>
      StrategySplit(overview: _overview(), detail: _detail());

  Widget _overview() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 2),
        child: Row(
          children: [
            Text(
              city.planet == 'earth' ? '地球  /  ' : '火星  /  ',
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
                            fontSize: 16,
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
            const SizedBox(width: 12),
            const Text(
              '区画を選択',
              style: TextStyle(color: strategyMint, fontSize: 12),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 5),
        child: Text(
          '${game.cityDevelopment(city.id).stageName} · 完成 ${game.cityDevelopment(city.id).completedPlots}/${city.plotCount}区画 · 総Lv.${game.cityDevelopment(city.id).totalLevels} · 未予約空地 ${game.cityDevelopment(city.id).availablePlots}',
          key: const Key('city-development-summary'),
          style: const TextStyle(color: strategyMint, fontSize: 11),
        ),
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = math.min(
              94.0,
              math.max(
                43.0,
                math.min(
                  (constraints.maxWidth - 44) / (city.width + .5),
                  (constraints.maxHeight - 12) / (city.height * .78 + .22),
                ),
              ),
            );
            final tileHeight = tileWidth;
            final boardWidth = (city.width + .5) * tileWidth;
            final boardHeight = (city.height * .78 + .22) * tileHeight;
            final neighbors = city.adjacentPlots(selectedPlot);
            return SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: boardWidth,
                  height: boardHeight,
                  child: Stack(
                    children: [
                      for (var index = 0; index < city.plotCount; index++)
                        Positioned(
                          left:
                              (index % city.width +
                                  ((index ~/ city.width).isOdd ? .5 : 0)) *
                              tileWidth,
                          top: (index ~/ city.width) * tileHeight * .78,
                          width: tileWidth - 3,
                          height: tileHeight - 3,
                          child: _plot(
                            index,
                            neighbors.contains(index),
                            tileWidth < 65,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
        child: Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _legend(strategyMint, '選択区画'),
            _legend(strategyCopper, '隣接効果の対象'),
            const Text(
              '上下スクロール · 隣接区画に効果',
              style: TextStyle(color: strategyMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _legend(Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 8, height: 8, color: color),
      const SizedBox(width: 5),
      Text(text, style: const TextStyle(color: strategyMuted, fontSize: 11)),
    ],
  );

  Widget _plot(int index, bool neighbor, bool compact) {
    final district = game.districtAt(city.id, index);
    final plans = game.plans.where(
      (plan) =>
          plan.cityId == city.id && plan.plotIndex == index && !plan.isFinished,
    );
    final planned = plans.isNotEmpty;
    final selected = index == selectedPlot;
    final terrain = city.terrainAt(index);
    final terrainName = GameContent.terrainNames[terrain] ?? terrain;
    final name = district == null
        ? terrainName
        : GameContent.districts[district.districtId]!.name;
    final fill = district != null
        ? const Color(0xff244443)
        : _terrainColor(terrain);
    final stroke = selected
        ? strategyMint
        : neighbor
        ? strategyCopper.withValues(alpha: .7)
        : strategyLine;
    return Semantics(
      label: '${city.name}の区画${index + 1}、$name${planned ? '、建設予約あり' : ''}',
      button: true,
      selected: selected,
      child: GestureDetector(
        key: Key('plot-${city.id}-$index'),
        onTap: () => setState(() {
          selectedDistrict =
              game.districtAt(city.id, selectedPlot)?.districtId ??
              selectedDistrict;
          selectedPlot = index;
        }),
        child: CustomPaint(
          painter: _HexPaint(
            fill: selected ? const Color(0xff31564f) : fill,
            stroke: stroke,
            selected: selected,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 3 : 7,
              vertical: compact ? 4 : 15,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  planned
                      ? Icons.construction
                      : district == null
                      ? _terrainIcon(terrain)
                      : _districtIcon(district.districtId),
                  size: compact ? 14 : 18,
                  color: selected ? strategyMint : strategyMuted,
                ),
                Text(
                  compact
                      ? '${index + 1}'
                      : planned
                      ? plans.first.status == 'running'
                            ? '建設中'
                            : '予約済み'
                      : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 12 : 10,
                    color: selected ? strategyMint : Colors.white,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
                if (district != null && !compact)
                  Text(
                    'Lv.${district.level}',
                    style: const TextStyle(color: strategyMint, fontSize: 10),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail() {
    final existing = game.districtAt(city.id, selectedPlot);
    final districts = available;
    final selected =
        existing?.districtId ??
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
            padding: const EdgeInsets.all(18),
            children: [
              StrategyHeading(
                '区画 ${selectedPlot + 1}  ·  $terrain',
                existing == null
                    ? '建設する地区を選び、立地効果を比較します。'
                    : '完成した地区を強化し、都市の能力を高めます。',
              ),
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
              if (existing == null) ...[
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
              OutlinedButton.icon(
                key: const Key('save-investment'),
                onPressed: maxLevel
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
                        onPressed: maxLevel
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
              if (maxLevel)
                const StrategyCard(
                  child: Text('この地区は最大レベルです。別の区画への展開を検討してください。'),
                )
              else ...[
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
                      StrategyFact('現在の資金', '${game.money} Cr'),
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
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '資金不足 · 予約後、必要な資金が貯まるまで着工を待ちます。',
                    style: TextStyle(fontSize: 12, color: strategyCopper),
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
              if (plan != null) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: plan.progress.clamp(0, 1)),
                const SizedBox(height: 7),
                Text(
                  plan.status == 'running'
                      ? '建設中 · 残り ${gameDuration(plan.remainingMs)}'
                      : '建設予約 · ${plan.stopReason}',
                  style: const TextStyle(color: strategyCopper, fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                '費用は着工時に確保。完成すると地区と隣接効果が都市に反映されます。',
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
                  : '${preview.cost} Cr · ${gameDuration(preview.durationMs)}'),
          child: FilledButton.icon(
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

Color _terrainColor(String terrain) => switch (terrain) {
  'coast' => const Color(0xff193a4b),
  'mineral' => const Color(0xff493d32),
  'ridge' => const Color(0xff353d44),
  'ice' => const Color(0xff324b56),
  'crater' => const Color(0xff45362f),
  _ => const Color(0xff243a37),
};

IconData _terrainIcon(String terrain) => switch (terrain) {
  'coast' => Icons.water_outlined,
  'ice' => Icons.ac_unit,
  'mineral' => Icons.diamond_outlined,
  'ridge' => Icons.landscape_outlined,
  'crater' => Icons.blur_circular,
  _ => Icons.grass_outlined,
};

IconData _districtIcon(String district) => switch (district) {
  'housing' => Icons.home_outlined,
  'campus' || 'mars_lab' => Icons.science_outlined,
  'industry' => Icons.factory_outlined,
  'solar' => Icons.solar_power_outlined,
  'spaceport' => Icons.rocket_launch_outlined,
  'mars_habitat' => Icons.holiday_village_outlined,
  'greenhouse' => Icons.eco_outlined,
  'extractor' => Icons.construction_outlined,
  _ => Icons.location_city_outlined,
};

class _HexPaint extends CustomPainter {
  const _HexPaint({
    required this.fill,
    required this.stroke,
    required this.selected,
  });
  final Color fill;
  final Color stroke;
  final bool selected;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 1)
      ..lineTo(size.width - 1, size.height * .25)
      ..lineTo(size.width - 1, size.height * .75)
      ..lineTo(size.width / 2, size.height - 1)
      ..lineTo(1, size.height * .75)
      ..lineTo(1, size.height * .25)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2 : 1,
    );
  }

  @override
  bool shouldRepaint(covariant _HexPaint oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.stroke != stroke ||
      oldDelegate.selected != selected;
}
