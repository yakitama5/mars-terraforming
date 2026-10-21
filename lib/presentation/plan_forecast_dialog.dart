import 'dart:convert';

import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/plan_forecast.dart';
import 'strategy_widgets.dart';

class PlanForecastDialog extends StatefulWidget {
  const PlanForecastDialog({super.key, required this.controller});
  final GameController controller;

  @override
  State<PlanForecastDialog> createState() => _PlanForecastDialogState();
}

class _PlanForecastDialogState extends State<PlanForecastDialog> {
  Duration horizon = const Duration(hours: 1);
  PlanForecast? result;
  DateTime? calculatedAt;
  String? sourceSnapshot;
  bool stale = false;
  bool unavailable = false;
  PlanForecast get forecast => result!;

  @override
  void initState() {
    super.initState();
    _calculate();
    widget.controller.addListener(_sourceChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sourceChanged);
    super.dispose();
  }

  void _calculate() {
    final state = widget.controller.engine?.state;
    if (state == null) {
      unavailable = true;
      return;
    }
    result = forecastPlans(state, horizon);
    sourceSnapshot = jsonEncode(state.toJson());
    calculatedAt = widget.controller.now();
    stale = false;
  }

  void _sourceChanged() {
    // A save conflict can stop the world while this dialog remains open.
    final state = widget.controller.engine?.state;
    if (state == null) {
      if (!unavailable) setState(() => unavailable = true);
      return;
    }
    // A live notification only invalidates the quote. It must never simulate
    // another horizon or replace the player's explicitly requested result.
    if (!stale && jsonEncode(state.toJson()) != sourceSnapshot) {
      setState(() => stale = true);
    }
  }

  String get _timestamp {
    final at = calculatedAt;
    if (at == null) return '未計算';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.month)}/${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(18),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 940, maxHeight: 760),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 8, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '予約の見通し',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  key: const Key('close-plan-forecast'),
                  tooltip: '見通しを閉じる',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final duration in planForecastHorizons)
                  ChoiceChip(
                    key: Key('forecast-horizon-${duration.inMinutes}'),
                    label: Text('${gameDuration(duration.inMilliseconds)}後'),
                    selected: duration == horizon,
                    showCheckmark: false,
                    onSelected: unavailable
                        ? null
                        : (_) => setState(() {
                            horizon = duration;
                            _calculate();
                          }),
                  ),
                TextButton.icon(
                  key: const Key('refresh-plan-forecast'),
                  onPressed: unavailable ? null : () => setState(_calculate),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('最新状態で再計算'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '見積時点 $_timestamp',
                    key: const Key('forecast-timestamp'),
                    style: const TextStyle(color: strategyMuted, fontSize: 11),
                  ),
                ),
                if (stale && !unavailable)
                  const Flexible(
                    child: Text(
                      '見積後に進行・変更があります',
                      key: Key('forecast-stale'),
                      style: TextStyle(color: strategyCopper, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: strategyLine),
          Flexible(
            child: SingleChildScrollView(
              key: const Key('plan-forecast-scroll'),
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (unavailable || result == null)
                    const Text(
                      '進行が停止したため、試算できません。画面を閉じて保存の状態を確認してください。',
                      key: Key('forecast-unavailable'),
                      style: TextStyle(color: strategyCopper, fontSize: 13),
                    )
                  else ...[
                    _summary(),
                    if (_attentionFacilities.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _attention(),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      '完了する作業 ${forecast.completions.length}件・${forecast.completedRuns}回',
                      key: const Key('forecast-completion-summary'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (forecast.completions.isEmpty)
                      const Text(
                        'この期間に完成する作業はありません。停止理由や残り時間を確認してください。',
                        style: TextStyle(color: strategyMuted, fontSize: 12),
                      ),
                    for (final completion in forecast.completions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Text(
                          '${GameContent.tasks[completion.taskId]!.name} ×${completion.runs}'
                          '${completion.cityId == null ? '' : ' · ${widget.controller.state.cityName(completion.cityId!)} 区画 ${completion.plotIndex! + 1} Lv.${completion.targetLevel}'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    _details(),
                    ExpansionTile(
                      key: const Key('forecast-equipment-details'),
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        '${gameDuration(forecast.horizon.inMilliseconds)}後の設備を詳しく',
                        style: const TextStyle(fontSize: 13),
                      ),
                      children: [
                        for (final facility in forecast.facilities)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _facility(facility),
                          ),
                      ],
                    ),
                    const ExpansionTile(
                      key: Key('forecast-rules'),
                      tilePadding: EdgeInsets.zero,
                      title: Text('見通しの計算について', style: TextStyle(fontSize: 13)),
                      children: [
                        Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            '開始・予約済みの作業だけを試算します。未指定の研究・建設や居住方式は選びません。\n\n'
                            '受注の完了収入は資金見込みに含みます。この画面を開いている間も実際の計画は進行します。',
                            style: TextStyle(
                              color: strategyMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _summary() => StrategyCard(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${gameDuration(forecast.horizon.inMilliseconds)}後の見込み',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: strategyMint,
          ),
        ),
        StrategyFact(
          '資金',
          '${dollars(forecast.money - forecast.moneyDelta)} → ${dollars(forecast.money)}（${signedDollars(forecast.moneyDelta)}）',
          key: const Key('forecast-money'),
        ),
        if (forecast.districtDelta != 0 || forecast.districtLevelDelta != 0)
          StrategyFact(
            '地区の成長',
            '${signedNumber(forecast.districtDelta)}区画 · 総Lv.${signedNumber(forecast.districtLevelDelta)}',
          ),
        if (forecast.marsResidentsDelta != 0)
          StrategyFact(
            '火星に入居',
            '${signedNumber(forecast.marsResidentsDelta)}人',
          ),
        if (forecast.completedResearch.isNotEmpty)
          StrategyFact(
            '研究の完成',
            forecast.completedResearch
                .map((id) => GameContent.tasks[id]!.name)
                .join('・'),
            key: const Key('forecast-research'),
          ),
        if (forecast.newAchievements.isNotEmpty)
          StrategyFact(
            '新しい実績',
            forecast.newAchievements
                .map((id) => GameContent.achievementNames[id] ?? id)
                .join('・'),
          ),
      ],
    ),
  );

  List<ForecastFacility> get _attentionFacilities => forecast.facilities
      .where(
        (facility) =>
            facility.status == ForecastFacilityStatus.waiting ||
            facility.status == ForecastFacilityStatus.paused,
      )
      .toList();

  Widget _attention() => StrategyCard(
    key: const Key('forecast-attention'),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${gameDuration(forecast.horizon.inMilliseconds)}後に条件待ち・休止の設備',
          style: const TextStyle(
            color: strategyCopper,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        for (final facility in _attentionFacilities)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${GameContent.facilities[facility.facilityId]!.name} · ${facility.stopReason}',
              key: Key('forecast-attention-${facility.facilityId}'),
              style: const TextStyle(color: strategyCopper, fontSize: 12),
            ),
          ),
      ],
    ),
  );

  Widget _details() => ExpansionTile(
    key: const Key('forecast-resource-details'),
    tilePadding: EdgeInsets.zero,
    title: const Text('収支・人口・在庫の内訳', style: TextStyle(fontSize: 13)),
    children: [
      StrategyFact('定常収支', '${signedDollars(forecast.netPerMinute)}/分（税収−維持費）'),
      StrategyFact(
        '完成地区',
        '${forecast.districtCount}区画（${signedNumber(forecast.districtDelta)}） · 総Lv.${forecast.totalDistrictLevels}（${signedNumber(forecast.districtLevelDelta)}）',
      ),
      StrategyFact(
        '地球人口',
        '${forecast.population}人（${signedNumber(forecast.populationDelta)}）',
      ),
      StrategyFact(
        '火星居住者',
        '${forecast.marsResidents}人（${signedNumber(forecast.marsResidentsDelta)}）',
      ),
      StrategyFact(
        'キット在庫',
        '地球 ${forecast.earthKits}基 · 月 ${forecast.moonKits}基 · 火星 ${forecast.marsKits}基',
      ),
    ],
  );

  Widget _facility(ForecastFacility facility) {
    final status = switch (facility.status) {
      ForecastFacilityStatus.running => '進行中',
      ForecastFacilityStatus.waiting => '条件待ち',
      ForecastFacilityStatus.paused => '休止中',
      ForecastFacilityStatus.idle => '待機中',
    };
    final attention =
        facility.status == ForecastFacilityStatus.waiting ||
        facility.status == ForecastFacilityStatus.paused;
    return StrategyCard(
      key: Key('forecast-facility-${facility.facilityId}'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${GameContent.facilities[facility.facilityId]!.name} · $status',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: attention ? strategyCopper : strategyMint,
            ),
          ),
          const SizedBox(height: 5),
          if (facility.taskId != null)
            Text(
              GameContent.tasks[facility.taskId]!.name,
              style: const TextStyle(fontSize: 12),
            ),
          Text(
            facility.status == ForecastFacilityStatus.running
                ? 'その時点から残り ${gameDuration(facility.remainingMs)}'
                : facility.stopReason,
            style: TextStyle(
              color: attention ? strategyCopper : strategyMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '期間中の完了 ${facility.completedRuns}回 · 今後の予約 ${facility.queuedPlans}件（反復含む）',
            style: const TextStyle(color: strategyMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
