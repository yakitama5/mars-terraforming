import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/presentation/mission_adviser.dart';

class _PortraitBundle extends CachingAssetBundle {
  _PortraitBundle({this.missing = const {}});
  final Set<String> missing;

  // One valid transparent pixel keeps gesture tests independent of artwork.
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
    if (missing.contains(key)) throw FlutterError('Missing portrait: $key');
    return ByteData.sublistView(_pixel);
  }
}

Widget _host({
  required AssetBundle bundle,
  MinaExpression expression = MinaExpression.normal,
  bool disableAnimations = false,
  bool tickerEnabled = true,
  GlobalKey<NavigatorState>? navigatorKey,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) => DefaultAssetBundle(
    bundle: bundle,
    child: MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(disableAnimations: disableAnimations),
      child: TickerMode(enabled: tickerEnabled, child: child!),
    ),
  ),
  home: Scaffold(
    body: Center(
      child: MinaAvatar(
        key: const Key('test-mina'),
        size: 40,
        expression: expression,
        semanticLabel: '秘書ミナからのアドバイス',
      ),
    ),
  ),
);

String _asset(WidgetTester tester, {String key = 'mina-portrait'}) {
  final image = tester.widget<Image>(find.byKey(Key(key), skipOffstage: false));
  final provider = image.image;
  return ((provider is ResizeImage ? provider.imageProvider : provider)
          as AssetImage)
      .assetName;
}

double _displacement(WidgetTester tester) {
  final motion = tester.widget<Transform>(
    find.byKey(const Key('mina-portrait-motion'), skipOffstage: false),
  );
  final translation = motion.transform.getTranslation();
  return translation.length;
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 50),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 2),
);

Future<void> _waitForBlinkImage(WidgetTester tester) async {
  final context = tester.element(find.byKey(const Key('test-mina')));
  await tester.runAsync(
    () => precacheImage(
      ResizeImage.resizeIfNeeded(
        120,
        null,
        AssetImage(
          'assets/images/mina_blink.png',
          bundle: DefaultAssetBundle.of(context),
        ),
      ),
      context,
      onError: (_, _) {},
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'expression changes nod while the frame and semantic label stay fixed',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final bundle = _PortraitBundle();
        await tester.pumpWidget(_host(bundle: bundle));
        final frame = tester.getRect(find.byKey(const Key('test-mina')));
        await tester.pump(const Duration(milliseconds: 100));
        expect(_displacement(tester), greaterThan(0));
        expect(tester.getRect(find.byKey(const Key('test-mina'))), frame);
        await _settle(tester);
        for (final expression in MinaExpression.values.skip(1)) {
          await tester.pumpWidget(
            _host(bundle: bundle, expression: expression),
          );
          expect(_asset(tester), expression.assetPath);
          await tester.pump(const Duration(milliseconds: 100));
          expect(_displacement(tester), greaterThan(0));
          expect(tester.getRect(find.byKey(const Key('test-mina'))), frame);
          expect(find.bySemanticsLabel('秘書ミナからのアドバイス'), findsOneWidget);
          await _settle(tester);
          expect(_displacement(tester), closeTo(0, .001));
          expect(tester.binding.hasScheduledFrame, isFalse);
        }
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'normal blinks briefly while expressive portraits retain their eyes',
    (tester) async {
      final bundle = _PortraitBundle();
      await tester.pumpWidget(_host(bundle: bundle));
      await _waitForBlinkImage(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(_asset(tester), 'assets/images/mina_blink.png');
      await tester.pump(const Duration(milliseconds: 120));
      expect(_asset(tester), MinaExpression.normal.assetPath);
      await _settle(tester);
      for (final expression in MinaExpression.values.skip(1)) {
        await tester.pumpWidget(_host(bundle: bundle, expression: expression));
        await tester.pump(const Duration(seconds: 5));
        expect(_asset(tester), expression.assetPath);
        await _settle(tester);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion prevents entrance, idle motion and blinking', (
    tester,
  ) async {
    final bundle = _PortraitBundle();
    await tester.pumpWidget(_host(bundle: bundle, disableAnimations: true));
    await tester.pump(const Duration(seconds: 6));
    expect(_displacement(tester), 0);
    expect(_asset(tester), MinaExpression.normal.assetPath);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(_host(bundle: bundle));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_displacement(tester), greaterThan(0));
    await tester.pumpWidget(_host(bundle: bundle, disableAnimations: true));
    expect(_displacement(tester), 0);
    await tester.pump(const Duration(seconds: 6));
    expect(_asset(tester), MinaExpression.normal.assetPath);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'TickerMode hiding cancels a blink and restarts only when visible',
    (tester) async {
      final bundle = _PortraitBundle();
      await tester.pumpWidget(_host(bundle: bundle));
      await _waitForBlinkImage(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(_asset(tester), 'assets/images/mina_blink.png');
      await tester.pumpWidget(_host(bundle: bundle, tickerEnabled: false));
      expect(_asset(tester), MinaExpression.normal.assetPath);
      expect(_displacement(tester), 0);
      await tester.pump(const Duration(seconds: 12));
      expect(_displacement(tester), 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(_host(bundle: bundle));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_displacement(tester), greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a covering dialog stops the underlying portrait even on a transparent route',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        _host(bundle: _PortraitBundle(), navigatorKey: navigator),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(_displacement(tester), greaterThan(0));
      unawaited(
        navigator.currentState!.push<void>(
          DialogRoute<void>(
            context: tester.element(find.byKey(const Key('test-mina'))),
            builder: (_) => const AlertDialog(content: Text('確認')),
          ),
        ),
      );
      await _settle(tester);
      expect(_displacement(tester), 0);
      await tester.pump(const Duration(seconds: 6));
      expect(_asset(tester), MinaExpression.normal.assetPath);
      expect(tester.binding.hasScheduledFrame, isFalse);
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_displacement(tester), greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('application suspension freezes gestures until resumed', (
    tester,
  ) async {
    final binding = tester.binding;
    addTearDown(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
    );
    await tester.pumpWidget(_host(bundle: _PortraitBundle()));
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      expect(_displacement(tester), 0);
      expect(_asset(tester), MinaExpression.normal.assetPath);
      expect(binding.hasScheduledFrame, isFalse);
    }
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_displacement(tester), greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'removal during a blink leaves neither callbacks nor active tickers',
    (tester) async {
      await tester.pumpWidget(_host(bundle: _PortraitBundle()));
      await _waitForBlinkImage(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(_asset(tester), 'assets/images/mina_blink.png');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 12));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing expression falls back to the normal portrait', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        bundle: _PortraitBundle(missing: {MinaExpression.anger.assetPath}),
        expression: MinaExpression.anger,
        disableAnimations: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      _asset(tester, key: 'mina-normal-fallback'),
      MinaExpression.normal.assetPath,
    );
    expect(find.byIcon(Icons.support_agent), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing normal portrait retains a labelled icon fallback', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _host(
          bundle: _PortraitBundle(
            missing: {
              MinaExpression.sorrow.assetPath,
              MinaExpression.normal.assetPath,
            },
          ),
          expression: MinaExpression.sorrow,
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.support_agent), findsOneWidget);
      expect(find.bySemanticsLabel('秘書ミナからのアドバイス'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('missing blink image leaves the normal portrait visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(bundle: _PortraitBundle(missing: {'assets/images/mina_blink.png'})),
    );
    await _waitForBlinkImage(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(_asset(tester), MinaExpression.normal.assetPath);
    expect(find.byIcon(Icons.support_agent), findsNothing);
    await _settle(tester);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
