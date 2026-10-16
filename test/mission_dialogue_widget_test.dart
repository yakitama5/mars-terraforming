import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/presentation/mission_adviser.dart';
import 'package:mars_terraforming/presentation/mission_dialogue.dart';

class _DialogueAssets extends CachingAssetBundle {
  _DialogueAssets({this.missing = const {}});
  final Set<String> missing;
  static final _pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAABmJLR0QA/wD/AP+gvaeT'
    'AAAACXBIWXMAAAsTAAALEwEAmpwYAAAAB3RJTUUH5gMQFwcdLl4wmwAAAAtJREFUCNdj'
    'YAACAAAFAAHiJgWbAAAAAElFTkSuQmCC',
  );

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object>{})!;
    }
    if (missing.contains(key)) throw FlutterError('Missing test art: $key');
    return ByteData.sublistView(_pixel);
  }
}

Widget _host({
  required AssetBundle bundle,
  required String text,
  Object? dialogueKey,
  String? title,
  MinaExpression expression = MinaExpression.normal,
  bool reduceMotion = false,
  bool tickerEnabled = true,
  double textScale = 1,
  double height = 260,
  VoidCallback? onNext,
  GlobalKey<NavigatorState>? navigatorKey,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) => DefaultAssetBundle(
    bundle: bundle,
    child: MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reduceMotion,
        textScaler: TextScaler.linear(textScale),
      ),
      child: TickerMode(enabled: tickerEnabled, child: child!),
    ),
  ),
  home: Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: height,
          child: MissionDialogue(
            text: text,
            title: title,
            dialogueKey: dialogueKey,
            expression: expression,
            actions: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                OutlinedButton(onPressed: () {}, child: const Text('戻る')),
                FilledButton(
                  onPressed: onNext ?? () {},
                  child: const Text('次へ'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

String _visibleText(WidgetTester tester) {
  final text = tester.widget<Text>(
    find.byKey(const Key('mission-dialogue-text')),
  );
  return (text.textSpan! as TextSpan).children!.first.toPlainText();
}

double _portraitDisplacement(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(const Key('mina-portrait-motion')))
    .transform
    .getTranslation()
    .length;

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('mission-dialogue-scroll')),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

void main() {
  testWidgets('typing reveals complete graphemes and a tap never advances', (
    tester,
  ) async {
    const text = 'ルナと火星へ。👩‍🚀 新しい暮らしを始めましょう。';
    final bundle = _DialogueAssets();
    var nextCount = 0;
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _host(bundle: bundle, text: text, onNext: () => nextCount++),
      );
      expect(_visibleText(tester), isNot(text));
      expect(find.bySemanticsLabel('ルナ。$text'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_visibleText(tester), isNotEmpty);
      final prefixes = [
        for (var length = 0; length <= text.characters.length; length++)
          text.characters.take(length).join(),
      ];
      expect(prefixes, contains(_visibleText(tester)));
      expect(find.bySemanticsLabel('ルナ。$text'), findsOneWidget);
      await tester.tap(find.byKey(const Key('mission-dialogue-reveal')));
      await tester.pump();
      expect(_visibleText(tester), text);
      expect(nextCount, 0);
      await tester.tap(find.text('次へ'));
      expect(nextCount, 1);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('a new dialogue restarts typing without replacing the portrait', (
    tester,
  ) async {
    final bundle = _DialogueAssets();
    const first = '最初の案内です。';
    const second = '研究が完成しました。次の計画へ進みましょう。';
    await tester.pumpWidget(_host(bundle: bundle, text: first, dialogueKey: 1));
    final portraitState = tester.state(find.byType(MinaPortrait));
    await tester.tap(find.byKey(const Key('mission-dialogue-reveal')));
    await tester.pump();
    expect(_visibleText(tester), first);
    await tester.pumpWidget(_host(bundle: bundle, text: first, dialogueKey: 1));
    expect(_visibleText(tester), first);
    await tester.pumpWidget(
      _host(
        bundle: bundle,
        text: second,
        dialogueKey: 2,
        expression: MinaExpression.joy,
      ),
    );
    expect(_visibleText(tester), isNot(second));
    expect(tester.state(find.byType(MinaPortrait)), same(portraitState));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_portraitDisplacement(tester), greaterThan(0));
    await tester.pumpAndSettle();
    expect(_visibleText(tester), second);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'standing art has no frame or crop and reduced motion is static',
    (tester) async {
      const text = '動きを減らす設定でも、全文をすぐに読めます。';
      await tester.pumpWidget(
        _host(bundle: _DialogueAssets(), text: text, reduceMotion: true),
      );
      final portrait = tester.widget<Container>(
        find.byKey(const Key('mina-standing-portrait')),
      );
      expect(portrait.decoration, isNull);
      expect(portrait.clipBehavior, Clip.none);
      expect(find.byKey(const Key('mina-avatar-frame')), findsNothing);
      final image = tester.widget<Image>(
        find.byKey(const Key('mina-portrait')),
      );
      expect(image.fit, BoxFit.contain);
      expect(image.alignment, Alignment.bottomCenter);
      expect(_visibleText(tester), text);
      expect(_portraitDisplacement(tester), 0);
      expect(
        tester
            .widget<Opacity>(find.byKey(const Key('mission-dialogue-entrance')))
            .opacity,
        1,
      );
      await tester.pump(const Duration(seconds: 6));
      expect(_visibleText(tester), text);
      expect(_portraitDisplacement(tester), 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hiding a dialogue pauses typing and visible playback resumes', (
    tester,
  ) async {
    final text = '街と研究をつなげて、火星へ届けましょう。' * 8;
    final bundle = _DialogueAssets();
    await tester.pumpWidget(_host(bundle: bundle, text: text));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(
      _host(bundle: bundle, text: text, tickerEnabled: false),
    );
    final paused = _visibleText(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(_visibleText(tester), paused);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(_host(bundle: bundle, text: text));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_visibleText(tester).length, greaterThan(paused.length));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an application pause and a covering route stop dialogue ticks', (
    tester,
  ) async {
    final text = '遠い惑星での暮らしを、ひとつずつ実現します。' * 8;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _host(bundle: _DialogueAssets(), text: text, navigatorKey: navigator),
    );
    await tester.pump(const Duration(milliseconds: 100));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    try {
      await tester.pump();
      final paused = _visibleText(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(_visibleText(tester), paused);
      expect(tester.binding.hasScheduledFrame, isFalse);
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
    await tester.pump();
    unawaited(
      navigator.currentState!.push<void>(
        DialogRoute<void>(
          context: tester.element(find.byType(MissionDialogue)),
          builder: (_) => const AlertDialog(content: Text('別の画面')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final covered = _visibleText(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(_visibleText(tester), covered);
    expect(tester.binding.hasScheduledFrame, isFalse);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(_visibleText(tester), text);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'small landscape and large text keep actions fixed while speech scrolls',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final bundle = _DialogueAssets();
      final text = '街の収入で研究を進め、工場でつくり、ロケットで届けます。\n' * 12;
      var nextCount = 0;
      for (final size in [const Size(844, 390), const Size(568, 320)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          _host(
            bundle: bundle,
            text: text,
            title: '新しい故郷を目指す計画',
            textScale: 1.5,
            reduceMotion: true,
            height: size.height - 32,
            dialogueKey: size,
            onNext: () => nextCount++,
          ),
        );
        final actions = tester.getRect(find.widgetWithText(FilledButton, '次へ'));
        expect(actions.top, greaterThanOrEqualTo(0));
        expect(actions.bottom, lessThanOrEqualTo(size.height));
        expect(actions.right, lessThanOrEqualTo(size.width));
        expect(_position(tester).maxScrollExtent, greaterThan(0));
        await tester.drag(
          find.byKey(const Key('mission-dialogue-scroll')),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        expect(_position(tester).pixels, greaterThan(0));
        expect(
          tester.getRect(find.widgetWithText(FilledButton, '次へ')),
          actions,
        );
        await tester.tap(find.text('次へ'));
        expect(tester.takeException(), isNull);
      }
      expect(nextCount, 2);
      await tester.pumpWidget(
        _host(
          bundle: bundle,
          text: text,
          reduceMotion: true,
          dialogueKey: 'new',
        ),
      );
      expect(_position(tester).pixels, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('standing portrait retains the shared missing-image fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        bundle: _DialogueAssets(missing: {MinaExpression.joy.assetPath}),
        text: '新しい計画を確認しましょう。',
        expression: MinaExpression.joy,
        reduceMotion: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mina-normal-fallback')), findsOneWidget);
    expect(find.byIcon(Icons.support_agent), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing a speaking portrait releases all animation work', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(bundle: _DialogueAssets(), text: '火星の未来を描いていきましょう。' * 12),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
