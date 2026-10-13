import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/game_state.dart';
import 'strategy_widgets.dart';

const _mint = Color(0xffa2dfc8);
const _muted = Color(0xff98adb9);
const _copper = Color(0xffe8a57c);

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
        ? '稼働中'
        : upcoming.isNotEmpty
        ? '条件待ち'
        : '待機中';
    return Container(
      key: Key('facility-$facilityId'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xff172731),
        border: Border.all(color: const Color(0xff2a3c48)),
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
                      '$status · 基本維持費 ${enabled ? facility.upkeepPerMinute : 0} Cr/分',
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
              Switch(
                key: Key('facility-toggle-$facilityId'),
                value: enabled,
                onChanged: controller.busy
                    ? null
                    : (value) => controller.command(
                        (engine) =>
                            engine.setFacilityEnabled(facilityId, value),
                      ),
              ),
            ],
          ),
          const Divider(color: Color(0xff2a3c48)),
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
            _queued(plan, index, upcoming),
        ],
      ),
    );
  }

  Widget _current(PlannedTask plan, bool enabled) => Container(
    key: Key('current-${plan.id}'),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xff223a3c),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '現在の1回 · ${_purpose(plan)}',
                style: const TextStyle(fontSize: 11, color: _mint),
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
        if (plan.cityId != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _location(plan),
              style: const TextStyle(fontSize: 12, color: _mint),
            ),
          ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: plan.progress.clamp(0, 1),
          minHeight: 4,
          backgroundColor: const Color(0xff2a3c48),
        ),
        const SizedBox(height: 6),
        Text(
          '${enabled ? '進行中' : plan.stopReason} · 残り ${gameDuration(plan.remainingMs)}',
          style: TextStyle(color: enabled ? _mint : _copper, fontSize: 11),
        ),
        const SizedBox(height: 4),
        const Text(
          'この1回は順番変更後も続行・費用は確保済み',
          style: TextStyle(fontSize: 10, color: _muted),
        ),
      ],
    ),
  );

  Widget _queued(PlannedTask plan, int index, List<PlannedTask> upcoming) {
    final repeat = plan.remainingRepeats;
    final futureCount = repeat == null
        ? '無期限'
        : '${repeat - (plan.status == 'running' ? 1 : 0)}回';
    return Container(
      key: Key('upcoming-${plan.id}'),
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.fromLTRB(9, 7, 0, 7),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xff2a3c48)),
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
                      '${index + 1}. ${_purpose(plan)} · $futureCount',
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
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (plan.cityId != null)
                      Text(
                        _location(plan),
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
                tooltip: plan.status == 'running' ? '現在の1回で反復を終了' : 'この予約を取り消す',
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                onPressed: controller.busy
                    ? null
                    : () => controller.command(
                        (engine) => engine.cancelQueued(plan.id),
                      ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 9),
            child: Text(
              plan.status == 'running'
                  ? '現在の1回の後の反復 · ${plan.completedRuns}回完了'
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

String _purpose(PlannedTask plan) => plan.taskId.endsWith('_contract')
    ? '外部受注'
    : plan.definition.unique
    ? '研究'
    : plan.cityId != null
    ? '都市開発'
    : plan.taskId == 'earth_expansion'
    ? '地球開発'
    : '火星計画';

String _location(PlannedTask plan) =>
    '${GameContent.cities[plan.cityId]!.name} · 区画 ${plan.plotIndex! + 1} · Lv.${plan.targetLevel}';
