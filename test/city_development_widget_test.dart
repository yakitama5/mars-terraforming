import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/presentation/city_development.dart';
import 'package:mars_terraforming/presentation/city_facility_palette.dart';
import 'package:mars_terraforming/presentation/investment_comparison.dart';
import 'package:mars_terraforming/rendering/city_scene.dart';

class _CityMemorySave implements SaveRepository {
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
  Future<GameController> createController() async {
    final controller = GameController(
      _CityMemorySave(),
      now: () => DateTime.utc(2026, 10, 15),
    );
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> showCity(
    WidgetTester tester,
    GameController controller, {
    String cityId = 'earth_delta',
    ValueChanged<String>? onResearch,
    VoidCallback? onOperations,
    ValueChanged<InvestmentCandidate?>? onSaveInvestment,
    Size size = const Size(844, 390),
    double textScale = 1,
    double verticalChrome = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    InvestmentCandidate? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ListenableBuilder(
              listenable: controller,
              builder: (context, _) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: verticalChrome / 2),
                  child: CityDevelopment(
                    controller: controller,
                    cityId: cityId,
                    renderScene: false,
                    onCityChanged: (_) {},
                    onOpenResearch: onResearch ?? (_) {},
                    onOpenOperations: onOperations,
                    savedInvestment: saved,
                    onSaveInvestment: (candidate) {
                      setState(() => saved = candidate);
                      onSaveInvestment?.call(candidate);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> selectPlot(WidgetTester tester, int plot) async {
    tester.widget<CityScene>(find.byType(CityScene)).onPlotSelected(plot);
    await tester.pumpAndSettle();
  }

  Future<void> tapInList(
    WidgetTester tester,
    String listKey,
    String targetKey,
  ) async {
    final target = find.descendant(
      of: find.byKey(Key(listKey)),
      matching: find.byKey(Key(targetKey)),
    );
    await tester.scrollUntilVisible(
      target,
      80,
      scrollable: find.descendant(
        of: find.byKey(Key(listKey)),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Set<String> paletteIds(WidgetTester tester) {
    final palette = find.byType(CityFacilityPalette);
    if (palette.evaluate().isEmpty) return {};
    return tester
        .widget<CityFacilityPalette>(palette)
        .districts
        .map((district) => district.id)
        .toSet();
  }

  testWidgets(
    'initial construction choices show only research-free districts',
    (tester) async {
      final controller = await createController();
      await showCity(tester, controller);
      expect(paletteIds(tester), {'housing', 'solar'});
      expect(find.byKey(const Key('district-option-campus')), findsNothing);
      expect(find.byKey(const Key('district-option-industry')), findsNothing);
      expect(find.byKey(const Key('district-option-spaceport')), findsNothing);
      expect(
        find.byKey(const Key('district-option-space_elevator')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'discovery and a preserved plan do not expose district choices before manual unlock',
    (tester) async {
      final controller = await createController();
      await showCity(tester, controller);
      await controller.command(
        (engine) => engine.unlockResearch('deployable_solar_arrays'),
      );
      await tester.pumpAndSettle();
      expect(controller.state.isResearchDiscovered('urban_planning'), isTrue);
      expect(paletteIds(tester), {'housing', 'solar'});
      await controller.command((engine) => engine.enqueue('urban_planning'));
      await tester.pumpAndSettle();
      expect(
        controller.state.plans.where((plan) => plan.taskId == 'urban_planning'),
        isEmpty,
      );
      controller.state.plans.add(
        PlannedTask(id: 'preserved-urban', taskId: 'urban_planning')
          ..requiresManualStart = true,
      );
      expect(paletteIds(tester), {'housing', 'solar'});
      await controller.command((engine) {
        engine.state.population = 180;
        const solar = DistrictState(
          cityId: 'earth_delta',
          plotIndex: 0,
          districtId: 'solar',
        );
        engine.state.districts[solar.key] = solar;
        engine.state.researchPointUnits =
            GameContent.researchPointCost('urban_planning') *
            GameState.researchPointScale;
        engine.advanceBy(Duration.zero);
        expect(engine.state.research, isNot(contains('urban_planning')));
        return engine.startPlan('preserved-urban');
      });
      await tester.pumpAndSettle();
      expect(controller.state.research, contains('urban_planning'));
      expect(paletteIds(tester), {'housing', 'solar', 'campus', 'industry'});
      await tester.pump(const Duration(seconds: 8));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'space elevator appears only after both prerequisite technologies',
    (tester) async {
      final controller = await createController();
      controller.state.research.add('orbital_assembly');
      await showCity(tester, controller);
      expect(paletteIds(tester), isNot(contains('space_elevator')));
      await controller.command((engine) {
        engine.state.research.add('composite_shielding');
        return null;
      });
      await tester.pumpAndSettle();
      expect(paletteIds(tester), contains('space_elevator'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('lack of cash and vacant land does not hide known facilities', (
    tester,
  ) async {
    final controller = await createController();
    controller.state
      ..money = 0
      ..research.add('urban_planning');
    for (
      var plot = 0;
      plot < GameContent.cities['earth_delta']!.plotCount;
      plot++
    ) {
      final district = DistrictState(
        cityId: 'earth_delta',
        plotIndex: plot,
        districtId: 'housing',
      );
      controller.state.districts[district.key] = district;
    }
    await showCity(tester, controller);
    expect(paletteIds(tester), {'housing', 'solar', 'campus', 'industry'});
    expect(controller.state.money, 0);
    expect(controller.state.cityDevelopment('earth_delta').availablePlots, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'lunar and Martian choices use research independently of city access',
    (tester) async {
      final controller = await createController();
      controller.state.achievements.add('first_launch');
      expect(controller.state.cityUnlocked('moon_south_pole'), isTrue);
      await showCity(tester, controller, cityId: 'moon_south_pole');
      expect(paletteIds(tester), {'moon_solar', 'moon_spaceport'});
      controller.state.research.addAll(['life_support', 'local_resources']);
      await controller.command((_) => null);
      await tester.pumpAndSettle();
      expect(paletteIds(tester), {
        'moon_outpost',
        'moon_solar',
        'moon_extractor',
        'moon_spaceport',
      });
      controller.state.achievements.add('mars_route_open');
      await showCity(tester, controller, cityId: 'mars_arcadia');
      expect(controller.state.cityUnlocked('mars_arcadia'), isFalse);
      expect(controller.state.habitatChoice, isNull);
      expect(paletteIds(tester), {'mars_habitat', 'extractor'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an empty research frontier remains usable on the Martian map', (
    tester,
  ) async {
    final controller = await createController();
    controller.state.achievements.add('mars_route_open');
    await showCity(tester, controller, cityId: 'mars_arcadia');
    expect(paletteIds(tester), isEmpty);
    expect(find.byType(CityScene), findsOneWidget);
    await selectPlot(tester, 7);
    expect(paletteIds(tester), isEmpty);
    expect(find.byType(DistrictSelectionHeading), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final reserved in [false, true]) {
    testWidgets(
      'map selection retains a ${reserved ? 'reserved' : 'built'} district without its research',
      (tester) async {
        final controller = await createController();
        if (reserved) {
          controller.state.plans.add(
            PlannedTask(
              id: 'retained-campus',
              taskId: 'district_campus',
              cityId: 'earth_delta',
              plotIndex: 7,
              targetLevel: 1,
            ),
          );
        } else {
          controller.state.districts['earth_delta:7'] = const DistrictState(
            cityId: 'earth_delta',
            plotIndex: 7,
            districtId: 'campus',
          );
        }
        await showCity(tester, controller);
        expect(paletteIds(tester), isNot(contains('campus')));
        await selectPlot(tester, 7);
        expect(
          find.byKey(const Key('district-selection-campus')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('city-open-details')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('district-detail')), findsOneWidget);
        expect(
          find.byKey(const Key('district-selection-campus')),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (district, level, required) in [
    ('housing', 1, 'urban_planning'),
    ('campus', 1, 'automated_fabrication'),
    ('housing', 2, 'industrial_network'),
  ]) {
    testWidgets('upgrade $district level $level opens $required directly', (
      tester,
    ) async {
      final controller = await createController();
      if (required != 'urban_planning') {
        controller.state.research.add('urban_planning');
      }
      controller.state.districts['earth_delta:7'] = DistrictState(
        cityId: 'earth_delta',
        plotIndex: 7,
        districtId: district,
        level: level,
      );
      String? opened;
      await showCity(tester, controller, onResearch: (id) => opened = id);
      final before = jsonEncode(controller.state.toJson());
      await selectPlot(tester, 7);
      await tapInList(
        tester,
        'district-inspector',
        'district-required-research',
      );
      expect(opened, required);
      expect(jsonEncode(controller.state.toJson()), before);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('detailed upgrade links to the next level research', (
    tester,
  ) async {
    final controller = await createController();
    controller.state.research.add('urban_planning');
    controller.state.districts['earth_delta:7'] = const DistrictState(
      cityId: 'earth_delta',
      plotIndex: 7,
      districtId: 'housing',
      level: 2,
    );
    String? opened;
    await showCity(tester, controller, onResearch: (id) => opened = id);
    await selectPlot(tester, 7);
    await tester.tap(find.byKey(const Key('city-open-details')));
    await tester.pumpAndSettle();
    await tapInList(
      tester,
      'district-detail',
      'district-required-research-detail',
    );
    expect(opened, 'industrial_network');
    expect(find.byKey(const Key('district-detail')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final detailed in [false, true]) {
    testWidgets('Mars before landing opens operations from detail=$detailed', (
      tester,
    ) async {
      final controller = await createController();
      controller.state.achievements.add('mars_route_open');
      controller.state.research.add('life_support');
      String? openedResearch;
      var operationsOpened = false;
      await showCity(
        tester,
        controller,
        cityId: 'mars_arcadia',
        onResearch: (id) => openedResearch = id,
        onOperations: () => operationsOpened = true,
      );
      final before = jsonEncode(controller.state.toJson());
      await tester.tap(find.byKey(const Key('district-option-mars_habitat')));
      await tester.pumpAndSettle();
      if (detailed) {
        await selectPlot(tester, 7);
        await tester.tap(find.byKey(const Key('city-open-details')));
        await tester.pumpAndSettle();
      }
      await tapInList(
        tester,
        detailed ? 'district-detail' : 'district-inspector',
        detailed
            ? 'district-required-delivery-detail'
            : 'district-required-delivery',
      );
      expect(operationsOpened, isTrue);
      expect(openedResearch, isNull);
      expect(jsonEncode(controller.state.toJson()), before);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'maximum-level district does not suggest another upgrade research',
    (tester) async {
      final controller = await createController();
      controller.state.districts['earth_delta:7'] = const DistrictState(
        cityId: 'earth_delta',
        plotIndex: 7,
        districtId: 'housing',
        level: 3,
      );
      await showCity(tester, controller);
      await selectPlot(tester, 7);
      expect(find.byKey(const Key('district-required-research')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(568, 320), const Size(844, 390)]) {
    testWidgets(
      'map toolbar saves and compares directly with enlarged text at $size',
      (tester) async {
        final controller = await createController();
        InvestmentCandidate? saved;
        await showCity(
          tester,
          controller,
          size: size,
          textScale: 1.4,
          verticalChrome: 136,
          onSaveInvestment: (candidate) => saved = candidate,
        );
        final before = jsonEncode(controller.state.toJson());
        final housing = find.byKey(const Key('district-option-housing'));
        expect(housing.hitTestable(), findsOneWidget);
        await tester.tap(housing);
        await tester.pumpAndSettle();
        await selectPlot(tester, 0);
        final save = find.byKey(const Key('city-save-investment'));
        expect(save.hitTestable(), findsOneWidget);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(saved?.plotIndex, 0);
        expect(find.byType(Dialog), findsNothing);
        expect(tester.widget<TextButton>(save).onPressed, isNull);
        await selectPlot(tester, 1);
        final compare = find.byKey(const Key('city-compare-investments'));
        expect(compare.hitTestable(), findsOneWidget);
        expect(
          find.byKey(const Key('confirm-district')).hitTestable(),
          findsOneWidget,
        );
        if (size.width < 650) {
          expect(
            tester.getSize(find.byType(CityScene)).width,
            greaterThan(310),
          );
        }
        await tester.tap(compare);
        await tester.pumpAndSettle();
        final comparison = tester.widget<InvestmentComparison>(
          find.byType(InvestmentComparison),
        );
        expect(comparison.saved.plotIndex, 0);
        expect(comparison.current.plotIndex, 1);
        expect(jsonEncode(controller.state.toJson()), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'existing district offers new construction without changing the building',
    (tester) async {
      final controller = await createController();
      controller.state.districts['earth_delta:7'] = const DistrictState(
        cityId: 'earth_delta',
        plotIndex: 7,
        districtId: 'housing',
      );
      await showCity(tester, controller);
      final before = jsonEncode(controller.state.toJson());
      await selectPlot(tester, 7);
      expect(find.text('新設'), findsOneWidget);
      expect(find.text('施設を変更'), findsNothing);
      await tester.tap(find.byKey(const Key('city-change-facility')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('city-facility-palette')), findsOneWidget);
      expect(jsonEncode(controller.state.toJson()), before);
    },
  );

  for (final detailed in [false, true]) {
    testWidgets(
      'habitat confirmation can be cancelled or accepted from detail=$detailed',
      (tester) async {
        final controller = await createController();
        controller.state.achievements.add('first_landing');
        controller.state.research.add('life_support');
        await showCity(tester, controller, cityId: 'mars_arcadia');
        final before = jsonEncode(controller.state.toJson());
        await tester.tap(find.byKey(const Key('district-option-mars_habitat')));
        await tester.pumpAndSettle();
        if (detailed) {
          await selectPlot(tester, 7);
          await tester.tap(find.byKey(const Key('city-open-details')));
          await tester.pumpAndSettle();
        }
        final list = detailed ? 'district-detail' : 'district-inspector';
        await tapInList(tester, list, 'choose-underground');
        expect(find.byKey(const Key('confirm-habitat-choice')), findsOneWidget);
        expect(controller.state.habitatChoice, isNull);
        await tester.tap(find.byKey(const Key('cancel-habitat-choice')));
        await tester.pumpAndSettle();
        expect(jsonEncode(controller.state.toJson()), before);
        await tapInList(tester, list, 'choose-underground');
        await tester.tap(find.byKey(const Key('confirm-habitat-choice')));
        await tester.pumpAndSettle();
        expect(controller.state.habitatChoice, 'underground');
        expect(controller.state.plans, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
