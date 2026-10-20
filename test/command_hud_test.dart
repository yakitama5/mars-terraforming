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
  testWidgets('HUD shows common RP and used / department staff totals', (
    tester,
  ) async {
    final state = _game();
    state.researchPointUnits =
        24 * GameState.researchPointScale + GameState.researchPointScale ~/ 2;
    await _showHud(tester, state);
    expect(_value(tester, 'hud-research-points'), '24.5 RP');
    expect(_value(tester, 'hud-researchers'), '6/6');
    expect(_value(tester, 'hud-industrial-workers'), '0/6');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'equipment and paid crews are counted once, including suspension',
    (tester) async {
      final state = _game()
        ..developments.add('orbital_gardens')
        ..developmentEnabled['orbital_gardens'] = true
        ..developmentResearchers['orbital_gardens'] = 2;
      state.plans.addAll([
        PlannedTask(id: 'legacy-research', taskId: 'life_support')
          ..status = 'running'
          ..iterationSpecialists = 2,
        PlannedTask(id: 'paid-production', taskId: 'factory_contract')
          ..status = 'running'
          ..iterationSpecialists = 3,
      ]);
      expect(state.labResearchers, 2);
      expect(state.developmentWorkers, 1);
      expect(state.industrialWorkers, 5);
      await _showHud(tester, state);
      expect(_value(tester, 'hud-researchers'), '6/6');
      expect(_value(tester, 'hud-industrial-workers'), '4/6');

      state.facilities['lab'] = false;
      await _showHud(tester, state);
      expect(_value(tester, 'hud-researchers'), '4/6');
      state.facilities['factory'] = false;
      await _showHud(tester, state);
      expect(_value(tester, 'hud-researchers'), '2/6');
      expect(_value(tester, 'hud-industrial-workers'), '3/6');
      expect(tester.takeException(), isNull);
    },
  );

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
            'hud-researchers',
            'hud-industrial-workers',
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
          expect(_value(tester, 'hud-research-points'), '98.7億 RP');
          expect(_value(tester, 'money'), '9876.5億ドル');
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
