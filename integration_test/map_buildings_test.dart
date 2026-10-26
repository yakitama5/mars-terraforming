import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/infrastructure/file_save_store.dart';
import 'package:mars_terraforming/main.dart';
import 'package:mars_terraforming/rendering/city_scene.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'iOS: researched buildings, two sites, real work and saved cities',
    (tester) async {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      final directory = await Directory.systemTemp.createTemp(
        'mars-buildings-',
      );
      final repository = FileSaveStore(directory);
      final now = DateTime.utc(2026, 10, 21, 12);
      // This is a funded visual/interaction fixture, not an economy route or a
      // claim that all knowledge can be bought with the initial budget.
      final seed = GameState.initial(now)
        ..openingSeen = true
        ..firstRunTutorial = FirstRunTutorialStep.completed
        ..completionBannersEnabled = false
        ..tipsEnabled = false
        ..money = 2000000
        ..specialistCount = GameContent.maxSpecialists
        ..earthKits = 20
        ..moonKits = 10
        ..marsKits = 10;
      seed.research.addAll(
        ResearchCatalog.purchasableTechnologies.map(
          (technology) => technology.id,
        ),
      );
      seed.legacyUnlockedPlanets.addAll(['moon', 'mars']);
      seed.achievements.add('first_landing');
      await repository.save(seed.toJson());
      final controller = GameController(
        repository,
        devTools: true,
        now: () => now,
      );
      await controller.initialize(startTimer: false);
      expect(controller.error, isNull);
      addTearDown(controller.dispose);
      addTearDown(() => directory.delete(recursive: true));
      await tester.pumpWidget(
        MarsApp(
          controller: controller,
          showIntroduction: false,
          showTitle: false,
        ),
      );

      Future<void> settledSave() async {
        await tester.runAsync(() async {
          final waiting = Stopwatch()..start();
          while (controller.busy && waiting.elapsed.inSeconds < 30) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        expect(controller.busy, isFalse);
        expect(controller.error, isNull);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      }

      Future<void> tap(String key) async {
        final finder = find.byKey(Key(key));
        if (finder.evaluate().isEmpty) {
          final palette = find.byKey(const Key('city-facility-palette'));
          final scrolls = palette.evaluate().isNotEmpty
              ? find.descendant(of: palette, matching: find.byType(Scrollable))
              : find.byType(Scrollable);
          if (scrolls.evaluate().isNotEmpty) {
            await tester.scrollUntilVisible(
              finder,
              120,
              scrollable: scrolls.last,
            );
          }
        }
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 300));
        await settledSave();
      }

      Future<void> sceneReady() async {
        for (var i = 0; i < 60; i++) {
          if (find.byType(fs.SceneView).evaluate().isNotEmpty) break;
          await tester.pump(const Duration(milliseconds: 500));
        }
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(fs.SceneView), findsOneWidget);
        expect(find.textContaining('3D表示を開始できませんでした'), findsNothing);
        expect(tester.takeException(), isNull);
      }

      Future<void> capture(String name) async {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await binding.takeScreenshot(name);
      }

      Future<void> finishUntil(bool Function() complete) async {
        await controller.command((engine) {
          for (var events = 0; !complete(); events++) {
            if (events > 200) throw StateError('施設の検証が進みません');
            final running = engine.state.plans.where(
              (plan) => plan.status == 'running',
            );
            if (running.isEmpty) {
              throw StateError(
                jsonEncode(engine.state.plans.map((p) => p.toJson()).toList()),
              );
            }
            final next = running
                .map((plan) => plan.remainingMs)
                .reduce((a, b) => a < b ? a : b);
            engine.advanceBy(Duration(milliseconds: next));
          }
          return null;
        });
        await settledSave();
      }

      Future<void> palette() async {
        if (find
            .byKey(const Key('city-change-facility'))
            .evaluate()
            .isNotEmpty) {
          await tap('city-change-facility');
        } else if (find
            .byKey(const Key('cancel-map-building'))
            .evaluate()
            .isNotEmpty) {
          await tap('cancel-map-building');
        }
      }

      await tap('navigation-1');
      await sceneReady();
      await palette();
      await capture('buildings-ios-palette');
      final greenhouse = ResearchCatalog.idForCatalog('B01');
      final analysis = ResearchCatalog.idForCatalog('R01');
      await tap('building-option-$greenhouse');
      await tap('plot-earth_delta-12');
      await tap('building-slot-0');
      await tap('confirm-map-building');
      final greenhouseId = controller.state
          .cityBuildings('earth_delta')
          .singleWhere((building) => building.technologyId == greenhouse)
          .id;
      expect(
        tester
            .widget<CityScene>(find.byType(CityScene))
            .plots[12]
            .buildings
            .singleWhere((building) => building.id == greenhouseId)
            .workState,
        SceneWorkState.building,
      );
      await capture('buildings-ios-construction');
      await finishUntil(
        () => controller.state.developments.contains(greenhouseId),
      );
      await palette();
      await tap('building-option-$analysis');
      expect(tester.widget<CityScene>(find.byType(CityScene)).selectedPlot, 12);
      await tap('building-slot-1');
      await tap('confirm-map-building');
      final analysisId = controller.state
          .cityBuildings('earth_delta')
          .singleWhere((building) => building.technologyId == analysis)
          .id;
      await finishUntil(
        () => controller.state.developments.contains(analysisId),
      );
      final paired = tester
          .widget<CityScene>(find.byType(CityScene))
          .plots[12]
          .buildings;
      expect(
        paired.map((building) => building.catalogId),
        containsAll(['B01', 'R01']),
      );
      expect(paired.map((building) => building.slotIndex).toSet(), {0, 1});
      await capture('buildings-ios-two-sites');

      await palette();
      await tap('building-option-$greenhouse');
      await tap('enable-map-building-$greenhouseId');
      expect(
        find.byKey(Key('map-building-research-plus-$greenhouseId')),
        findsNothing,
      );
      await tap('reserve-building-work-building_import_water');
      await finishUntil(
        () => controller.state.cityStock('earth_delta', 'water') > 0,
      );
      await tap('reserve-building-work-building_grow_food');
      await finishUntil(
        () => controller.state.cityStock('earth_delta', 'food') > 0,
      );
      expect(controller.state.cityStock('earth_delta', 'water'), lessThan(4));
      await capture('buildings-ios-production');

      // Remaining silhouettes are built through the same public construction
      // command. These captures complement the interaction checks above.
      for (final technologyId in GameContent.mapBuildingIds) {
        final definition = GameContent.mapBuildingDefinition(technologyId);
        if (definition.isBaseLab ||
            controller.state
                .cityBuildings('earth_delta')
                .any((building) => building.technologyId == technologyId)) {
          continue;
        }
        final cityId = definition.allowedPlanets.contains('earth')
            ? 'earth_delta'
            : 'moon_south_pole';
        final city = GameContent.cities[cityId]!;
        var placed = false;
        for (var plot = 0; plot < city.plotCount && !placed; plot++) {
          for (var slot = 0; slot < 2 && !placed; slot++) {
            if (!controller.state
                .buildingPreview(
                  technologyId,
                  cityId: cityId,
                  plotIndex: plot,
                  slotIndex: slot,
                )
                .isValid) {
              continue;
            }
            await controller.command(
              (engine) => engine.enqueueMapBuilding(
                technologyId,
                cityId: cityId,
                plotIndex: plot,
                slotIndex: slot,
              ),
            );
            await settledSave();
            placed = true;
          }
        }
        expect(placed, isTrue, reason: '${definition.name}の建設位置');
        final instanceId = controller.state
            .cityBuildings(cityId)
            .singleWhere((building) => building.technologyId == technologyId)
            .id;
        await finishUntil(
          () => controller.state.developments.contains(instanceId),
        );
      }
      await palette();
      await tester.tap(find.byTooltip('都市全体を表示'));
      await tester.pump(const Duration(milliseconds: 500));
      await capture('buildings-ios-earth');
      await tap('building-option-${ResearchCatalog.idForCatalog('M25')}');
      await tester.tap(find.byTooltip('選んだ区画を近くから表示'));
      await tester.pump(const Duration(seconds: 1));
      await capture('buildings-ios-reusable-rocket');
      await tap('navigation-0');
      await tap('select-planet-moon');
      await tap('open-city');
      await sceneReady();
      await capture('buildings-ios-moon');
      await tap('building-option-${ResearchCatalog.idForCatalog('M13')}');
      await tester.tap(find.byTooltip('選んだ区画を近くから表示'));
      await tester.pump(const Duration(seconds: 1));
      await capture('buildings-ios-moon-shuttle');

      // The same design can exist in another city without moving the Earth asset.
      await controller.command(
        (engine) => engine.enqueueMapBuilding(
          greenhouse,
          cityId: 'mars_arcadia',
          plotIndex: 12,
          slotIndex: 0,
        ),
      );
      final marsId = controller.state
          .cityBuildings('mars_arcadia')
          .singleWhere((building) => building.technologyId == greenhouse)
          .id;
      await finishUntil(() => controller.state.developments.contains(marsId));
      expect(marsId, isNot(greenhouseId));
      expect(
        controller.state
            .cityBuildings('earth_delta')
            .any((building) => building.id == greenhouseId),
        isTrue,
      );
      await controller.save();
      final saved = await repository.load();
      final restored = GameState.fromJson(saved.data!);
      for (final city in ['earth_delta', 'moon_south_pole', 'mars_arcadia']) {
        expect(
          restored.cityBuildings(city).map((building) => building.id).toSet(),
          controller.state
              .cityBuildings(city)
              .map((building) => building.id)
              .toSet(),
        );
      }
      expect(
        restored.cityStock('earth_delta', 'food'),
        controller.state.cityStock('earth_delta', 'food'),
      );
      expect(restored.developmentResearchers[greenhouseId] ?? 0, 0);
      expect(controller.error, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
