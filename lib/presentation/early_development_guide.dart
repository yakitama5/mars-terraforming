import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/game_state.dart';
import 'strategy_widgets.dart';

class EarlyDevelopmentGuide extends StatelessWidget {
  const EarlyDevelopmentGuide({
    super.key,
    required this.controller,
    required this.compact,
    required this.onResearch,
    required this.onCity,
    required this.onOperations,
    required this.onAgency,
  });
  final GameController controller;
  final bool compact;
  final ValueChanged<String> onResearch, onCity;
  final ValueChanged<int> onOperations;
  final ValueChanged<int> onAgency;
  GameState get game => controller.state;

  PlannedTask? _plan(String id) => game.plans
      .where((plan) => plan.taskId == id && !plan.isFinished)
      .firstOrNull;

  String _taskStatus(String id) {
    final plan = _plan(id);
    if (plan != null) {
      if (_isStopped(plan)) return '停止中 · ${_stopReason(plan)}';
      return plan.status == 'running'
          ? '進行中 · 残り ${gameDuration(plan.remainingMs)}'
          : '予約済み · ${plan.stopReason.isEmpty ? '順番を確認' : plan.stopReason}';
    }
    final task = GameContent.tasks[id]!;
    final missing = (task.cost - game.money).clamp(0, task.cost);
    return '必要 ${dollars(task.cost)} · ${gameDuration(game.currentTaskDurationMs(id))}'
        '${missing > 0 ? '（あと ${dollars(missing)}）' : ' · 資金あり'}';
  }

  bool _isStopped(PlannedTask plan) =>
      plan.status == 'running' &&
      (game.facilities[plan.definition.facilityId] != true ||
          plan.stopReason.isNotEmpty);

  String _stopReason(PlannedTask plan) =>
      plan.stopReason.isNotEmpty ? plan.stopReason : '設備休止中・手動で再開';

  @override
  Widget build(BuildContext context) {
    final shortResearch = [
      for (final id in [
        'process_design',
        'cargo_packaging',
        'habitat_operations',
      ])
        if (!game.research.contains(id) &&
            _plan(id) == null &&
            controller.engine!.researchRequirementReasons(id).isEmpty)
          GameContent.tasks[id]!,
    ];
    final labWork = game.currentPlanFor('lab');
    late String title, detail;
    late VoidCallback open;
    String? focusedTask;
    if (!game.research.contains('life_support')) {
      focusedTask = 'life_support';
      title = '生命維持の実証';
      detail = _taskStatus('life_support');
      open = () => onResearch('life_support');
    } else if (!game.research.contains('urban_planning')) {
      focusedTask = 'urban_planning';
      title = '都市基盤の計画';
      detail = _taskStatus('urban_planning');
      open = () => onResearch('urban_planning');
    } else if (!game.achievements.contains('first_landing')) {
      final preparingDelivery =
          game.earthKits > 0 || _plan('mars_delivery') != null;
      focusedTask = preparingDelivery ? 'mars_delivery' : 'habitat_kit';
      title = preparingDelivery ? '火星への輸送を準備' : '居住キットを製造';
      detail = _taskStatus(preparingDelivery ? 'mars_delivery' : 'habitat_kit');
      open = () => onOperations(preparingDelivery ? 2 : 1);
    } else if (game.habitatChoice == null) {
      title = '火星の居住方式を選ぶ';
      detail = '初輸送は完了 · ドームか地下居住を選べます';
      open = () => onOperations(2);
    } else if (game.marsHabitats == 0) {
      focusedTask = 'district_mars_habitat';
      title = '火星の居住地区を建設';
      final plan = game.plans
          .where(
            (plan) =>
                plan.taskId == 'district_mars_habitat' && !plan.isFinished,
          )
          .firstOrNull;
      detail = plan == null
          ? '到着キット ${game.marsKits}基 · 区画を選び費用と隣接を比較'
          : '${plan.status == 'running' ? '建設中' : '予約済み'} · ${plan.stopReason.isEmpty ? '残り ${gameDuration(plan.remainingMs)}' : plan.stopReason}';
      open = () => onCity('mars_arcadia');
    } else if (labWork != null) {
      focusedTask = labWork.taskId;
      title = '${labWork.definition.name}を進める';
      detail = '進行中 · 残り ${gameDuration(labWork.remainingMs)} · 都市計画は並行できます';
      open = labWork.definition.unique
          ? () => onResearch(labWork.taskId)
          : () => onAgency(0);
    } else if (shortResearch.isNotEmpty) {
      title = '短い応用研究を選ぶ（任意）';
      detail =
          '${shortResearch.first.name}：${_taskStatus(shortResearch.first.id)}';
      open = () => onResearch(shortResearch.first.id);
    } else if (game.specialistCount == GameContent.initialSpecialists) {
      focusedTask = 'train_specialists';
      title = '次の研究に向け人員育成も検討';
      detail = _taskStatus('train_specialists');
      open = () => onAgency(0);
    } else {
      title = '研究と都市の次の投資を選ぶ';
      detail = '地区の実証を重ねて増強・新都市・長期受注へ';
      open = () => onResearch('automated_fabrication');
    }
    final focusedPlan = focusedTask == null ? null : _plan(focusedTask);
    if (focusedPlan != null && _isStopped(focusedPlan)) {
      title = '${focusedPlan.definition.name}の停止を確認・再開';
      detail = '停止中 · ${_stopReason(focusedPlan)}';
      open = () => onOperations(0);
    }
    final hasEarthDistrict = game.districts.values.any(
      (d) => d.cityId == 'earth_delta',
    );
    final cityLabel = hasEarthDistrict
        ? '地区を比較・増強'
        : '住宅 ${dollars(GameContent.districts['housing']!.cost)}';
    final availablePartnerships = game.availablePartnerships.length;
    return StrategyCard(
      selected: true,
      padding: EdgeInsets.all(compact ? 9 : 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '次にできること',
            style: TextStyle(color: strategyMint, fontSize: compact ? 10 : 11),
          ),
          TextButton(
            key: const Key('next-goal'),
            onPressed: open,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
              minimumSize: const Size(0, 28),
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: compact ? 12 : 16,
              ),
            ),
          ),
          Text(
            detail,
            maxLines: compact ? 1 : 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: strategyMuted, fontSize: 11),
          ),
          if (!compact) ...[
            const SizedBox(height: 8),
            const Text(
              '研究中も共用工場で都市を育てられます。受注と建設は同じ工場なので、予約順を選びます。',
              style: TextStyle(color: strategyMuted, fontSize: 12),
            ),
          ],
          if (game.research.contains('urban_planning') &&
              labWork == null &&
              shortResearch.isNotEmpty)
            PopupMenuButton<String>(
              key: const Key('guide-short-research'),
              tooltip: '並行してできる短い研究（任意）',
              onSelected: onResearch,
              itemBuilder: (_) => [
                for (final task in shortResearch)
                  PopupMenuItem(
                    key: Key('guide-research-${task.id}'),
                    value: task.id,
                    child: Text(
                      '${task.name} · ${dollars(task.cost)} · ${gameDuration(game.currentTaskDurationMs(task.id))}',
                    ),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '並行してできる短い研究（任意） ▼',
                  style: TextStyle(fontSize: 11, color: strategyMint),
                ),
              ),
            ),
          if (labWork == null && game.upcomingPlansFor('lab').isNotEmpty)
            TextButton(
              key: const Key('guide-lab-queue'),
              onPressed: () => onOperations(0),
              child: const Text(
                '研究所に予約あり · 設備配分で順番を確認',
                style: TextStyle(fontSize: 11, color: strategyCopper),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  key: const Key('guide-city'),
                  onPressed: () => onCity('earth_delta'),
                  child: Text(
                    cityLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              Expanded(
                child: TextButton(
                  key: Key(
                    availablePartnerships > 0
                        ? 'guide-partnership'
                        : 'guide-contract',
                  ),
                  onPressed: availablePartnerships > 0
                      ? () => onAgency(1)
                      : () => onOperations(1),
                  child: Text(
                    availablePartnerships > 0
                        ? '提携支援 $availablePartnerships件'
                        : '受注で資金を準備',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
