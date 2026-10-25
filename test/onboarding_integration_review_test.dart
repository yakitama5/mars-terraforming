import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/main.dart';

import 'widget_test.dart' show MemorySave;

class _ConflictSave extends MemorySave {
  bool conflict = false;

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    if (conflict) throw const SaveConflictException('別の画面で更新');
    await super.save(snapshot);
  }
}

Future<void> _smallScreen(
  WidgetTester tester,
  GameController controller,
) async {
  tester.view.physicalSize = const Size(568, 320);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MarsApp(
      showTitle: false,
      showIntroduction: false,
      controller: controller,
      renderScene: false,
    ),
  );
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  final epoch = DateTime.utc(2026, 10, 15);

  testWidgets(
    '568-wide guidance opens from every tab and nested navigation closes both dialogs',
    (tester) async {
      final controller = GameController(MemorySave(), now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await _smallScreen(tester, controller);
      for (var tab = 0; tab < 5; tab++) {
        await tester.tap(find.byKey(Key('navigation-$tab')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('open-guidance')));
        await tester.pumpAndSettle();
        await _tapVisible(tester, find.byKey(const Key('guide-roadmap')).last);
        await _tapVisible(
          tester,
          find.byKey(const Key('onboarding-open-first_research')),
        );
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byKey(const Key('research-detail')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'hidden tutorial and tips survive restart while guide stays reachable',
    (tester) async {
      final store = MemorySave();
      final controller = GameController(store, now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await _smallScreen(tester, controller);
      await tester.tap(find.byKey(const Key('open-guidance')));
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.byKey(const Key('guidance-display-settings')),
      );
      await _tapVisible(
        tester,
        find.widgetWithText(SwitchListTile, '惑星マップに導入ガイドを表示'),
      );
      await _tapVisible(
        tester,
        find.widgetWithText(SwitchListTile, '状況に応じたTipsを表示'),
      );
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guide-roadmap')), findsNothing);
      expect(find.byKey(const Key('contextual-tips-panel')), findsNothing);
      final restored = GameController(store, now: () => epoch);
      await restored.initialize(startTimer: false);
      addTearDown(restored.dispose);
      expect(restored.state.tutorialHidden, isTrue);
      expect(restored.state.tipsEnabled, isFalse);
      await tester.pumpWidget(
        MarsApp(
          showTitle: false,
          showIntroduction: false,
          controller: restored,
          renderScene: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-guidance')));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.byKey(const Key('guide-roadmap')));
      expect(find.textContaining('宇宙開発の手引き'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'save conflict while both guide dialogs are open leaves a usable close path',
    (tester) async {
      final store = _ConflictSave();
      final controller = GameController(store, now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await _smallScreen(tester, controller);
      await tester.tap(find.byKey(const Key('navigation-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-guidance')));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.byKey(const Key('guide-roadmap')));
      store.conflict = true;
      await controller.save();
      await tester.pumpAndSettle();
      expect(controller.engine, isNull);
      expect(find.text('手引きを更新できません'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('onboarding-close')));
      await tester.pumpAndSettle();
      expect(find.text('保存状態を確認してください。'), findsOneWidget);
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('保存内容の競合を検出'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
