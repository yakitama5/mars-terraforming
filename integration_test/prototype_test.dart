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
    'iOS: globes, research, shared queues, districts, and save/resume',
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
      await controller.advanceForDevelopment(
        duration: const Duration(hours: 1),
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
        duration: const Duration(hours: 1),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        controller.state.districtAt('earth_delta', 0)?.districtId,
        'housing',
      );
      await capture('strategy-ios-city');

      // A completed neighboring campus changes both tax and research speed.
      await controller.command((engine) => engine.enqueue('urban_planning'));
      await controller.advanceForDevelopment(
        duration: const Duration(hours: 5),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.state.research, contains('urban_planning'));
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
        duration: const Duration(hours: 2),
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
