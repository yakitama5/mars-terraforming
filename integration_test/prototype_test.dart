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
import 'package:mars_terraforming/rendering/city_scene.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'iOS: globes, parallel development, agency staffing, partnerships, forecasts and save/resume',
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

      await tester.pump(const Duration(seconds: 1));
      await capture('blue-ios-opening');
      await tapKey('opening-next');
      await tapKey('opening-next');
      await tapKey('opening-next');
      for (final (key, value) in [
        ('mission-city-earth_delta', '蒼海市'),
        ('mission-rocket', 'ひかり'),
        ('mission-city-mars_arcadia', '夜明け基地'),
      ]) {
        final field = find.byKey(Key(key));
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
        await tester.pump(const Duration(milliseconds: 300));
      }
      await capture('blue-ios-naming');
      await tapKey('mission-names-save');
      expect(controller.state.openingSeen, isTrue);
      expect(controller.state.cityName('earth_delta'), '蒼海市');
      expect(controller.state.rocketName, 'ひかり');
      await sceneReady();
      await capture('strategy-ios-earth');
      await tapKey('open-guidance');
      await capture('guidance-ios-guide');
      await tester.tap(find.text('閉じる'));
      await tester.pump(const Duration(milliseconds: 500));

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
      await tapKey('forecast-equipment-details');
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
      expect(controller.state.unreadCompletionNotices, isNotEmpty);
      await tapKey('open-completions');
      await capture('guidance-ios-completions');
      await tapKey('mark-completions-read');
      expect(controller.state.unreadCompletionNotices, isEmpty);
      await tester.tap(find.text('閉じる'));
      await tester.pump(const Duration(milliseconds: 500));

      await tapKey('operations-2');
      final branch = find.byKey(const Key('choose-dome'));
      await tester.scrollUntilVisible(
        branch,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tapKey('choose-dome');
      await tapKey('confirm-habitat-choice');

      // Choose a district, then compare real tiles before confirming placement.
      await tapKey('navigation-1');
      await sceneReady();
      await tapKey('district-option-housing');
      // Tap actual projected ground coordinates, not an accessibility label.
      await tester.tap(find.byTooltip('都市全体を表示'));
      await tester.pump(const Duration(milliseconds: 500));
      for (final index in [4, 0, 12]) {
        final map = tester.widget<CityScene>(find.byType(CityScene));
        final geometry = CityTerrain(
          earth: map.earth,
          columns: map.columns,
          rows: map.rows,
          plots: map.plots,
        );
        final projection = CityMapProjection(
          terrain: geometry,
          elevation: CityMapProjection.overviewElevation,
          zoom: CityMapProjection.overviewZoom,
        );
        final screen =
            tester.getTopLeft(find.byType(CityScene)) +
            projection.center(index, tester.getSize(find.byType(CityScene)));
        await tester.tapAt(screen);
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester.widget<CityScene>(find.byType(CityScene)).selectedPlot,
          index,
        );
      }
      await tester.tap(find.byTooltip('選んだ区画を近くから表示'));
      await tester.pump(const Duration(milliseconds: 500));
      await capture('terrain-ios-before');
      await tapKey('confirm-district');
      final home = controller.state.districtPlanAt('earth_delta', 12)!;
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
        duration: Duration(milliseconds: factoryRun.remainingMs),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.widget<CityScene>(find.byType(CityScene)).plots[12].workState,
        SceneWorkState.building,
      );
      expect(
        tester.widget<CityScene>(find.byType(CityScene)).plots[12].level,
        0,
      );
      await capture('terrain-ios-construction');
      await controller.advanceForDevelopment(
        duration: const Duration(minutes: 15),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        controller.state.districtAt('earth_delta', 12)?.districtId,
        'housing',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('city-development-summary')))
            .data,
        contains('拠点 · 完成 1/25区画 · 総Lv.1'),
      );
      expect(
        tester.widget<CityScene>(find.byType(CityScene)).plots[12].level,
        1,
      );
      await capture('strategy-ios-city');
      await capture('terrain-ios-completed');

      // A completed neighboring campus changes both tax and research speed.
      await controller.command((engine) => engine.enqueue('urban_planning'));
      await controller.advanceForDevelopment(
        duration: const Duration(minutes: 10),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.state.research, contains('urban_planning'));
      // The first urban research unlocks housing improvements without automation.
      await tapKey('plot-earth_delta-12');
      await tapKey('confirm-district');
      final upgrade = controller.state.districtPlanAt('earth_delta', 12)!;
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
      expect(controller.state.districtAt('earth_delta', 12)!.level, 2);
      expect(
        controller.state.research,
        isNot(contains('automated_fabrication')),
      );

      expect(
        tester.widget<CityScene>(find.byType(CityScene)).plots[12].level,
        2,
      );
      await capture('terrain-ios-upgraded');
      await tapKey('city-change-facility');
      await tapKey('district-option-campus');
      await tapKey('plot-earth_delta-7');
      final estimate = controller.state.districtPreview(
        'earth_delta',
        7,
        'campus',
      );
      final researchBefore = controller.state.researchBonusPercent;
      final taxBefore = controller.state.taxPerMinute;
      expect(estimate.researchBonusDelta, greaterThan(0));
      expect(estimate.taxDeltaPerMinute, greaterThan(0));
      await capture('strategy-ios-adjacency');
      await tapKey('confirm-district');
      final campus = controller.state.districtPlanAt('earth_delta', 7)!;
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
      await capture('district-ios-neighborhood');
      await tester.tap(find.byTooltip('都市全体を表示'));
      await tapKey('city-inspector-toggle');
      await capture('terrarium-ios-whole');
      await tapKey('city-inspector-toggle');
      await tester.tap(find.byTooltip('選んだ区画を近くから表示'));
      await tester.pump(const Duration(milliseconds: 400));
      await tapKey('city-inspector-toggle');
      await tester.tap(find.byTooltip('都市地図を拡大'));
      await tester.pump(const Duration(milliseconds: 400));
      await capture('diorama-ios-close');
      await tapKey('city-inspector-toggle');
      final beforeComparison = jsonEncode(controller.state.toJson());
      await tapKey('city-open-details');
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
      await tapKey('plot-earth_highland-12');
      await tapKey('city-open-details');
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
      await tapKey('district-option-mars_habitat');
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
      await tapKey('open-completions');
      await tapKey('completion-open-endings');
      await tapKey('play-ending-dome_habitat');
      await capture('blue-ios-colony-ending');
      final endingSnapshot = jsonEncode(controller.state.toJson());
      await tapKey('ending-next');
      await tapKey('ending-next');
      await tapKey('ending-next');
      expect(jsonEncode(controller.state.toJson()), endingSnapshot);
      await tester.tap(find.text('閉じる'));
      await tester.pump(const Duration(milliseconds: 500));
      await tapKey('navigation-0');
      await sceneReady();
      await capture('strategy-ios-settlement');
      // Choose a real one-time partnership, then develop and reassign staff.
      await tapKey('navigation-4');
      await capture('agency-ios-overview');
      await tapKey('staff-research-less');
      await tapKey('confirm-staff-allocation');
      expect(controller.state.researchers, 5);
      await tapKey('agency-section-partnerships');
      await tapKey('partnership-research_exchange-funding');
      await tapKey('confirm-partnership-research_exchange-funding');
      expect(
        controller.state.partnershipChoices['research_exchange'],
        'funding',
      );
      await capture('agency-ios-partnerships');
      await tapKey('agency-section-staff');
      await tapKey('queue-train_specialists');
      await controller.advanceForDevelopment(
        duration: const Duration(minutes: 5),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.state.specialistCount, 14);
      expect(controller.state.researchers, 5);
      await tapKey('navigation-4');
      await capture('agency-ios-staff');
      await controller.save();
      final resumed = GameController(FileSaveStore(directory));
      addTearDown(resumed.dispose);
      await resumed.initialize(startTimer: false);
      expect(resumed.state.cityName('earth_delta'), '蒼海市');
      expect(resumed.state.cityName('mars_arcadia'), '夜明け基地');
      expect(resumed.state.rocketName, 'ひかり');
      expect(
        resumed.state.districtAt('earth_delta', 12)?.districtId,
        'housing',
      );
      expect(
        resumed.state.districtAt('mars_arcadia', 12)?.districtId,
        'mars_habitat',
      );
      expect(resumed.state.marsResidents, 24);
      expect(resumed.state.specialistCount, 14);
      expect(resumed.state.researchers, 5);
      expect(resumed.state.partnershipChoices['research_exchange'], 'funding');
      expect(resumed.state.claimedRewards, controller.state.claimedRewards);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
