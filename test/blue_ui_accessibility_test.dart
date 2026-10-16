import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/presentation/command_hud.dart';
import 'package:mars_terraforming/presentation/district_location_impact.dart';
import 'package:mars_terraforming/presentation/strategy_widgets.dart';

void main() {
  GameState game() => GameState.initial(DateTime.utc(2026, 10, 16));

  test('all outcome colors remain legible on blue surfaces', () {
    for (final foreground in [
      strategyBlue,
      strategyBenefit,
      strategyWarning,
      strategyDanger,
      strategyMuted,
      strategyText,
    ]) {
      for (final background in [
        strategyPanel,
        strategySurface,
        strategySelected,
      ]) {
        final contrast =
            (foreground.computeLuminance() + .05) /
            (background.computeLuminance() + .05);
        expect(
          contrast,
          greaterThanOrEqualTo(4.5),
          reason: '$foreground on $background',
        );
      }
    }
  });

  testWidgets(
    'industrial adjacency loss uses words, a minus sign and an icon',
    (tester) async {
      final state = game()..research.add('urban_planning');
      const housing = DistrictState(
        cityId: 'earth_delta',
        plotIndex: 2,
        districtId: 'housing',
      );
      state.districts[housing.key] = housing;
      final preview = state.districtPreview('earth_delta', 3, 'industry');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 250,
              child: ColoredBox(
                color: strategySurface,
                child: SingleChildScrollView(
                  child: DistrictLocationImpact(
                    game: state,
                    cityId: 'earth_delta',
                    plotIndex: 3,
                    preview: preview,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final negative = find.text('税収 -3ドル/分');
      expect(negative, findsOneWidget);
      expect(tester.widget<Text>(negative).style!.color, strategyDanger);
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
      expect(find.textContaining('＋ 地形'), findsNothing);
      await tester.tap(find.byKey(const Key('location-impact-explanation')));
      await tester.pumpAndSettle();
      expect(find.text('区画 3 · 住宅地区 Lv.1'), findsOneWidget);
      expect(find.textContaining('辺を共有する最大6区画'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('paused locations explain why no effect is applied', (
    tester,
  ) async {
    final state = game()..facilities['factory'] = false;
    final preview = state.districtPreview('earth_delta', 0, 'housing');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DistrictLocationImpact(
            game: state,
            cityId: 'earth_delta',
            plotIndex: 0,
            preview: preview,
          ),
        ),
      ),
    );
    expect(find.text('設備休止中 · 再開すると効果が有効'), findsOneWidget);
    expect(find.text('追加効果なし'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('deficit HUD remains explicit in a small enlarged landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = game();
    expect(state.netPerMinute, lessThan(0));
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: Column(
              children: [
                CommandHud(
                  game: state,
                  devTools: true,
                  busy: false,
                  onAdvance: () {},
                  onAdvanceDuration: (_) {},
                  onOpenResources: () => opened = true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('毎分収支 · 赤字'), findsOneWidget);
    expect(
      find.textContaining('${signedDollars(state.netPerMinute)}/分'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('open-resources')));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });
}
