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
        onStart: onStart,
      ),
    ),
  );
  await tester.pump();
}

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
      await _mountTitle(tester, onStart: () => starts++);
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

  testWidgets('暗転中に画面を破棄しても開始や例外を残さない', (tester) async {
    var starts = 0;
    await _mountTitle(tester, onStart: () => starts++);
    await tester.tap(find.byKey(const Key('title-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(starts, 0);
    expect(tester.takeException(), isNull);
  });
}
