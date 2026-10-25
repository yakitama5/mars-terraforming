import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/infrastructure/file_save_store.dart';
import 'package:mars_terraforming/main.dart';
import 'package:mars_terraforming/presentation/city_facility_palette.dart';
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
        const capturePrefix = String.fromEnvironment(
          'MARS_INTEGRATION_CAPTURE_PREFIX',
        );
        if (capturePrefix.isNotEmpty && !name.startsWith(capturePrefix)) {
          return;
        }
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
        // A pumped frame does not guarantee the native save has finished.
        // Later commands intentionally refuse input while a save is busy.
        await tester.runAsync(() async {
          final waiting = Stopwatch()..start();
          while (controller.busy &&
              waiting.elapsed < const Duration(seconds: 30)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        expect(controller.busy, isFalse, reason: '操作後の保存完了待ち: $key');
        expect(controller.error, isNull);
        await tester.pump();
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
      await tapKey('title-start');
      await tapKey('opening-cinematic-skip');
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
      await tapKey('district-option-housing');
      await tapKey('plot-earth_delta-1');
      await tapKey('confirm-district');
      expect(
        controller.state.firstRunTutorial,
        FirstRunTutorialStep.finishConstruction,
      );
      await tapKey('tutorial-complete-construction');
      expect(controller.state.districtAt('earth_delta', 1)?.level, 1);
      expect(controller.state.netPerMinute, greaterThan(0));
      await tapKey('tutorial-continue-income');
      await tapKey('queue-life_support');
      expect(
        controller.state.firstRunTutorial,
        FirstRunTutorialStep.researchStarted,
      );
      await tapKey('tutorial-finish');
      expect(controller.state.firstRunTutorial, FirstRunTutorialStep.completed);
      expect(find.text('開発ガイド・Tips'), findsOneWidget);
      await tester.tap(find.text('閉じる'));
      await tester.pump(const Duration(milliseconds: 500));
      await tapKey('navigation-0');
      await sceneReady();
      await capture('strategy-ios-earth');
      await tapKey('open-guidance');
      await capture('guidance-ios-guide');
      await tester.tap(find.text('閉じる'));
      await tester.pump(const Duration(milliseconds: 500));

      await tapKey('navigation-2');
      await tapKey('research-reset-zoom');
      expect(find.byKey(const Key('research-detail')), findsNothing);
      await capture('research-mobile-ios-overview');
      await tapKey('research-node-life_support');
      final researchScroll = find
          .descendant(
            of: find.byKey(const Key('research-detail')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('RP生産'),
        100,
        scrollable: researchScroll,
      );
      expect(find.text('必要RP'), findsOneWidget);
      expect(find.text('保有RP'), findsOneWidget);
      expect(find.text('RP生産'), findsOneWidget);
      expect(find.text('科学メモ・出典'), findsNothing);
      await capture('research-mobile-ios-detail');
      await tester.scrollUntilVisible(
        find.byKey(const Key('close-research-detail')),
        -150,
        scrollable: researchScroll,
      );
      await tapKey('close-research-detail');
      expect(find.byKey(const Key('research-detail')), findsNothing);
      await capture('strategy-ios-research');
      expect(
        controller.state.plans.where((plan) => plan.taskId == 'life_support'),
        hasLength(1),
      );
      // Open each destination through actual public commands. The moon is a
      // developed staging base before a probe opens the Mars route.
      await controller.command((engine) {
        void command(String? reason) {
          if (reason != null) throw StateError(reason);
        }

        void until(bool Function() condition) {
          for (var event = 0; !condition(); event++) {
            if (event > 500) throw StateError('月面開発の検証が進みません');
            final running = engine.state.plans.where(
              (plan) =>
                  plan.status == 'running' &&
                  engine.state.facilities[plan.definition.facilityId] == true,
            );
            if (running.isEmpty) throw StateError('月面開発が停止しました');
            final next = running
                .map((plan) => plan.remainingMs)
                .reduce((a, b) => a < b ? a : b);
            engine.advanceBy(Duration(milliseconds: next));
          }
        }

        void job(String id) {
          command(engine.enqueue(id));
          final plan = engine.state.plans.last;
          final ahead = engine.state
              .upcomingPlansFor(plan.definition.facilityId)
              .where((other) => other.id != plan.id)
              .firstOrNull;
          if (ahead != null) {
            command(
              engine.reorderPlan(
                plan.id,
                relativeToPlanId: ahead.id,
                before: true,
              ),
            );
          }
          until(() => plan.isFinished);
        }

        command(engine.enqueue('factory_contract', repeats: null));
        job('launch_contract');
        expect(engine.state.planetUnlocked('moon'), isTrue);
        expect(engine.state.planetUnlocked('mars'), isFalse);
        for (var supply = 0; supply < 2; supply++) {
          job('habitat_kit');
          job('moon_delivery');
        }
        for (final (plot, district) in [
          (2, 'moon_outpost'),
          (3, 'moon_spaceport'),
        ]) {
          command(engine.enqueueDistrict('moon_south_pole', plot, district));
          final plan = engine.state.plans.last;
          until(() => plan.isFinished);
        }
        return null;
      });
      await tapKey('navigation-0');
      await tapKey('select-planet-moon');
      await sceneReady();
      await capture('space-ios-moon');
      await tapKey('open-city');
      await sceneReady();
      await capture('space-ios-moon-base');
      await controller.command((engine) {
        final reason = engine.enqueue('mars_probe');
        if (reason != null) return reason;
        final probe = engine.state.plans.last;
        engine.advanceBy(const Duration(minutes: 15));
        expect(probe.isFinished, isTrue);
        final contract = engine.state.currentPlanFor('factory')!;
        final cancel = engine.cancelQueued(contract.id);
        if (cancel != null) return cancel;
        engine.advanceBy(Duration(milliseconds: contract.remainingMs));
        return null;
      });
      expect(controller.state.planetUnlocked('mars'), isTrue);
      await tapKey('navigation-0');
      await tapKey('select-planet-earth');
      await tapKey('navigation-3');
      await controller.command((engine) {
        engine.enqueue('factory_contract', repeats: null);
        engine.enqueue('habitat_kit');
        engine.enqueue('mars_delivery');
        return null;
      });
      await tester.pump(const Duration(milliseconds: 500));
      final factoryRun = controller.state.currentPlanFor('factory')!;
      final kit = controller.state.plans.firstWhere(
        (p) => p.taskId == 'habitat_kit' && !p.isFinished,
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
      expect(
        tester
            .widget<CityFacilityPalette>(find.byType(CityFacilityPalette))
            .districts
            .map((district) => district.id),
        ['housing', 'solar'],
      );
      await capture('facility-unlocks-ios-initial');
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
      await controller.command((engine) {
        expect(
          engine.reorderPlan(
            home.id,
            relativeToPlanId: factoryRun.id,
            before: true,
          ),
          isNull,
        );
        final current = engine.state.currentPlanFor('factory')!;
        expect(current.id, factoryRun.id);
        engine.advanceBy(Duration(milliseconds: current.remainingMs));
        return null;
      });
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.widget<CityScene>(find.byType(CityScene)).plots[12].workState,
        SceneWorkState.building,
        reason: jsonEncode({
          'money': controller.state.money,
          'home': home.toJson(),
          'factory': controller.state
              .upcomingPlansFor('factory')
              .map((plan) => plan.toJson())
              .toList(),
        }),
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
        contains('拠点 · 完成 2/25区画 · 総Lv.2'),
      );
      expect(
        tester.widget<CityScene>(find.byType(CityScene)).plots[12].level,
        1,
      );
      await capture('strategy-ios-city');
      await capture('terrain-ios-completed');

      // A completed neighboring campus changes both tax and research speed.
      // The next energy branch is discovered from its entry technology.
      // Spend the RP already produced by the real lab during this route.
      await controller.command((engine) {
        expect(engine.unlockResearch('deployable_solar_arrays'), isNull);
        expect(engine.enqueue('urban_planning'), isNull);
        return null;
      });
      expect(controller.state.research, contains('deployable_solar_arrays'));
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
      expect(
        tester
            .widget<CityFacilityPalette>(find.byType(CityFacilityPalette))
            .districts
            .map((district) => district.id),
        containsAll(['campus', 'industry']),
      );
      expect(
        find.byKey(const Key('district-option-space_elevator')),
        findsNothing,
      );
      await capture('facility-unlocks-ios-urban');
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
      // A separate late-game visual fixture supplies only knowledge and budget;
      // construction, its queue occupation and the operating discount are real.
      await controller.command((engine) {
        engine.state.research.addAll([
          'orbital_assembly',
          'composite_shielding',
        ]);
        engine.state.money = 500000;
        final plot = List.generate(25, (index) => index).firstWhere(
          (index) =>
              engine.state.districtAt('earth_delta', index) == null &&
              engine.state.districtPlanAt('earth_delta', index) == null,
        );
        final reason = engine.enqueueDistrict(
          'earth_delta',
          plot,
          'space_elevator',
        );
        if (reason != null) return reason;
        final elevator = engine.state.plans.last;
        final ahead = engine.state
            .upcomingPlansFor('factory')
            .where((plan) => plan.id != elevator.id)
            .firstOrNull;
        if (ahead != null) {
          final move = engine.reorderPlan(
            elevator.id,
            relativeToPlanId: ahead.id,
            before: true,
          );
          if (move != null) return move;
        }
        engine.advanceBy(const Duration(hours: 36));
        expect(elevator.isFinished, isTrue);
        expect(engine.state.districtCount('space_elevator'), 1);
        expect(engine.state.launchCostReductionPercent, 50);
        return null;
      });
      await tapKey('navigation-0');
      await tapKey('select-planet-earth');
      await tapKey('navigation-1');
      await sceneReady();
      await capture('space-ios-elevator');
      await controller.save();
      final resumed = GameController(FileSaveStore(directory));
      addTearDown(resumed.dispose);
      await resumed.initialize(startTimer: false);
      expect(resumed.state.cityName('earth_delta'), '蒼海市');
      expect(resumed.state.cityName('mars_arcadia'), '夜明け基地');
      expect(resumed.state.rocketName, 'ひかり');
      expect(resumed.state.firstRunTutorial, FirstRunTutorialStep.completed);
      expect(resumed.state.districtAt('earth_delta', 1)?.level, 1);
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
      expect(resumed.state.districtCount('space_elevator'), 1);
      expect(resumed.state.launchCostReductionPercent, 50);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
