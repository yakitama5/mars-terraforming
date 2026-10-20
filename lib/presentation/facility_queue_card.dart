import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/game_state.dart';
import 'strategy_widgets.dart';

const _mint = strategyBlue;
const _muted = strategyMuted;
const _copper = strategyWarning;

/// The current paid iteration is displayed separately from future starts.
class FacilityQueueCard extends StatelessWidget {
  const FacilityQueueCard({
    super.key,
    required this.controller,
    required this.facilityId,
  });

  final GameController controller;
  final String facilityId;

  @override
  Widget build(BuildContext context) {
    final game = controller.state;
    final facility = GameContent.facilities[facilityId]!;
    final enabled = game.facilities[facilityId]!;
    final current = game.currentPlanFor(facilityId);
    final upcoming = game.upcomingPlansFor(facilityId);
    final status = !enabled
        ? '休止中'
        : current != null
        ? current.stopReason.isEmpty
              ? '稼働中'
              : '条件待ち'
        : facilityId == 'lab' && game.researchPointsPerMinute > 0
        ? 'RPを生産中'
        : upcoming.isNotEmpty
        ? '条件待ち'
        : '待機中';
    return Container(
      key: Key('facility-$facilityId'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: strategyPanel,
        border: Border.all(color: strategyLine),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      facility.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '$status · 基本維持費 ${dollars(enabled ? facility.upkeepPerMinute : 0)}/分',
                      style: TextStyle(
                        color: enabled ? _mint : _copper,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                enabled ? '稼働' : '休止',
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
              Semantics(
                label: '${facility.name}の稼働',
                child: Switch(
                  key: Key('facility-toggle-$facilityId'),
                  value: enabled,
                  onChanged: controller.busy
                      ? null
                      : (value) => controller.command(
                          (engine) =>
                              engine.setFacilityEnabled(facilityId, value),
                        ),
                ),
              ),
            ],
          ),
          if (facilityId == 'lab')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '共通RP ${game.researchPoints.toStringAsFixed(1)} RP · 全施設で ${game.researchPointsPerMinute.toStringAsFixed(1)} RP/分',
                key: const Key('lab-common-research-points'),
                style: const TextStyle(color: _mint, fontSize: 11),
              ),
            ),
          const Divider(color: strategyLine),
          if (current != null)
            _current(current, enabled)
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                !enabled
                    ? '設備休止中・スイッチで再開できます'
                    : upcoming.isEmpty
                    ? '予約なし・次の計画を待っています'
                    : '開始待ち · ${upcoming.first.stopReason}',
                style: TextStyle(
                  color: upcoming.isEmpty && enabled ? _muted : _copper,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            '次の予約 ${upcoming.length}件',
            style: const TextStyle(fontSize: 11, color: _muted),
          ),
          if (upcoming.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '次の予約はありません',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ),
          for (final (index, plan) in upcoming.indexed)
            _queued(context, plan, index, upcoming),
        ],
      ),
    );
  }

  Widget _current(PlannedTask plan, bool enabled) {
    final advancing = enabled && plan.stopReason.isEmpty;
    final status = !enabled
        ? '一時停止'
        : advancing
        ? '進行中'
        : '条件待ち';
    return Container(
      key: Key('current-${plan.id}'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: strategySelected,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$status · ${_purpose(plan)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: advancing ? _mint : _copper,
                  ),
                ),
              ),
              Text(
                '${(plan.progress * 100).floor()}%',
                style: const TextStyle(fontSize: 11, color: _mint),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(plan.definition.name, style: const TextStyle(fontSize: 13)),
          if (plan.stopReason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                plan.stopReason,
                key: Key('current-stop-reason-${plan.id}'),
                style: const TextStyle(fontSize: 12, color: _copper),
              ),
            ),
          if (plan.cityId != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _location(plan, controller.state),
                style: const TextStyle(fontSize: 12, color: _mint),
              ),
            ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: plan.progress.clamp(0, 1),
            semanticsLabel: '${plan.definition.name}の進捗',
            minHeight: 4,
            backgroundColor: strategyLine,
          ),
          const SizedBox(height: 6),
          Text(
            '${advancing ? '残り' : '再開後の残り'} ${gameDuration(plan.remainingMs)} · 支払済み${plan.definition.unique ? '・追加RP不要' : ''}',
            style: TextStyle(color: advancing ? _mint : _copper, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _queued(
    BuildContext context,
    PlannedTask plan,
    int index,
    List<PlannedTask> upcoming,
  ) {
    final unlimitedBefore = upcoming
        .take(index)
        .where((previous) => previous.remainingRepeats == null)
        .firstOrNull;
    final repeat = plan.remainingRepeats;
    final futureCount = repeat == null
        ? '無期限'
        : '${repeat - (plan.status == 'running' ? 1 : 0)}回';
    return Container(
      key: Key('upcoming-${plan.id}'),
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.fromLTRB(9, 7, 0, 7),
      decoration: BoxDecoration(
        border: Border.all(color: strategyLine),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${index == 0 ? '次の作業' : '${index + 1}番目'} · ${_purpose(plan)}${plan.definition.unique ? '' : ' · $futureCount'}',
                      style: TextStyle(
                        fontSize: 10,
                        color: plan.taskId.endsWith('_contract')
                            ? _copper
                            : _mint,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      plan.definition.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (plan.cityId != null)
                      Text(
                        _location(plan, controller.state),
                        style: const TextStyle(fontSize: 11, color: _mint),
                      ),
                  ],
                ),
              ),
              IconButton(
                key: Key('queue-up-${plan.id}'),
                tooltip: '${plan.definition.name}を前へ',
                icon: const Icon(Icons.arrow_upward, size: 18),
                onPressed: index == 0 || controller.busy
                    ? null
                    : () => _move(plan, upcoming[index - 1], true),
              ),
              IconButton(
                key: Key('queue-down-${plan.id}'),
                tooltip: '${plan.definition.name}を後ろへ',
                icon: const Icon(Icons.arrow_downward, size: 18),
                onPressed: index == upcoming.length - 1 || controller.busy
                    ? null
                    : () => _move(plan, upcoming[index + 1], false),
              ),
              IconButton(
                key: Key('queue-cancel-${plan.id}'),
                tooltip: plan.status == 'running'
                    ? '${plan.definition.name}を現在の1回で終了'
                    : '${plan.definition.name}の予約を取り消す',
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                onPressed: controller.busy
                    ? null
                    : () => _cancel(context, plan),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 9, bottom: 5),
            child: Text(
              plan.definition.unique
                  ? '必要 ${GameContent.researchPointCost(plan.taskId)} RP · 保有 ${controller.state.researchPoints.toStringAsFixed(1)} RP'
                  : '1回の目安 ${gameDuration(controller.state.plannedDurationMs(plan))} · 開始時 ${dollars(controller.state.plannedCost(plan))}（未払い）',
              key: Key('queue-estimate-${plan.id}'),
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ),
          if (unlimitedBefore != null)
            Padding(
              padding: const EdgeInsets.only(right: 9, bottom: 5),
              child: Text(
                '先にある「${unlimitedBefore.definition.name}」の無期限反復が続く間、この予約は開始しません。',
                key: Key('unlimited-before-${plan.id}'),
                style: const TextStyle(color: _copper, fontSize: 11),
              ),
            ),
          if (index > 0)
            TextButton.icon(
              key: Key('queue-next-${plan.id}'),
              onPressed: controller.busy
                  ? null
                  : () => _move(plan, upcoming.first, true),
              icon: const Icon(Icons.vertical_align_top, size: 16),
              label: Text(
                '次に実行',
                semanticsLabel: '${plan.definition.name}を次の予約の先頭へ移動',
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 9),
            child: Text(
              plan.status == 'running'
                  ? '次回以降の反復 · ${plan.completedRuns}回完了'
                  : plan.stopReason.isEmpty
                  ? '開始待ち'
                  : plan.stopReason,
              style: TextStyle(
                color:
                    plan.status != 'running' &&
                        plan.stopReason.isNotEmpty &&
                        plan.stopReason != '共用設備の順番待ち'
                    ? _copper
                    : _muted,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(BuildContext context, PlannedTask plan) async {
    final running = plan.status == 'running';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(running ? 'この1回で反復を終了しますか？' : '予約を取り消しますか？'),
        content: Text(
          '${plan.definition.name}\n'
          '${plan.cityId == null ? '' : '${_location(plan, controller.state)}\n'}'
          '${running
              ? '進行中の1回は完成まで続き、その後の反復を終了します。確保済みの費用と進捗は維持されます。'
              : plan.definition.unique
              ? '未解放の研究予約を取り消します。RPはまだ使っていません。確認中に技術が解放された場合、その成果は保持します。'
              : '未着手の予約を取り消します。まだ費用は支払っていません。確認中に作業が始まった場合、その1回は完成まで続きます。'}',
        ),
        actions: [
          TextButton(
            key: Key('queue-keep-${plan.id}'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('予約を残す'),
          ),
          FilledButton(
            key: Key('queue-confirm-cancel-${plan.id}'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(running ? 'この1回で終了' : '予約を取り消す'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await controller.command((engine) => engine.cancelQueued(plan.id));
  }

  void _move(PlannedTask plan, PlannedTask relative, bool before) {
    controller.command(
      (engine) => engine.reorderPlan(
        plan.id,
        relativeToPlanId: relative.id,
        before: before,
      ),
    );
  }
}

/// Shared help for the facility list; current work and blockers stay in cards.
class QueueRulesDisclosure extends StatelessWidget {
  const QueueRulesDisclosure({super.key});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: ExpansionTile(
      key: const Key('queue-rules'),
      tilePadding: EdgeInsets.zero,
      title: const Text('予約・反復のしくみ', style: TextStyle(fontSize: 13)),
      children: const [
        Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            '同じ設備では上から順に着手します。「次に実行」や↑↓で順番を変更できます。進行中の1回は中断しません。\n\n'
            '研究予約は、必要な共通RPと前提がそろうと技術を必ず解放します。RPの蓄積中は、施設と研究者の配分を見直せます。\n\n'
            '建設・製造・育成などの費用は1回の着手ごとに支払います。未着手の費用・工期は、その時点の効率や土地で変わることがあります。\n\n'
            '先頭が資金・資材・研究の条件待ちなら、後続も待ちます。無期限反復の後ろにある作業は、反復より前に移すと進められます。\n\n'
            '取消は未着手の予約を取り消します。反復中なら現在の1回を最後に終了します。設備スイッチで休止した作業は、再開後に残り時間から続きます。',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
        ),
      ],
    ),
  );
}

String _purpose(PlannedTask plan) => plan.taskId.endsWith('_contract')
    ? '外部受注'
    : plan.taskId == 'train_specialists'
    ? '人員育成'
    : plan.definition.unique
    ? plan.status == 'running'
          ? '研究（着手済み）'
          : '技術解放'
    : plan.cityId != null
    ? '都市開発'
    : plan.taskId == 'earth_expansion'
    ? '地球開発'
    : '火星計画';

String _location(PlannedTask plan, GameState game) =>
    '${game.cityName(plan.cityId!)} · 区画 ${plan.plotIndex! + 1} · Lv.${plan.targetLevel}';
