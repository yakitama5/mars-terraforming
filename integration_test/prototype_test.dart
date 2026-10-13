import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/infrastructure/file_save_store.dart';
import 'package:mars_terraforming/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'iOS: globes, research, districts, investment and reservation forecasts, and save/resume',
    (tester) async {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      final directory = await Directory.systemTemp.createTemp(
        'mars-integration-',
      );
      final controller = GameController(
        FileSaveStore(directory),
        devTools: true,
      );
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      addTearDown(() => directory.delete(recursive: true));
      await tester.pumpWidget(MarsApp(controller: controller));

      Future<void> capture(String name) async {
        // The native screenshot service observes the last rasterized frame.
        // Let it present after controller commands instead of only advancing
        // the test clock, which can otherwise capture the preceding state.
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await binding.takeScreenshot(name);
      }

      Future<void> tapKey(String key) async {
        final finder = find.byKey(Key(key));
        if (finder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            finder,
            150,
            scrollable: find.byType(Scrollable).last,
          );
        }
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      }

      Future<void> sceneReady() async {
        for (
          var i = 0;
          i < 60 && find.byType(fs.SceneView).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        await tester.pump(const Duration(seconds: 2));
        expect(find.textContaining('3D表示を開始できませんでした'), findsNothing);
        expect(find.byType(fs.SceneView), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      await sceneReady();
      await capture('strategy-ios-earth');
      await tapKey('navigation-2');
      await tapKey('research-fit');
      await capture('strategy-ios-research');
      await tapKey('queue-life_support');
      await controller.command((engine) {
        engine.enqueue('factory_contract', repeats: null);
        engine.enqueue('habitat_kit');
        engine.enqueue('mars_delivery');
        return null;
      });
      await tester.pump(const Duration(milliseconds: 500));
      final factoryRun = controller.state.currentPlanFor('factory')!;
      final kit = controller.state.plans.firstWhere(
        (p) => p.taskId == 'habitat_kit',
      );
      final move = find.byKey(Key('queue-up-${kit.id}'));
      await tester.scrollUntilVisible(
        move,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tapKey('queue-up-${kit.id}');
      expect(controller.state.currentPlanFor('factory'), factoryRun);
      expect(factoryRun.completedRuns, 0);
      expect(controller.state.upcomingPlansFor('factory'), [kit, factoryRun]);
      await capture('strategy-ios-equipment');
      final beforeForecast = jsonEncode(controller.state.toJson());
      await tester.scrollUntilVisible(
        find.byKey(const Key('open-plan-forecast')),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tapKey('open-plan-forecast');
      await tapKey('forecast-horizon-480');
      await capture('forecast-ios-summary');
      await tester.drag(
        find.byKey(const Key('plan-forecast-scroll')),
        const Offset(0, -420),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(const Key('refresh-plan-forecast')).hitTestable(),
        findsOneWidget,
      );
      await capture('forecast-ios-equipment');
      await tapKey('refresh-plan-forecast');
      await tapKey('close-plan-forecast');
      expect(jsonEncode(controller.state.toJson()), beforeForecast);

      await controller.advanceForDevelopment(
        duration: const Duration(minutes: 20),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.state.achievements, contains('first_landing'));
      expect(controller.state.marsHabitats, 0);
      await tapKey('operations-2');
      final branch = find.byKey(const Key('choose-dome'));
      await tester.scrollUntilVisible(
        branch,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tapKey('choose-dome');

      // Place an Earth housing district through the actual hex board and preview.
      await tapKey('navigation-1');
      await tapKey('plot-earth_delta-0');
      await tapKey('confirm-district');
      final home = controller.state.districtPlanAt('earth_delta', 0)!;
      expect(home.definition.districtId, 'housing');
      // Move construction ahead of the external contract's future repetitions.
      await controller.command(
        (engine) => engine.reorderPlan(
          home.id,
          relativeToPlanId: factoryRun.id,
          before: true,
        ),
      );
      await controller.advanceForDevelopment(
        duration: const Duration(minutes: 15),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        controller.state.districtAt('earth_delta', 0)?.districtId,
        'housing',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('city-development-summary')))
            .data,
        contains('拠点 · 完成 1/25区画 · 総Lv.1'),
      );
      await capture('strategy-ios-city');

      // A completed neighboring campus changes both tax and research speed.
      await controller.command((engine) => engine.enqueue('urban_planning'));
      await controller.advanceForDevelopment(
        duration: const Duration(minutes: 10),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.state.research, contains('urban_planning'));
      // The first urban research unlocks housing improvements without automation.
      await tapKey('plot-earth_delta-0');
      await tapKey('confirm-district');
      final upgrade = controller.state.districtPlanAt('earth_delta', 0)!;
      expect(upgrade.definition.isDistrictUpgrade, isTrue);
      await controller.command(
        (engine) => engine.reorderPlan(
          upgrade.id,
          relativeToPlanId: factoryRun.id,
          before: true,
        ),
      );
      await controller.advanceForDevelopment(
        duration: const Duration(minutes: 10),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.state.districtAt('earth_delta', 0)!.level, 2);
      expect(
        controller.state.research,
        isNot(contains('automated_fabrication')),
      );

      await tapKey('plot-earth_delta-1');
      await tapKey('district-option-campus');
      final estimate = controller.state.districtPreview(
        'earth_delta',
        1,
        'campus',
      );
      final researchBefore = controller.state.researchBonusPercent;
      final taxBefore = controller.state.taxPerMinute;
      expect(estimate.researchBonusDelta, greaterThan(0));
      expect(estimate.taxDeltaPerMinute, greaterThan(0));
      await capture('strategy-ios-adjacency');
      await tapKey('confirm-district');
      final campus = controller.state.districtPlanAt('earth_delta', 1)!;
      await controller.command(
        (engine) => engine.reorderPlan(
          campus.id,
          relativeToPlanId: factoryRun.id,
          before: true,
        ),
      );
      await controller.advanceForDevelopment(
        duration: const Duration(minutes: 20),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        controller.state.researchBonusPercent,
        researchBefore + estimate.researchBonusDelta,
      );
      expect(
        controller.state.taxPerMinute,
        taxBefore + estimate.taxDeltaPerMinute,
      );

      // Save the existing campus upgrade and inspect a new city's campus.
      // UI comparison must not modify the world, time, or equipment queue.
      final beforeComparison = jsonEncode(controller.state.toJson());
      await tapKey('save-investment');
      await tapKey('city-selector');
      await tester.tap(find.text('高原科学都市').last);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('city-development-summary')))
            .data,
        contains('候補地 · 完成 0/25区画 · 総Lv.0'),
      );
      await tapKey('compare-investments');
      expect(find.text('研究地区 Lv.1 → 2'), findsOneWidget);
      expect(find.text('研究地区 新設 Lv.1'), findsOneWidget);
      expect(find.text('0区画 · 空地を温存'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('investment-comparison-current')),
          matching: find.text('1区画'),
        ),
        findsOneWidget,
      );
      await capture('investment-ios-comparison');
      await tester.drag(
        find.byKey(const Key('investment-comparison-scroll')),
        const Offset(0, -450),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(const Key('close-investment-comparison')).hitTestable(),
        findsOneWidget,
      );
      await capture('investment-ios-comparison-details');
      await tapKey('close-investment-comparison');
      expect(
        find.byKey(const Key('investment-comparison-saved')),
        findsNothing,
      );
      expect(jsonEncode(controller.state.toJson()), beforeComparison);
      expect(
        find.byKey(const Key('confirm-district')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // Planet selection leads into a different city's finite construction plots.
      await tapKey('navigation-0');
      await tester.tap(find.text('火星').first);
      await tester.pump(const Duration(milliseconds: 500));
      await sceneReady();
      await capture('strategy-ios-mars');
      await tapKey('navigation-1');
      await tapKey('plot-mars_arcadia-12');
      await tapKey('confirm-district');
      expect(controller.state.currentPlanFor('mars')!.cityId, 'mars_arcadia');
      await controller.advanceForDevelopment(
        duration: const Duration(hours: 1),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        controller.state.districtAt('mars_arcadia', 12)?.districtId,
        'mars_habitat',
      );
      expect(controller.state.marsHabitats, 1);
      expect(controller.state.marsResidents, 24);
      expect(controller.state.achievements, contains('dome_habitat'));
      await tapKey('navigation-0');
      await sceneReady();
      await capture('strategy-ios-settlement');
      await controller.save();
      final resumed = GameController(FileSaveStore(directory));
      addTearDown(resumed.dispose);
      await resumed.initialize(startTimer: false);
      expect(resumed.state.districtAt('earth_delta', 0)?.districtId, 'housing');
      expect(
        resumed.state.districtAt('mars_arcadia', 12)?.districtId,
        'mars_habitat',
      );
      expect(resumed.state.marsResidents, 24);
      expect(resumed.state.claimedRewards, controller.state.claimedRewards);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
