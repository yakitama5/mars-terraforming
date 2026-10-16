import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mars_terraforming/presentation/mission_adviser.dart';
import 'package:mars_terraforming/presentation/strategy_colors.dart';

const _portraitSize = 96.0;
const _blinkAsset = 'assets/images/mina_blink.png';
const _galleryKey = Key('mina-gallery');
const _toggleKey = Key('mina-gallery-motion-toggle');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'iOS: five Mina portraits, finite gestures, blink and reduced motion',
    (tester) async {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      // Rasterize only explicitly pumped frames, so the short blink remains on
      // screen while the native screenshot service captures that exact frame.
      final previousPolicy = binding.framePolicy;
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
      final reduceMotion = ValueNotifier(true);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        reduceMotion.dispose();
        binding.framePolicy = previousPolicy;
      });

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(useMaterial3: true).copyWith(
            scaffoldBackgroundColor: strategyBackground,
            textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: 'NotoSansJP',
            ),
          ),
          home: ValueListenableBuilder<bool>(
            valueListenable: reduceMotion,
            builder: (context, disabled, _) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: disabled),
              child: _MinaGallery(
                reduceMotion: disabled,
                onToggle: () => reduceMotion.value = !reduceMotion.value,
              ),
            ),
          ),
        ),
      );

      final imageErrors = <Object>[];
      final galleryContext = tester.element(find.byKey(_galleryKey));
      await tester.runAsync(() async {
        for (final asset in [
          ...MinaExpression.values.map((expression) => expression.assetPath),
          _blinkAsset,
        ]) {
          await precacheImage(
            ResizeImage(AssetImage(asset), width: (_portraitSize * 3).round()),
            galleryContext,
            onError: (error, _) => imageErrors.add(error),
          );
        }
      });
      expect(imageErrors, isEmpty, reason: '表情画像と瞬き画像を全て読み込めること');
      await tester.pump();

      Finder avatar(MinaExpression expression) =>
          find.byKey(Key('mina-gallery-avatar-${expression.name}'));
      Finder portrait(MinaExpression expression) => find.descendant(
        of: avatar(expression),
        matching: find.byKey(const Key('mina-portrait')),
      );
      String displayedAsset(MinaExpression expression) {
        final provider = tester.widget<Image>(portrait(expression)).image;
        final original = provider is ResizeImage
            ? provider.imageProvider
            : provider;
        return (original as AssetImage).assetName;
      }

      Transform movement(MinaExpression expression) => tester.widget<Transform>(
        find.descendant(
          of: avatar(expression),
          matching: find.byKey(const Key('mina-portrait-motion')),
        ),
      );
      void expectResting() {
        for (final expression in MinaExpression.values) {
          final transform = movement(expression).transform;
          expect(transform.entry(0, 3), closeTo(0, 0.000001));
          expect(transform.entry(1, 3), closeTo(0, 0.000001));
          expect(displayedAsset(expression), expression.assetPath);
        }
      }

      Future<void> capture(String name) async {
        // Allow the last submitted frame to reach the native surface without
        // pumping another frame that could replace a 120 ms blink.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await binding.takeScreenshot(name);
      }

      Future<Uint8List> galleryPixels() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_galleryKey),
        );
        final pixels = await tester.runAsync(() async {
          final frame = await boundary.toImage(pixelRatio: 1);
          try {
            final bytes = await frame.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            expect(bytes, isNotNull);
            return Uint8List.fromList(bytes!.buffer.asUint8List());
          } finally {
            frame.dispose();
          }
        });
        return pixels!;
      }

      for (final expression in MinaExpression.values) {
        final raw = find.descendant(
          of: portrait(expression),
          matching: find.byType(RawImage),
        );
        expect(raw, findsOneWidget);
        expect(tester.widget<RawImage>(raw).image, isNotNull);
        expect(displayedAsset(expression), expression.assetPath);
      }
      expect(find.byKey(const Key('mina-normal-fallback')), findsNothing);
      expect(find.byIcon(Icons.support_agent), findsNothing);
      expect(tester.takeException(), isNull);
      expectResting();
      await capture('mina-ios-five-expressions');

      await tester.tap(find.byKey(_toggleKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      for (final expression in MinaExpression.values) {
        expect(movement(expression).transform.entry(1, 3), greaterThan(0));
      }
      await capture('mina-ios-finite-gesture');
      await tester.pump(const Duration(milliseconds: 600));
      expectResting();

      var foundBlink = false;
      for (var attempt = 0; attempt < 350; attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (displayedAsset(MinaExpression.normal) == _blinkAsset) {
          foundBlink = true;
          break;
        }
      }
      expect(foundBlink, isTrue, reason: '通常表情のアイドル瞬きを実際に描画すること');
      expect(
        tester
            .widget<RawImage>(
              find.descendant(
                of: portrait(MinaExpression.normal),
                matching: find.byType(RawImage),
              ),
            )
            .image,
        isNotNull,
      );
      await capture('mina-ios-normal-blink');

      // Turn reduced motion on while the blink/gesture is in progress. It must
      // reopen normal eyes and stop movement immediately, then stay unchanged
      // beyond the next five-second idle interval.
      await tester.tap(find.byKey(_toggleKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expectResting();
      final stillPixels = await galleryPixels();
      await capture('mina-ios-reduced-motion');
      await tester.pump(const Duration(seconds: 6));
      expectResting();
      expect(await galleryPixels(), orderedEquals(stillPixels));
      expect(find.byKey(const Key('mina-normal-fallback')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _MinaGallery extends StatelessWidget {
  const _MinaGallery({required this.reduceMotion, required this.onToggle});

  final bool reduceMotion;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: RepaintBoundary(
          key: _galleryKey,
          child: ColoredBox(
            color: strategyBackground,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '秘書ミナ · 表情と動作の確認',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      for (final expression in MinaExpression.values)
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: MinaAvatar(
                                  key: Key(
                                    'mina-gallery-avatar-${expression.name}',
                                  ),
                                  expression: expression,
                                  size: _portraitSize,
                                  semanticLabel: 'ミナの${_label(expression)}の表情',
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(_label(expression)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: _toggleKey,
                    onPressed: onToggle,
                    icon: Icon(reduceMotion ? Icons.play_arrow : Icons.pause),
                    label: Text(reduceMotion ? '動きを再生' : '動きを止める'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  String _label(MinaExpression expression) => switch (expression) {
    MinaExpression.normal => '通常',
    MinaExpression.joy => '喜',
    MinaExpression.anger => '怒',
    MinaExpression.sorrow => '哀',
    MinaExpression.delight => '楽',
  };
}
