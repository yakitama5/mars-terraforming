import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/presentation/city_development.dart';
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
  }) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: CityDevelopment(
            controller: controller,
            cityId: cityId,
            renderScene: false,
            onCityChanged: (_) {},
            onOpenResearch: onResearch ?? (_) {},
            onOpenOperations: onOperations,
            onSaveInvestment: (_) {},
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
    final target = find.byKey(Key(targetKey));
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
}
