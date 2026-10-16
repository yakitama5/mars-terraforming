import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/presentation/landscape_play_hint.dart';

Widget _host({
  bool enabled = true,
  double textScale = 1,
  VoidCallback? onAction,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: LandscapePlayHint(enabled: enabled, child: child!),
  ),
  home: Scaffold(
    key: const Key('game-viewport'),
    body: Center(
      child: FilledButton(
        onPressed: onAction ?? () {},
        child: const Text('ゲームを操作'),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'portrait browser hint is dismissible and leaves the game operable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var actions = 0;
      await tester.pumpWidget(_host(onAction: () => actions++));
      expect(find.byKey(const Key('landscape-play-hint')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('game-viewport'))),
        const Size(390, 844),
      );
      await tester.tap(find.text('ゲームを操作'));
      expect(actions, 1);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pump();
        expect(find.bySemanticsLabel('横向きの案内を閉じる'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
      await tester.tap(find.byKey(const Key('dismiss-landscape-hint')));
      await tester.pump();
      expect(find.byKey(const Key('landscape-play-hint')), findsNothing);
      await tester.tap(find.text('ゲームを操作'));
      expect(actions, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('landscape and native presentation have no hint', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host());
    expect(find.byKey(const Key('landscape-play-hint')), findsNothing);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(_host(enabled: false));
    expect(find.byKey(const Key('landscape-play-hint')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rotation reveals the hint once and a dismissal survives further rotation',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_host());
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      expect(find.byKey(const Key('landscape-play-hint')), findsOneWidget);
      await tester.tap(find.byKey(const Key('dismiss-landscape-hint')));
      await tester.pump();
      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      expect(find.byKey(const Key('landscape-play-hint')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'large text on a small portrait display keeps the close action reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_host(textScale: 1.5));
      final close = find.byKey(const Key('dismiss-landscape-hint'));
      expect(close.hitTestable(), findsOneWidget);
      expect(tester.getRect(close).right, lessThanOrEqualTo(320));
      await tester.tap(close);
      await tester.pump();
      expect(find.byKey(const Key('landscape-play-hint')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
