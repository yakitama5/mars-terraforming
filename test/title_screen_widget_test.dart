import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/presentation/title_screen.dart';

Future<void> _mountTitle(
  WidgetTester tester, {
  Size size = const Size(844, 390),
  double textScale = 1,
  bool reduceMotion = false,
  TitleSceneBuilder? sceneBuilder,
  required VoidCallback onStart,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: TitleScreen(
        game: GameState.initial(DateTime.utc(2026, 10, 25)),
        renderScene: false,
        sceneBuilder: sceneBuilder,
        onStart: onStart,
      ),
    ),
  );
  await tester.pump();
}

double _backgroundOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find.descendant(
        of: find.byKey(const Key('title-background-fade')),
        matching: find.byType(FadeTransition),
      ),
    )
    .opacity
    .value;

void main() {
  for (final size in [const Size(568, 320), const Size(844, 390)]) {
    testWidgets('横${size.width.toInt()}px・文字1.5倍でもタイトルと開始案内が収まる', (
      tester,
    ) async {
      await _mountTitle(tester, size: size, textScale: 1.5, onStart: () {});
      final screen = Offset.zero & size;
      for (final label in [
        'DEAR MARS',
        '火星開発計画',
        'TAP TO START',
        'タップしてはじめる',
      ]) {
        final target = find.text(label);
        expect(target, findsOneWidget);
        final rect = tester.getRect(target);
        expect(screen.contains(rect.topLeft), isTrue, reason: label);
        expect(screen.contains(rect.bottomRight), isTrue, reason: label);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('背景の準備を待たず開始でき、開始後に届く通知も安全に破棄する', (tester) async {
    var starts = 0;
    late VoidCallback ready;
    late ValueChanged<Object> failed;
    final semantics = tester.ensureSemantics();
    try {
      await _mountTitle(
        tester,
        sceneBuilder: (_, onReady, onError) {
          ready = onReady;
          failed = onError;
          return const ColoredBox(color: Colors.red);
        },
        onStart: () => starts++,
      );
      expect(find.text('DEAR MARS'), findsOneWidget);
      expect(find.text('TAP TO START'), findsOneWidget);
      expect(find.byKey(const Key('title-loading')), findsNothing);
      expect(_backgroundOpacity(tester), 0);
      expect(
        tester.getSemantics(find.bySemanticsLabel('タップまたはクリックしてスタート')),
        isSemantics(
          label: 'タップまたはクリックしてスタート',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(find.byKey(const Key('title-start')));
      await tester.pump();
      ready();
      failed(StateError('開始後に完了した背景の読み込み'));
      await tester.pump(const Duration(milliseconds: 450));
      expect(starts, 1, reason: '背景の準備通知は開始完了の条件にしない');
      expect(_backgroundOpacity(tester), 0, reason: '開始後は背景の出現を始めない');
      await tester.pumpWidget(const SizedBox.shrink());
      ready();
      failed(StateError('画面破棄後に届いた読み込みエラー'));
      await tester.pump();
      expect(starts, 1);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('読み込み完了後は背景だけフェードインし、タイトルと開始案内は保持する', (tester) async {
    var starts = 0;
    late VoidCallback ready;
    await _mountTitle(
      tester,
      sceneBuilder: (_, onReady, _) {
        ready = onReady;
        return const ColoredBox(color: Colors.red);
      },
      onStart: () => starts++,
    );
    final title = tester.element(find.text('DEAR MARS'));
    final prompt = tester.element(find.text('TAP TO START'));
    await tester.pump(const Duration(seconds: 3));
    expect(_backgroundOpacity(tester), 0);
    ready();
    await tester.pump();
    expect(_backgroundOpacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 450));
    expect(_backgroundOpacity(tester), allOf(greaterThan(0), lessThan(1)));
    expect(tester.element(find.text('DEAR MARS')), same(title));
    expect(tester.element(find.text('TAP TO START')), same(prompt));
    expect(find.byKey(const Key('title-start')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_backgroundOpacity(tester), 1);
    expect(starts, 0, reason: '背景の準備完了だけではゲームを開始しない');
    expect(tester.takeException(), isNull);
  });

  for (final fails in [false, true]) {
    testWidgets('動きを減らす設定では背景の${fails ? '代替表示' : '準備完了'}も待機なしで表示する', (
      tester,
    ) async {
      var starts = 0;
      late VoidCallback ready;
      late ValueChanged<Object> failed;
      await _mountTitle(
        tester,
        reduceMotion: true,
        sceneBuilder: (_, onReady, onError) {
          ready = onReady;
          failed = onError;
          return const ColoredBox(color: Colors.red);
        },
        onStart: () => starts++,
      );
      expect(_backgroundOpacity(tester), 0);
      if (fails) {
        failed(StateError('GPUを利用できない'));
      } else {
        ready();
      }
      await tester.pump();
      expect(_backgroundOpacity(tester), 1);
      expect(find.text('DEAR MARS'), findsOneWidget);
      expect(find.text('TAP TO START'), findsOneWidget);
      expect(starts, 0);
      await tester.tap(find.byKey(const Key('title-start')));
      expect(starts, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('画面端のタップとマウスクリックの連打でも開始は一度だけ', (tester) async {
    var starts = 0;
    await _mountTitle(tester, onStart: () => starts++);
    await tester.tapAt(const Offset(2, 2));
    await tester.pump();
    expect(starts, 0, reason: '通常は画面の暗転完了を待つ');
    await tester.tapAt(const Offset(842, 388));
    await tester.tapAt(const Offset(422, 195), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 450));
    expect(starts, 1);
    await tester.tapAt(const Offset(2, 388));
    await tester.pump(const Duration(seconds: 1));
    expect(starts, 1);
    expect(tester.takeException(), isNull);
  });

  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
    testWidgets('${key.keyLabel}の押しっぱなし・再入力でも開始は一度だけ', (tester) async {
      var starts = 0;
      await _mountTitle(
        tester,
        sceneBuilder: (_, _, _) => const ColoredBox(color: Colors.red),
        onStart: () => starts++,
      );
      await tester.sendKeyDownEvent(key);
      await tester.pump();
      expect(starts, 0);
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyRepeatEvent(key);
      }
      await tester.pump(const Duration(milliseconds: 450));
      expect(starts, 1);
      await tester.sendKeyUpEvent(key);
      await tester.sendKeyEvent(key);
      await tester.sendKeyEvent(
        key == LogicalKeyboardKey.enter
            ? LogicalKeyboardKey.space
            : LogicalKeyboardKey.enter,
      );
      await tester.pump(const Duration(milliseconds: 450));
      expect(starts, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('動きを減らす設定では暗転待ちなしで開始する', (tester) async {
    var starts = 0;
    await _mountTitle(tester, reduceMotion: true, onStart: () => starts++);
    await tester.tap(find.byKey(const Key('title-start')));
    expect(starts, 1, reason: '次のフレームや400msの暗転を待たない');
    await tester.tap(find.byKey(const Key('title-start')));
    await tester.pump();
    expect(starts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Creditsは開始せず出典とCC BYを表示し、閉じた後に開始できる', (tester) async {
    var starts = 0;
    await _mountTitle(
      tester,
      reduceMotion: true,
      sceneBuilder: (_, _, _) => const ColoredBox(color: Colors.red),
      onStart: () => starts++,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Credits'));
    await tester.pumpAndSettle();
    expect(starts, 0);
    expect(find.text('素材のクレジット'), findsOneWidget);
    final credits = tester.widget<SelectableText>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(SelectableText),
      ),
    );
    expect(credits.data, contains('ESO/S. Brunier'));
    expect(
      credits.data,
      contains('https://www.eso.org/public/images/eso0932a/'),
    );
    expect(credits.data, contains('Creative Commons Attribution 4.0'));
    expect(
      credits.data,
      contains('https://creativecommons.org/licenses/by/4.0/'),
    );
    await tester.tap(find.widgetWithText(TextButton, '閉じる'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(starts, 0, reason: '閉じる操作を背後の開始へ伝えない');
    expect(_backgroundOpacity(tester), 0, reason: '背景の読込中もクレジットを確認できる');
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    expect(starts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('暗転中に画面を破棄しても開始や例外を残さない', (tester) async {
    var starts = 0;
    late VoidCallback ready;
    late ValueChanged<Object> failed;
    await _mountTitle(
      tester,
      sceneBuilder: (_, onReady, onError) {
        ready = onReady;
        failed = onError;
        return const ColoredBox(color: Colors.red);
      },
      onStart: () => starts++,
    );
    await tester.tap(find.byKey(const Key('title-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpWidget(const SizedBox.shrink());
    ready();
    failed(StateError('暗転中の破棄後に届いた読み込みエラー'));
    await tester.pump(const Duration(seconds: 1));
    expect(starts, 0);
    expect(tester.takeException(), isNull);
  });
}
