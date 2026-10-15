import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_state.dart';
import 'strategy_widgets.dart';

class CompletionCenter extends StatelessWidget {
  const CompletionCenter({
    super.key,
    required this.controller,
    required this.onOpen,
  });
  final GameController controller;
  final ValueChanged<CompletionNotice> onOpen;

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
        title: Text('完了通知 · 未読 ${game.unreadCompletionNotices.length}件'),
        content: SizedBox(
          width: 560,
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '画面下に完了をお知らせ',
                  style: TextStyle(fontSize: 13),
                ),
                value: game.completionBannersEnabled,
                onChanged: controller.busy
                    ? null
                    : (value) => controller.command((engine) {
                        engine.state.completionBannersEnabled = value;
                        return null;
                      }),
              ),
              const Text(
                '最新48件を保存。同じ予約の未読の反復完了はまとめます。',
                style: TextStyle(fontSize: 11, color: strategyMuted),
              ),
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
              const SizedBox(height: 8),
              Expanded(
                child: notices.isEmpty
                    ? const Center(
                        child: Text(
                          '建設・研究・製造・輸送が完了すると\nここに記録されます。',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        key: const Key('completion-history'),
                        itemCount: notices.length,
                        itemBuilder: (context, index) {
                          final notice = notices[index];
                          final unread =
                              notice.id > game.readCompletionNoticeId;
                          return ListTile(
                            key: Key('completion-${notice.id}'),
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              unread
                                  ? Icons.fiber_new
                                  : Icons.check_circle_outline,
                              color: unread ? strategyCopper : strategyMuted,
                            ),
                            title: Text(
                              notice.title,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              '${notice.location}\n開始から ${gameDuration(notice.simulatedMs)}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.pop(context);
                              onOpen(notice);
                            },
                          );
                        },
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
