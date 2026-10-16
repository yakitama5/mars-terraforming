import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mars_terraforming/presentation/mission_adviser.dart';
import 'package:mars_terraforming/presentation/strategy_colors.dart';

const _portraitSize = 220.0;
const _avatarKey = Key('mina-video-avatar');
const _blinkAsset = 'assets/images/mina_blink.png';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('record Mina expressions and natural blinking in real time', (
    tester,
  ) async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    final previousPolicy = binding.framePolicy;
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final expression = ValueNotifier(MinaExpression.normal);
    final disableMotion = ValueNotifier(true);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      expression.dispose();
      disableMotion.dispose();
      binding.framePolicy = previousPolicy;
    });

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          textTheme: ThemeData.dark().textTheme.apply(
            fontFamily: 'NotoSansJP',
            bodyColor: strategyText,
            displayColor: strategyText,
          ),
        ),
        home: ValueListenableBuilder<bool>(
          valueListenable: disableMotion,
          builder: (context, disabled, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: disabled),
            child: ValueListenableBuilder<MinaExpression>(
              valueListenable: expression,
              builder: (_, current, _) => _CaptureScreen(expression: current),
            ),
          ),
        ),
      ),
    );

    final imageErrors = <Object>[];
    final avatarContext = tester.element(find.byKey(_avatarKey));
    await tester.runAsync(() async {
      for (final asset in [
        ...MinaExpression.values.map((value) => value.assetPath),
        _blinkAsset,
      ]) {
        await precacheImage(
          ResizeImage.resizeIfNeeded(
            (_portraitSize * 3).round(),
            null,
            AssetImage(asset, bundle: DefaultAssetBundle.of(avatarContext)),
          ),
          avatarContext,
          onError: (error, _) => imageErrors.add(error),
        );
      }
    });
    expect(imageErrors, isEmpty, reason: '録画開始前に表情と瞬きの全画像を読み込む');

    final originalAvatarState = tester.state(find.byKey(_avatarKey));
    for (final current in MinaExpression.values) {
      expression.value = current;
      await tester.pump();
      final portrait = find.descendant(
        of: find.byKey(_avatarKey),
        matching: find.byKey(const Key('mina-portrait')),
      );
      final provider = tester.widget<Image>(portrait).image;
      final source = provider is ResizeImage
          ? provider.imageProvider
          : provider;
      expect((source as AssetImage).assetName, current.assetPath);
      final renderedImage = find.descendant(
        of: portrait,
        matching: find.byType(RawImage),
      );
      expect(tester.widget<RawImage>(renderedImage).image, isNotNull);
      expect(tester.state(find.byKey(_avatarKey)), same(originalAvatarState));
    }
    expect(find.byKey(const Key('mina-normal-fallback')), findsNothing);
    expect(find.byIcon(Icons.support_agent), findsNothing);
    expect(tester.takeException(), isNull);
    expression.value = MinaExpression.normal;
    await tester.pump();

    Future<void> waitInRealTime(Duration duration) async {
      await tester.runAsync(() => Future<void>.delayed(duration));
    }

    void markStage() {
      // ignore: avoid_print
      print('MINA_VIDEO_STAGE:${expression.value.name}');
    }

    // The recorder starts at this marker while the portrait is still. Enabling
    // motion afterwards starts its own five-second blink timer from zero.
    // ignore: avoid_print
    print('MINA_VIDEO_READY');
    await waitInRealTime(const Duration(seconds: 3));
    disableMotion.value = false;
    await tester.pump();
    markStage();
    await waitInRealTime(const Duration(seconds: 6));

    for (final current in [
      MinaExpression.joy,
      MinaExpression.anger,
      MinaExpression.sorrow,
      MinaExpression.delight,
    ]) {
      expression.value = current;
      await tester.pump();
      markStage();
      expect(tester.state(find.byKey(_avatarKey)), same(originalAvatarState));
      await waitInRealTime(const Duration(milliseconds: 2500));
    }
    expression.value = MinaExpression.normal;
    await tester.pump();
    markStage();
    await waitInRealTime(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
    // ignore: avoid_print
    print('MINA_VIDEO_DONE');
    // Keep the final portrait on screen while the recorder stops.
    await waitInRealTime(const Duration(seconds: 2));
  }, timeout: const Timeout(Duration(minutes: 2)));
}

class _CaptureScreen extends StatelessWidget {
  const _CaptureScreen({required this.expression});

  final MinaExpression expression;

  @override
  Widget build(BuildContext context) {
    final (label, purpose) = switch (expression) {
      MinaExpression.normal => ('通常', '計画の説明や、日々の案内。'),
      MinaExpression.joy => ('喜び', '一歩進んだ成果を、一緒に喜ぶ。'),
      MinaExpression.anger => ('怒り', '大切な注意を、きちんと伝える。'),
      MinaExpression.sorrow => ('悲しみ', 'うまくいかない時も、そばで支える。'),
      MinaExpression.delight => ('楽しさ', '新しい挑戦への期待を伝える。'),
    };
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [strategyBackground, strategyPanel]),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MinaAvatar(
                      key: _avatarKey,
                      size: _portraitSize,
                      expression: expression,
                      semanticLabel: 'ミナの$labelの表情',
                    ),
                    const SizedBox(width: 40),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '秘書ミナ',
                            style: TextStyle(fontSize: 18, color: strategyBlue),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(purpose, style: const TextStyle(fontSize: 18)),
                          const SizedBox(height: 28),
                          const Text(
                            'ゲーム内の表示を拡大',
                            style: TextStyle(
                              fontSize: 12,
                              color: strategyMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
