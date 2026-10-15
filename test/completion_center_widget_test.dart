import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/presentation/completion_center.dart';

class _NotificationSave implements SaveRepository {
  Map<String, dynamic>? data;
  bool fail = false;
  bool conflict = false;

  @override
  Future<SaveLoadResult> load() async =>
      SaveLoadResult(data: data, recovered: false, generation: 1);

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    if (conflict) throw const SaveConflictException('別の画面で更新');
    if (fail) throw StateError('保存できません');
    data = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  }
}

void _addHistory(GameState state) {
  state.simulatedMs = 600000;
  state.completionNotices.addAll([
    for (final (index, task) in [
      'train_specialists',
      'habitat_kit',
      'mars_delivery',
      'life_support',
      'factory_contract',
    ].indexed)
      CompletionNotice(
        id: index + 1,
        planId: 'plan-${index + 1}',
        taskId: task,
        simulatedMs: 60000 * index,
        count: task == 'factory_contract' ? 214 : 1,
      ),
    const CompletionNotice(
      id: 6,
      planId: 'plan-6',
      taskId: 'district_housing',
      cityId: 'earth_delta',
      plotIndex: 0,
      targetLevel: 1,
      simulatedMs: 540000,
    ),
  ]);
  state.nextCompletionNoticeId = 7;
}

Future<void> _show(
  WidgetTester tester,
  GameController controller, {
  Size size = const Size(844, 390),
  double textScale = 1,
  ValueChanged<CompletionNotice>? onOpen,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => CompletionCenter(
                controller: controller,
                onOpen: onOpen ?? (_) {},
              ),
            ),
            child: const Text('通知を開く'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('通知を開く'));
  await tester.pumpAndSettle();
}

void main() {
  final epoch = DateTime.utc(2026, 10, 15);

  testWidgets(
    'notification history takes priority and preserves each destination',
    (tester) async {
      final controller = GameController(_NotificationSave(), now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      _addHistory(controller.state);
      CompletionNotice? opened;
      final before = jsonEncode(controller.state.toJson());
      await _show(tester, controller, onOpen: (notice) => opened = notice);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.textContaining('最新48件'), findsNothing);
      for (final id in [6, 5, 4]) {
        expect(find.byKey(Key('completion-$id')).hitTestable(), findsOneWidget);
      }
      expect(find.text('住宅地区 Lv.1'), findsOneWidget);
      expect(find.text('1分前'), findsOneWidget);
      expect(find.text('214回完了'), findsOneWidget);
      await tester.tap(find.byKey(const Key('completion-6')));
      await tester.pumpAndSettle();
      expect(opened?.cityId, 'earth_delta');
      expect(opened?.plotIndex, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(jsonEncode(controller.state.toJson()), before);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'small notification panel scrolls with settings at text scale $scale',
      (tester) async {
        final store = _NotificationSave();
        final controller = GameController(store, now: () => epoch);
        await controller.initialize(startTimer: false);
        addTearDown(controller.dispose);
        _addHistory(controller.state);
        await _show(
          tester,
          controller,
          size: const Size(568, 320),
          textScale: scale,
        );
        await tester.tap(find.byKey(const Key('completion-settings-toggle')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('completion-banner-setting')),
        );
        await tester.tap(find.byKey(const Key('completion-banner-setting')));
        await tester.pumpAndSettle();
        expect(controller.state.completionBannersEnabled, isFalse);
        expect(
          store.data!['guidancePreferences'],
          containsPair('completionBannersEnabled', false),
        );
        expect(find.textContaining('最新48件'), findsOneWidget);
        await tester.tap(find.byKey(const Key('completion-settings-toggle')));
        await tester.pumpAndSettle();
        final oldest = find.byKey(const Key('completion-1'));
        await tester.scrollUntilVisible(
          oldest,
          100,
          scrollable: find.descendant(
            of: find.byKey(const Key('completion-history')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        expect(oldest.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'save error remains visible with settings closed and retry persists acknowledgement',
    (tester) async {
      final store = _NotificationSave();
      final controller = GameController(store, now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      _addHistory(controller.state);
      await _show(
        tester,
        controller,
        size: const Size(568, 320),
        textScale: 1.5,
      );
      store.fail = true;
      await tester.tap(find.byKey(const Key('mark-completions-read')));
      await tester.pumpAndSettle();
      expect(find.text('既読・表示設定を保存できていません。'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(tester.takeException(), isNull);
      store.fail = false;
      await tester.tap(find.byKey(const Key('retry-notification-save')));
      await tester.pumpAndSettle();
      expect(store.data!['readCompletionNoticeId'], 6);
      expect(find.text('既読・表示設定を保存できていません。'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty history and lost engine both have an operable close action',
    (tester) async {
      final store = _NotificationSave();
      final controller = GameController(store, now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await _show(
        tester,
        controller,
        size: const Size(568, 320),
        textScale: 1.5,
      );
      expect(find.textContaining('ここに記録されます。'), findsOneWidget);
      store.conflict = true;
      await controller.save();
      await tester.pumpAndSettle();
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
