import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/presentation/city_development.dart';
import 'package:mars_terraforming/presentation/game_screen.dart';
import 'package:mars_terraforming/rendering/city_scene.dart';

class _BuildingSave implements SaveRepository {
  Map<String, dynamic>? data;
  @override
  Future<SaveLoadResult> load() async =>
      SaveLoadResult(data: data, recovered: false, generation: 1);
  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    data = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  }
}

void main() {
  Future<GameController> ready(_BuildingSave repository) async {
    final controller = GameController(
      repository,
      devTools: true,
      now: () => DateTime.utc(2026, 10, 21),
    );
    await controller.initialize(startTimer: false);
    controller.state
      ..openingSeen = true
      ..firstRunTutorial = FirstRunTutorialStep.completed
      ..money = 100000;
    controller.state.research.addAll(['orbital_gardens', 'local_resources']);
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> showCity(
    WidgetTester tester,
    GameController controller, {
    String? technologyId,
    String cityId = 'earth_delta',
    Size size = const Size(844, 390),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => CityDevelopment(
              controller: controller,
              cityId: cityId,
              initialMapBuildingId: technologyId,
              renderScene: false,
              onCityChanged: (_) {},
              onOpenResearch: (_) {},
              onSaveInvestment: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  void selectPlot(WidgetTester tester, int plot) =>
      tester.widget<CityScene>(find.byType(CityScene)).onPlotSelected(plot);

  for (final size in [const Size(884, 402), const Size(1280, 800)]) {
    testWidgets(
      'normal facility palette selects researched map buildings at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        final controller = await ready(_BuildingSave());
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: GameScreen(
              showTitle: false,
              controller: controller,
              renderScene: false,
              showIntroduction: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, 'navigation-1');
        expect(
          tester
              .widget<CityDevelopment>(find.byType(CityDevelopment))
              .initialMapBuildingId,
          isNull,
        );
        final palette = find.byKey(const Key('city-facility-palette'));
        expect(palette, findsOneWidget);
        for (final id in ['orbital_gardens', 'local_resources']) {
          final choice = find.descendant(
            of: palette,
            matching: find.byKey(Key('building-option-$id')),
          );
          await tester.scrollUntilVisible(
            choice,
            100,
            scrollable: find.descendant(
              of: palette,
              matching: find.byType(Scrollable),
            ),
          );
          await tap(tester, 'building-option-$id');
          expect(find.byKey(Key('building-title-$id')), findsOneWidget);
          expect(controller.state.plans, isEmpty);
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const Key('confirm-map-building')),
                )
                .onPressed,
            isNull,
          );
          await tap(tester, 'cancel-map-building');
          expect(palette, findsOneWidget);
        }
        expect(
          find.byKey(const Key('building-option-water_purification')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'research route requires a plot and slot confirmation before reserving',
    (tester) async {
      final controller = await ready(_BuildingSave());
      await showCity(tester, controller, technologyId: 'orbital_gardens');
      expect(controller.state.plans, isEmpty);
      expect(find.byKey(const Key('building-kit-requirement')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-map-building')))
            .onPressed,
        isNull,
      );
      final before = controller.state.money;
      selectPlot(tester, 12);
      await tester.pumpAndSettle();
      await tap(tester, 'building-slot-1');
      expect(controller.state.plans, isEmpty);
      expect(controller.state.money, before);
      expect(
        tester.widget<CityScene>(find.byType(CityScene)).selectedBuildingSlot,
        1,
      );
      await tap(tester, 'confirm-map-building');
      final building = controller.state
          .cityBuildings('earth_delta')
          .singleWhere((b) => b.technologyId == 'orbital_gardens');
      expect(building.plotIndex, 12);
      expect(building.slotIndex, 1);
      expect(building.id, isNot('orbital_gardens'));
      expect(
        tester
            .widget<CityScene>(find.byType(CityScene))
            .plots[12]
            .buildings
            .single
            .id,
        building.id,
      );
      expect(find.byKey(const Key('building-work-status')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a second facility shares the empty slot and completed operations use the instance',
    (tester) async {
      final repository = _BuildingSave();
      final controller = await ready(repository);
      await controller.constructMapBuilding(
        'orbital_gardens',
        cityId: 'earth_delta',
        plotIndex: 12,
        slotIndex: 0,
      );
      var plan = controller.state.plans.lastWhere((p) => !p.isFinished);
      await controller.advanceForDevelopment(
        duration: Duration(milliseconds: plan.remainingMs),
      );
      await showCity(tester, controller, technologyId: 'local_resources');
      selectPlot(tester, 12);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('building-slot-0')))
            .onSelected,
        isNull,
      );
      expect(
        tester.widget<CityScene>(find.byType(CityScene)).availableBuildingSlots,
        {1},
      );
      await tap(tester, 'confirm-map-building');
      plan = controller.state.plans.lastWhere((p) => !p.isFinished);
      await controller.advanceForDevelopment(
        duration: Duration(milliseconds: plan.remainingMs),
      );
      await tester.pumpAndSettle();
      final facilities = controller.state
          .cityBuildings('earth_delta')
          .where((b) => b.plotIndex == 12)
          .toList();
      expect(facilities, hasLength(2));
      expect(facilities.map((b) => b.slotIndex).toSet(), {0, 1});
      final analyzer = facilities.singleWhere(
        (b) => b.technologyId == 'local_resources',
      );
      await tap(tester, 'enable-map-building-${analyzer.id}');
      expect(controller.state.developmentEnabled[analyzer.id], isTrue);
      await tap(tester, 'map-building-research-plus-${analyzer.id}');
      expect(controller.state.developmentResearchers[analyzer.id], 1);
      final saved = GameState.fromJson(repository.data!);
      expect(
        saved.cityBuildings('earth_delta').where((b) => b.plotIndex == 12),
        hasLength(2),
      );
      expect(saved.developmentResearchers[analyzer.id], 1);
      // The development-time command notice expires without advancing game time.
      await tester.pump(const Duration(seconds: 8));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'headquarters research lab is an existing asset and small landscape stays usable',
    (tester) async {
      final controller = await ready(_BuildingSave());
      await showCity(
        tester,
        controller,
        technologyId: 'base_lab',
        size: const Size(667, 375),
      );
      final scene = tester.widget<CityScene>(find.byType(CityScene));
      expect(
        scene.legacyBuildings.singleWhere((b) => b.id == 'base_lab').name,
        '基礎研究所',
      );
      expect(find.byKey(const Key('confirm-map-building')), findsNothing);
      expect(
        find.byKey(const Key('enable-map-building-base_lab')),
        findsOneWidget,
      );
      expect(controller.state.plans, isEmpty);
      await tap(tester, 'relocate-building-base_lab');
      expect(find.byKey(const Key('building-kit-requirement')), findsNothing);
      expect(find.byKey(const Key('confirm-map-building')), findsOneWidget);
      expect(controller.state.plans, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'research staffing changes the work quote and production keeps its completed model',
    (tester) async {
      final controller = await ready(_BuildingSave());
      await controller.constructMapBuilding(
        'orbital_gardens',
        cityId: 'earth_delta',
        plotIndex: 12,
      );
      final plan = controller.state.plans.lastWhere((p) => !p.isFinished);
      await controller.advanceForDevelopment(
        duration: Duration(milliseconds: plan.remainingMs),
      );
      await showCity(tester, controller, technologyId: 'orbital_gardens');
      final building = controller.state
          .cityBuildings('earth_delta')
          .firstWhere((b) => b.technologyId == 'orbital_gardens');
      await tap(tester, 'enable-map-building-${building.id}');
      expect(find.textContaining('出力：食品 3'), findsOneWidget);
      await tap(tester, 'map-building-research-plus-${building.id}');
      await tap(tester, 'map-building-research-plus-${building.id}');
      expect(find.textContaining('出力：食品 2'), findsOneWidget);
      await tap(tester, 'repeat-building-work-building_import_water');
      await tap(tester, 'reserve-building-work-building_import_water-5');
      expect(
        controller.state.plans
            .lastWhere((plan) => !plan.isFinished)
            .remainingRepeats,
        5,
      );
      final scene = tester.widget<CityScene>(find.byType(CityScene));
      expect(scene.plots[12].buildings.single.workState, SceneWorkState.none);
      expect(
        controller.state
            .cityBuildings('earth_delta')
            .firstWhere((b) => b.id == building.id)
            .workState,
        'running',
      );
      await tester.pump(const Duration(seconds: 8));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'research application opens the matching map draft without an automatic purchase',
    (tester) async {
      final controller = await ready(_BuildingSave());
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: GameScreen(
            showTitle: false,
            controller: controller,
            renderScene: false,
            showIntroduction: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'navigation-3');
      await tap(tester, 'operations-4');
      await tap(tester, 'open-building-map-orbital_gardens');
      expect(
        find.byKey(const Key('building-title-orbital_gardens')),
        findsOneWidget,
      );
      expect(
        tester.widget<CityDevelopment>(find.byType(CityDevelopment)).cityId,
        'earth_delta',
      );
      expect(controller.state.plans, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-map-building')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final (planet, cityId, transport) in [
    ('moon', 'moon_south_pole', 'moon_delivery'),
    ('mars', 'mars_arcadia', 'mars_delivery'),
  ]) {
    testWidgets(
      '$planet construction shows local kits and reserves before normal cargo arrives',
      (tester) async {
        final repository = _BuildingSave();
        final controller = await ready(repository);
        // Access and one manufactured Earth kit are an explicit transport fixture.
        // Local inventory starts empty; ordinary cargo must arrive before work pays.
        controller.state.achievements.add(
          planet == 'moon' ? 'first_launch' : 'first_landing',
        );
        controller.state.earthKits = 1;
        int localKits() => planet == 'moon'
            ? controller.state.moonKits
            : controller.state.marsKits;
        await showCity(
          tester,
          controller,
          technologyId: 'orbital_gardens',
          cityId: cityId,
        );
        selectPlot(tester, 12);
        await tester.pumpAndSettle();
        expect(find.textContaining('必要 1基・現在 0基'), findsOneWidget);
        expect(find.byKey(const Key('building-kit-wait')), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('confirm-map-building')),
              )
              .onPressed,
          isNotNull,
        );
        final money = controller.state.money;
        await tap(tester, 'confirm-map-building');
        final construction = controller.state.plans.lastWhere(
          (plan) => plan.definition.developmentId == 'orbital_gardens',
        );
        expect(construction.status, 'queued');
        expect(construction.stopReason, isNotEmpty);
        expect(controller.state.money, money);
        expect(localKits(), 0);
        expect(find.text(construction.stopReason), findsOneWidget);
        await controller.command((engine) => engine.enqueue(transport));
        final cargo = controller.state.currentPlanFor('launch')!;
        await controller.command((engine) {
          engine.advanceBy(Duration(milliseconds: cargo.remainingMs));
          return null;
        });
        await tester.pumpAndSettle();
        expect(construction.status, 'running');
        expect(localKits(), 0);
        expect(
          tester
              .widget<CityScene>(find.byType(CityScene))
              .plots[12]
              .buildings
              .single
              .workState,
          SceneWorkState.building,
        );
        final saved = GameState.fromJson(repository.data!);
        expect(
          saved.plans.singleWhere((plan) => plan.id == construction.id).status,
          'running',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('undiscovered buildings do not enter the construction palette', (
    tester,
  ) async {
    final controller = await ready(_BuildingSave());
    controller.state.research.remove('orbital_gardens');
    await showCity(tester, controller);
    final scene = tester.widget<CityScene>(find.byType(CityScene));
    expect(scene.plots.every((p) => p.buildings.isEmpty), isTrue);
    expect(
      find.byKey(const Key('building-option-orbital_gardens')),
      findsNothing,
    );
    expect(
      find.text(GameContent.mapBuildingDefinitions['water_purification']!.name),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
