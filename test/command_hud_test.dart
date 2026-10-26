import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/presentation/command_hud.dart';

GameState _game() => GameState.initial(DateTime.utc(2026, 10, 20));

Future<void> _showHud(
  WidgetTester tester,
  GameState game, {
  bool devTools = false,
  Size size = const Size(873, 393),
  double textScale = 1,
  VoidCallback? onOpenResources,
  VoidCallback? onAdvance,
  ValueChanged<Duration>? onAdvanceDuration,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: const EdgeInsets.fromLTRB(40, 0, 24, 20),
            textScaler: TextScaler.linear(textScale),
          ),
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: CommandHud(
                game: game,
                devTools: devTools,
                busy: false,
                onAdvance: onAdvance ?? () {},
                onAdvanceDuration: onAdvanceDuration ?? (_) {},
                onOpenResources: onOpenResources ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

String _value(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('HUD shows storage limits, population and research capacity', (
    tester,
  ) async {
    final state = _game();
    state.researchPointUnits =
        24 * GameState.researchPointScale + GameState.researchPointScale ~/ 2;
    await _showHud(tester, state);
    expect(_value(tester, 'hud-research-points'), startsWith('24.5/'));
    expect(_value(tester, 'hud-population'), '${state.totalPopulation}人');
    expect(_value(tester, 'hud-research-rate'), endsWith(' RP/時'));
    expect(find.byKey(const Key('hud-researchers')), findsNothing);
    expect(find.byKey(const Key('hud-industrial-workers')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('facility suspension changes capacity without a staff control', (
    tester,
  ) async {
    final state = _game();
    await _showHud(tester, state);
    final activeRate = _value(tester, 'hud-research-rate');
    state.facilities['lab'] = false;
    await _showHud(tester, state);
    expect(_value(tester, 'hud-research-rate'), isNot(activeRate));
    expect(_value(tester, 'hud-research-rate'), '0.0 RP/時');
    expect(_value(tester, 'hud-population'), '${state.totalPopulation}人');
    expect(tester.takeException(), isNull);
  });

  for (final devTools in [false, true]) {
    for (final size in [const Size(873, 393), const Size(568, 320)]) {
      testWidgets(
        'all key resources fit $size with DEV=$devTools and large text',
        (tester) async {
          final state = _game()
            ..money = 987654321012
            ..researchPointUnits = 9876543210 * GameState.researchPointScale;
          await _showHud(
            tester,
            state,
            devTools: devTools,
            size: size,
            textScale: 1.6,
          );
          for (final key in [
            'money',
            'hud-research-points',
            'hud-population',
            'hud-research-rate',
          ]) {
            final finder = find.byKey(Key(key));
            expect(finder, findsOneWidget);
            final richText = find.descendant(
              of: finder,
              matching: find.byType(RichText),
            );
            expect(richText, findsOneWidget);
            final paragraph = tester.renderObject<RenderParagraph>(richText);
            expect(paragraph.didExceedMaxLines, isFalse);
            final center = paragraph.localToGlobal(
              paragraph.size.center(Offset.zero),
            );
            expect(center.dx, inInclusiveRange(40, size.width - 24));
            expect(center.dy, inInclusiveRange(0, 64));
          }
          expect(_value(tester, 'hud-research-points'), startsWith('98.7億/'));
          expect(_value(tester, 'money'), startsWith('9876.5億/'));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('compact HUD keeps resource and time actions reachable', (
    tester,
  ) async {
    var resourceOpens = 0;
    var advances = 0;
    Duration? selected;
    await _showHud(
      tester,
      _game(),
      devTools: true,
      onOpenResources: () => resourceOpens++,
      onAdvance: () => advances++,
      onAdvanceDuration: (value) => selected = value,
    );
    await tester.tap(find.byKey(const Key('open-resources')));
    await tester.tap(find.byKey(const Key('advance-time')));
    await tester.tap(find.byKey(const Key('development-time-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開発 +1時間'));
    await tester.pumpAndSettle();
    expect(resourceOpens, 1);
    expect(advances, 1);
    expect(selected, const Duration(hours: 1));
    expect(tester.takeException(), isNull);
  });
}
