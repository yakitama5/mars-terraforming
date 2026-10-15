import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/presentation/investment_comparison.dart';
import 'package:mars_terraforming/presentation/strategy_widgets.dart';

void main() {
  for (final size in [const Size(568, 320), const Size(844, 390)]) {
    testWidgets(
      'investment differences stay directional and read-only at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final game = GameState.initial(DateTime.utc(2026, 10, 15));
        game.research.addAll(['urban_planning', 'automated_fabrication']);
        const district = DistrictState(
          cityId: 'earth_delta',
          plotIndex: 0,
          districtId: 'housing',
        );
        game.districts[district.key] = district;
        const upgrade = InvestmentCandidate(
          cityId: 'earth_delta',
          plotIndex: 0,
          districtId: 'housing',
          targetLevel: 2,
        );
        const expansion = InvestmentCandidate(
          cityId: 'earth_highland',
          plotIndex: 12,
          districtId: 'housing',
          targetLevel: 1,
        );
        final before = jsonEncode(game.toJson());
        Future<void> draw(
          InvestmentCandidate saved,
          InvestmentCandidate current,
        ) => tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
            home: Scaffold(
              body: InvestmentComparison(
                game: game,
                saved: saved,
                current: current,
              ),
            ),
          ),
        );
        String difference(String id) => tester
            .widget<Text>(find.byKey(Key('investment-difference-$id')))
            .data!;
        final extraCost =
            expansion.preview(game).cost - upgrade.preview(game).cost;
        final extraTime =
            expansion.preview(game).durationMs -
            upgrade.preview(game).durationMs;
        expect(extraCost, greaterThan(0));
        expect(extraTime, greaterThan(0));
        await draw(upgrade, expansion);
        expect(difference('cost'), '${dollars(extraCost)}高い');
        expect(difference('duration'), '${gameDuration(extraTime)}長い');
        expect(difference('plots'), '1区画多い');
        expect(find.text('費用・工期の内訳'), findsNothing);
        expect(
          tester
              .getTopLeft(
                find.byKey(const Key('investment-difference-summary')),
              )
              .dy,
          lessThan(
            tester
                .getTopLeft(
                  find.byKey(const Key('investment-comparison-saved')),
                )
                .dy,
          ),
        );
        final details = find.byKey(const Key('investment-details-saved'));
        await tester.scrollUntilVisible(
          details.hitTestable(),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(details);
        await tester.pumpAndSettle();
        expect(find.text('費用・工期の内訳'), findsOneWidget);
        expect(jsonEncode(game.toJson()), before);
        await draw(expansion, upgrade);
        expect(difference('cost'), '${dollars(extraCost)}安い');
        expect(difference('duration'), '${gameDuration(extraTime)}短い');
        expect(difference('plots'), '1区画少ない');
        expect(jsonEncode(game.toJson()), before);
        // A finished saved candidate must not leave an obsolete difference visible.
        const completed = DistrictState(
          cityId: 'earth_highland',
          plotIndex: 12,
          districtId: 'housing',
        );
        game.districts[completed.key] = completed;
        await draw(expansion, upgrade);
        expect(
          find.byKey(const Key('investment-difference-unavailable')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('investment-difference-cost')),
          findsNothing,
        );
        expect(find.textContaining('この新設候補は完成済みです'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
