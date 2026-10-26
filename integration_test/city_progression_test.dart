import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/infrastructure/file_save_store.dart';
import 'package:mars_terraforming/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'iOS: city conditions, immediate starts, no staffing, caps and offline resume',
    (tester) async {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      final directory = await Directory.systemTemp.createTemp('mars-city-v11-');
      addTearDown(() => directory.delete(recursive: true));
      final store = FileSaveStore(directory);
      var clock = DateTime.utc(2026, 10, 26, 12);
      // Skip only the story and its clock-pausing tutorial. The budget, RP,
      // buildings and knowledge below are the normal initial values.
      final seed = GameState.initial(clock)
        ..openingSeen = true
        ..firstRunTutorial = FirstRunTutorialStep.completed
        ..tipsEnabled = false
        ..completionBannersEnabled = false;
      await store.save(seed.toJson());
      final controller = GameController(
        store,
        devTools: true,
        now: () => clock,
      );
      addTearDown(controller.dispose);
      await controller.initialize(startTimer: false);
      expect(controller.error, isNull);
      await tester.pumpWidget(
        MarsApp(
          controller: controller,
          showTitle: false,
          showIntroduction: false,
        ),
      );

      Future<void> settle() async {
        await tester.runAsync(() async {
          final wait = Stopwatch()..start();
          while (controller.busy && wait.elapsed.inSeconds < 30) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        expect(controller.busy, isFalse);
        expect(controller.error, isNull);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      }

      Future<void> tap(String key) async {
        final finder = find.byKey(Key(key));
        if (finder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            finder,
            120,
            scrollable: find.byType(Scrollable).last,
          );
        }
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(finder);
        await settle();
      }

      Future<void> sceneReady() async {
        for (
          var i = 0;
          i < 100 && find.byType(fs.SceneView).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(find.byType(fs.SceneView), findsOneWidget);
        expect(find.textContaining('3D表示を開始できませんでした'), findsNothing);
      }

      Future<void> capture(String name) async {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await binding.takeScreenshot(name);
      }

      Future<void> finish(PlannedTask plan) async {
        await controller.advanceForDevelopment(
          duration: Duration(milliseconds: plan.remainingMs),
        );
        await settle();
        expect(plan.isFinished, isTrue);
      }

      await tap('navigation-2');
      await tap('research-filter-bio');
      await tap('research-node-orbital_gardens');
      await tap('queue-orbital_gardens');
      expect(controller.state.research, contains('orbital_gardens'));
      expect(controller.state.developments, isEmpty);
      await tap('close-research-detail');
      await tap('research-fit');
      await tester.pump(const Duration(seconds: 2));
      await tap('research-node-algal_cultivation');
      await tester.scrollUntilVisible(
        find.byKey(const Key('research-city-requirements')),
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('research-detail')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();
      expect(find.textContaining('完成した水耕温室'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('queue-algal_cultivation')),
            )
            .onPressed,
        isNull,
      );
      await capture('city-v11-ios-research-conditions');

      await tap('navigation-1');
      await sceneReady();
      await tap('district-option-housing');
      await tap('plot-earth_delta-1');
      await tap('confirm-district');
      final house = controller.state.plans.last;
      expect(house.status, 'running');
      final snapshot = jsonEncode(controller.state.toJson());
      expect(
        controller.engine!.enqueueDistrict('earth_delta', 2, 'housing'),
        isNotNull,
      );
      expect(jsonEncode(controller.state.toJson()), snapshot);
      await capture('city-v11-ios-construction');
      await finish(house);
      expect(controller.state.totalPopulation, 180);
      await controller.command(
        (engine) => engine.enqueue('factory_contract', repeats: 8),
      );
      final contract = controller.state.plans.last;
      await controller.advanceForDevelopment(
        duration: const Duration(minutes: 15),
      );
      await settle();
      expect(contract.isFinished, isTrue);
      await tap('city-change-facility');
      await tap('building-option-orbital_gardens');
      await tap('plot-earth_delta-12');
      await tap('building-slot-0');
      await tap('confirm-map-building');
      final greenhouse = controller.state.plans.last;
      expect(greenhouse.status, 'running');
      await finish(greenhouse);
      expect(
        controller.state.developments,
        contains(greenhouse.buildingInstanceId),
      );
      expect(
        find.byKey(
          Key('map-building-research-plus-${greenhouse.buildingInstanceId}'),
        ),
        findsNothing,
      );
      await tap('navigation-2');
      await tap('research-filter-bio');
      if (find.byKey(const Key('research-detail')).evaluate().isNotEmpty) {
        await tap('close-research-detail');
      }
      await tap('research-fit');
      await tester.pump(const Duration(seconds: 2));
      await tap('research-node-algal_cultivation');
      final rp = controller.state.researchPointUnits;
      await tap('queue-algal_cultivation');
      expect(controller.state.research, contains('algal_cultivation'));
      expect(
        controller.state.researchPointUnits,
        rp -
            GameContent.researchPointCost('algal_cultivation') *
                GameState.researchPointScale,
      );
      await capture('city-v11-ios-research-unlocked');

      await tap('navigation-4');
      await tap('agency-section-foundation');
      expect(find.byKey(const Key('staff-research-more')), findsNothing);
      expect(find.byKey(const Key('queue-train_specialists')), findsNothing);
      expect(find.byKey(const Key('agency-foundation')), findsOneWidget);
      await capture('city-v11-ios-city-foundation');

      // A separate near-capacity fixture tests the boundary and its actual UI;
      // these injected reserves are not part of the initial-budget route above.
      await controller.command((engine) {
        engine.state.money = engine.state.moneyCapacity - 1;
        engine.state.researchPointUnits =
            engine.state.researchPointCapacity * GameState.researchPointScale -
            1;
        return null;
      });
      await controller.advanceForDevelopment(
        duration: const Duration(hours: 1),
      );
      expect(controller.state.isMoneyAtCapacity, isTrue);
      expect(controller.state.isResearchAtCapacity, isTrue);
      await capture('city-v11-ios-capacities');
      await controller.save();
      final expected = GameEngine(
        GameState.fromJson(controller.state.toJson()),
      );
      clock = clock.add(const Duration(hours: 8));
      expected.advanceTo(clock);
      final resumed = GameController(store, now: () => clock);
      addTearDown(resumed.dispose);
      await resumed.initialize(startTimer: false);
      expect(resumed.error, isNull);
      expect(resumed.state.toJson(), expected.state.toJson());
      expect(
        resumed.state.money,
        lessThanOrEqualTo(resumed.state.moneyCapacity),
      );
      expect(
        resumed.state.researchPoints,
        lessThanOrEqualTo(resumed.state.researchPointCapacity),
      );
      expect(resumed.state.research, controller.state.research);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
