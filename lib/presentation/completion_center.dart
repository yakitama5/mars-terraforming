import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/game_state.dart';
import 'strategy_widgets.dart';

class CompletionCenter extends StatefulWidget {
  const CompletionCenter({
    super.key,
    required this.controller,
    required this.onOpen,
  });
  final GameController controller;
  final ValueChanged<CompletionNotice> onOpen;

  @override
  State<CompletionCenter> createState() => _CompletionCenterState();
}

class _CompletionCenterState extends State<CompletionCenter> {
  bool showSettings = false;
  GameController get controller => widget.controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.engine == null) {
        return AlertDialog(
          content: const Text('進行状態を確認できません。画面を閉じて保存状態を確認してください。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        );
      }
      final game = controller.state;
      final notices = game.completionNotices.reversed.toList();
      final lastId = game.nextCompletionNoticeId - 1;
      return AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        titlePadding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '完了通知 · 未読 ${game.unreadCompletionNotices.length}件',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              key: const Key('completion-settings-toggle'),
              tooltip: '通知の表示設定',
              isSelected: showSettings,
              onPressed: () => setState(() => showSettings = !showSettings),
              icon: const Icon(Icons.tune, size: 20),
              selectedIcon: const Icon(
                Icons.tune,
                size: 20,
                color: strategyMint,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 560,
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (controller.error != null)
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '既読・表示設定を保存できていません。',
                        style: TextStyle(fontSize: 11, color: strategyCopper),
                      ),
                    ),
                    TextButton(
                      key: const Key('retry-notification-save'),
                      onPressed: controller.busy ? null : controller.save,
                      child: const Text('再保存'),
                    ),
                  ],
                ),
              Expanded(
                child: ListView(
                  key: const Key('completion-history'),
                  padding: EdgeInsets.zero,
                  children: [
                    if (showSettings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              key: const Key('completion-banner-setting'),
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                '画面下に完了をお知らせ',
                                style: TextStyle(fontSize: 13),
                              ),
                              value: game.completionBannersEnabled,
                              onChanged: controller.busy
                                  ? null
                                  : (value) => controller.command((engine) {
                                      engine.state.completionBannersEnabled =
                                          value;
                                      return null;
                                    }),
                            ),
                            const Text(
                              '最新48件を保存。同じ予約の未読の反復完了はまとめます。',
                              style: TextStyle(
                                fontSize: 11,
                                color: strategyMuted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Divider(height: 1, color: strategyLine),
                          ],
                        ),
                      ),
                    if (notices.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Column(
                          children: [
                            Icon(
                              Icons.task_alt,
                              size: 34,
                              color: strategyMuted,
                            ),
                            SizedBox(height: 12),
                            Text(
                              '建設・研究・製造・輸送が完了すると\nここに記録されます。',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    for (final notice in notices)
                      _CompletionRow(
                        notice: notice,
                        unread: notice.id > game.readCompletionNoticeId,
                        elapsedMs: game.simulatedMs,
                        onOpen: () {
                          Navigator.pop(context);
                          widget.onOpen(notice);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('mark-completions-read'),
            onPressed: controller.busy || game.unreadCompletionNotices.isEmpty
                ? null
                : () => controller.command((engine) {
                    engine.state.markCompletionsRead(lastId);
                    return null;
                  }),
            child: const Text('すべて既読にする'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      );
    },
  );
}

class _CompletionRow extends StatelessWidget {
  const _CompletionRow({
    required this.notice,
    required this.unread,
    required this.elapsedMs,
    required this.onOpen,
  });
  final CompletionNotice notice;
  final bool unread;
  final int elapsedMs;
  final VoidCallback onOpen;

  (IconData, String) get category {
    final task = notice.definition;
    if (task.districtId != null ||
        task.id == 'earth_expansion' ||
        task.id == 'build_habitat') {
      return (
        Icons.location_city_outlined,
        task.isDistrictUpgrade ? '増強' : '建設',
      );
    }
    if (task.unique) return (Icons.science_outlined, '研究');
    if (task.outputResource == 'marsKits') {
      return (Icons.rocket_launch_outlined, '輸送');
    }
    if (task.outputResource == 'earthKits') {
      return (Icons.inventory_2_outlined, '製造');
    }
    if (task.id.endsWith('_contract')) {
      return (Icons.payments_outlined, '受注');
    }
    return (Icons.groups_outlined, '育成');
  }

  String get title {
    final task = notice.definition;
    if (task.districtId != null) {
      return '${GameContent.districts[task.districtId]!.name} Lv.${notice.targetLevel}';
    }
    return task.name.replaceFirst('外部受注・', '');
  }

  @override
  Widget build(BuildContext context) {
    final (icon, label) = category;
    final age = (elapsedMs - notice.simulatedMs).clamp(0, elapsedMs);
    final ageLabel = age < 60000
        ? 'たった今'
        : '${gameDuration(age ~/ 60000 * 60000)}前';
    final tint = unread ? strategyMint : strategyMuted;
    return Semantics(
      button: true,
      label:
          '${unread ? '未読、' : ''}${notice.title}、${notice.location}、$ageLabel',
      excludeSemantics: true,
      onTap: onOpen,
      child: InkWell(
        key: Key('completion-${notice.id}'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: unread ? const Color(0xff24423f) : strategyPanel,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 19, color: tint),
                  ),
                  if (unread)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: strategyCopper,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message:
                              '開始から ${gameDuration(notice.simulatedMs)}に完了',
                          child: Text(
                            ageLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              color: strategyMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        Text(
                          label,
                          style: TextStyle(fontSize: 11, color: tint),
                        ),
                        if (notice.count > 1)
                          Text(
                            '${notice.count}回完了',
                            style: const TextStyle(
                              fontSize: 11,
                              color: strategyCopper,
                            ),
                          ),
                        Text(
                          notice.location,
                          style: const TextStyle(
                            fontSize: 11,
                            color: strategyMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: strategyMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
