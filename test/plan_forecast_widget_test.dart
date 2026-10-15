import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/main.dart';
import 'package:mars_terraforming/presentation/strategy_widgets.dart';

class _ForecastSave implements SaveRepository {
  Map<String, dynamic>? data;
  int writes = 0;
  bool conflict = false;
  @override
  Future<SaveLoadResult> load() async =>
      SaveLoadResult(data: data, recovered: false, generation: 1);
  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    writes++;
    if (conflict) throw const SaveConflictException('別の保存元が更新しました');
    data = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  }
}

void main() {
  for (final size in [const Size(844, 390), const Size(1280, 800)]) {
    testWidgets('forecast is read-only and refreshes only on request at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _ForecastSave();
      final controller = GameController(
        repository,
        devTools: true,
        now: () => DateTime.utc(2026, 10, 13, 15),
      );
      try {
        await controller.initialize(startTimer: false);
        await controller.command((engine) {
          engine.enqueue('factory_contract', repeats: 3);
          engine.enqueue('life_support');
          return null;
        });
        await tester.pumpWidget(
          MarsApp(
            controller: controller,
            sceneBuilder: (_, _, _, _) => const SizedBox.expand(),
          ),
        );
        await tester.tap(find.byKey(const Key('navigation-3')));
        await tester.pumpAndSettle();
        final before = jsonEncode(controller.state.toJson());
        final writesBefore = repository.writes;
        await tester.tap(find.byKey(const Key('open-plan-forecast')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('close-plan-forecast')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('refresh-plan-forecast')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('forecast-horizon-480')).hitTestable(),
          findsOneWidget,
        );
        expect(jsonEncode(controller.state.toJson()), before);
        expect(repository.writes, writesBefore);
        final originalQuote = tester
            .widget<StrategyFact>(find.byKey(const Key('forecast-money')))
            .value;

        // The live world keeps advancing while the displayed quote is retained.
        await controller.advanceForDevelopment(
          duration: const Duration(minutes: 10),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('forecast-stale')), findsOneWidget);
        expect(
          tester
              .widget<StrategyFact>(find.byKey(const Key('forecast-money')))
              .value,
          originalQuote,
        );
        final advanced = jsonEncode(controller.state.toJson());
        final writesAfterAdvance = repository.writes;
        await tester.tap(find.byKey(const Key('refresh-plan-forecast')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('forecast-stale')), findsNothing);
        expect(
          tester
              .widget<StrategyFact>(find.byKey(const Key('forecast-money')))
              .value,
          startsWith('${dollars(controller.state.money)} → '),
        );
        expect(jsonEncode(controller.state.toJson()), advanced);
        expect(repository.writes, writesAfterAdvance);

        for (final minutes in [30, 480]) {
          await tester.tap(find.byKey(Key('forecast-horizon-$minutes')));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<ChoiceChip>(
                  find.byKey(Key('forecast-horizon-$minutes')),
                )
                .selected,
            isTrue,
          );
          expect(jsonEncode(controller.state.toJson()), advanced);
          expect(repository.writes, writesAfterAdvance);
        }
        await tester.drag(
          find.byKey(const Key('plan-forecast-scroll')),
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('close-plan-forecast')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('refresh-plan-forecast')).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('close-plan-forecast')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('plan-forecast-scroll')), findsNothing);
        expect(jsonEncode(controller.state.toJson()), advanced);
        expect(repository.writes, writesAfterAdvance);
        expect(tester.takeException(), isNull);
      } finally {
        controller.dispose();
      }
    });
  }

  for (final alreadyStale in [false, true]) {
    testWidgets(
      'forecast remains closable after save conflict, stale=$alreadyStale',
      (tester) async {
        tester.view.physicalSize = const Size(844, 390);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _ForecastSave();
        final controller = GameController(
          repository,
          devTools: true,
          now: () => DateTime.utc(2026, 10, 13),
        );
        try {
          await controller.initialize(startTimer: false);
          await tester.pumpWidget(
            MarsApp(
              controller: controller,
              sceneBuilder: (_, _, _, _) => const SizedBox.expand(),
            ),
          );
          await tester.tap(find.byKey(const Key('navigation-3')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('open-plan-forecast')));
          await tester.pumpAndSettle();
          if (alreadyStale) {
            await controller.advanceForDevelopment();
            await tester.pumpAndSettle();
            expect(find.byKey(const Key('forecast-stale')), findsOneWidget);
          }
          repository.conflict = true;
          await controller.save();
          await tester.pumpAndSettle();
          expect(controller.engine, isNull);
          expect(find.byKey(const Key('forecast-unavailable')), findsOneWidget);
          expect(find.byKey(const Key('forecast-money')), findsNothing);
          expect(
            tester
                .widget<TextButton>(
                  find.byKey(const Key('refresh-plan-forecast')),
                )
                .onPressed,
            isNull,
          );
          for (final minutes in [30, 60, 480]) {
            final chip = find.byKey(Key('forecast-horizon-$minutes'));
            expect(tester.widget<ChoiceChip>(chip).onSelected, isNull);
            await tester.tap(chip);
          }
          await tester.tap(find.byKey(const Key('refresh-plan-forecast')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('close-plan-forecast')).hitTestable(),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const Key('close-plan-forecast')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('forecast-unavailable')), findsNothing);
          expect(find.textContaining('保存内容の競合を検出'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          controller.dispose();
        }
      },
    );
  }

  testWidgets('a future plan explains an unlimited reservation ahead of it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = GameController(
      _ForecastSave(),
      now: () => DateTime.utc(2026, 10, 13),
    );
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    await controller.command((engine) {
      engine.enqueue('factory_contract', repeats: null);
      engine.enqueueDistrict('earth_delta', 0, 'housing');
      return null;
    });
    final house = controller.state.districtPlanAt('earth_delta', 0)!;
    final contract = controller.state.currentPlanFor('factory')!;
    await tester.pumpWidget(
      MarsApp(
        controller: controller,
        sceneBuilder: (_, _, _, _) => const SizedBox.expand(),
      ),
    );
    await tester.tap(find.byKey(const Key('navigation-3')));
    await tester.pumpAndSettle();
    final warning = find.byKey(Key('unlimited-before-${house.id}'));
    await tester.scrollUntilVisible(
      warning,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.widget<Text>(warning).data,
      contains('無期限反復が続く間、この予約は開始しません'),
    );
    final move = find.byKey(Key('queue-up-${house.id}'));
    await tester.ensureVisible(move);
    await tester.tap(move);
    await tester.pumpAndSettle();
    expect(warning, findsNothing);
    expect(controller.state.currentPlanFor('factory'), same(contract));
    expect(controller.state.upcomingPlansFor('factory').first.id, house.id);
    expect(tester.takeException(), isNull);
  });
}
