import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/main.dart';

import 'widget_test.dart' show MemorySave;

void main() {
  final epoch = DateTime.utc(2026, 10, 15);

  testWidgets(
    'offline research completions remain unread until acknowledged and survive restart',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var now = epoch;
      final store = MemorySave();
      final original = GameController(store, now: () => now);
      await original.initialize(startTimer: false);
      await original.command((engine) => engine.enqueue('life_support'));
      original.dispose();
      now = epoch.add(const Duration(minutes: 5));
      final controller = GameController(store, now: () => now);
      addTearDown(controller.dispose);
      await controller.initialize(startTimer: false);
      await tester.pumpWidget(
        MarsApp(controller: controller, renderScene: false),
      );
      expect(find.text('通知 1'), findsOneWidget);
      final money = controller.state.moneyUnits;
      await tester.tap(find.byKey(const Key('open-completions')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('completion-history')), findsOneWidget);
      await tester.tap(find.byKey(const Key('mark-completions-read')));
      await tester.pumpAndSettle();
      expect(controller.state.unreadCompletionNotices, isEmpty);
      expect(controller.state.moneyUnits, money);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      final restored = GameController(store, now: () => now);
      addTearDown(restored.dispose);
      await restored.initialize(startTimer: false);
      expect(restored.state.unreadCompletionNotices, isEmpty);
      expect(restored.state.completionNotices, hasLength(1));
      expect(restored.state.moneyUnits, money);
    },
  );

  testWidgets(
    'notification opens completed research and display preferences are saved',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemorySave();
      final controller = GameController(
        store,
        now: () => epoch,
        devTools: true,
      );
      try {
        await controller.initialize(startTimer: false);
        await controller.command((engine) => engine.enqueue('life_support'));
        await controller.advanceForDevelopment();
        await tester.pumpWidget(
          MarsApp(controller: controller, renderScene: false),
        );
        await tester.tap(find.byKey(const Key('open-completions')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('completion-settings-toggle')));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(controller.state.completionBannersEnabled, isFalse);
        await tester.tap(
          find.byKey(
            Key('completion-${controller.state.completionNotices.single.id}'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('research-detail')), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          store.data!['guidancePreferences'],
          containsPair('completionBannersEnabled', false),
        );
        expect(tester.takeException(), isNull);
      } finally {
        controller.dispose();
      }
    },
  );

  testWidgets(
    'notification acknowledgement save failure is visible and retryable',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemorySave();
      final controller = GameController(
        store,
        now: () => epoch,
        devTools: true,
      );
      try {
        await controller.initialize(startTimer: false);
        await controller.command((engine) => engine.enqueue('life_support'));
        await controller.advanceForDevelopment();
        await tester.pumpWidget(
          MarsApp(controller: controller, renderScene: false),
        );
        await tester.tap(find.byKey(const Key('open-completions')));
        await tester.pumpAndSettle();
        store.fail = true;
        await tester.tap(find.byKey(const Key('mark-completions-read')));
        await tester.pumpAndSettle();
        expect(find.text('既読・表示設定を保存できていません。'), findsOneWidget);
        expect(store.data!['readCompletionNoticeId'], 0);
        expect(tester.takeException(), isNull);
        store.fail = false;
        await tester.tap(find.byKey(const Key('retry-notification-save')));
        await tester.pumpAndSettle();
        expect(find.text('既読・表示設定を保存できていません。'), findsNothing);
        expect(store.data!['readCompletionNoticeId'], 1);
      } finally {
        controller.dispose();
      }
    },
  );

  testWidgets(
    'guide is reachable from every tab and nested roadmap closes before navigating',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = GameController(MemorySave(), now: () => epoch);
      addTearDown(controller.dispose);
      await controller.initialize(startTimer: false);
      await tester.pumpWidget(
        MarsApp(controller: controller, renderScene: false),
      );
      await tester.tap(find.byKey(const Key('navigation-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-guidance')));
      await tester.pumpAndSettle();
      final roadmap = find.byKey(const Key('guide-roadmap'));
      await tester.ensureVisible(roadmap);
      await tester.tap(roadmap);
      await tester.pumpAndSettle();
      final research = find.byKey(const Key('onboarding-open-first_research'));
      await tester.ensureVisible(research);
      await tester.tap(research);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const Key('research-detail')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
