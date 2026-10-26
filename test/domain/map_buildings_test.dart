import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 21);
  GameState copy(GameState s) => GameState.fromJson(
    jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
  );
  GameEngine ready() {
    final s = GameState.initial(epoch)
      ..money = 1000000
      ..specialistCount = 36
      ..researchers = 12
      ..firstRunTutorial = FirstRunTutorialStep.completed;
    s.research.addAll(
      GameContent.researchTechnologies.values
          .where((t) => t.isPurchasable)
          .map((t) => t.id),
    );
    s.achievements.add('first_landing');
    return GameEngine(s);
  }

  void finish(GameEngine g, PlannedTask p) {
    for (var i = 0; !p.isFinished; i++) {
      if (i > 100 || p.status != 'running') {
        throw StateError('待機: ${p.taskId} ${p.stopReason}');
      }
      g.advanceBy(Duration(milliseconds: p.remainingMs));
    }
  }

  String build(
    GameEngine g,
    String tech, {
    String city = 'earth_delta',
    int plot = 12,
    int slot = 0,
  }) {
    expect(
      g.enqueueMapBuilding(
        tech,
        cityId: city,
        plotIndex: plot,
        slotIndex: slot,
      ),
      isNull,
    );
    final p = g.state.plans.last;
    final id = p.buildingInstanceId!;
    finish(g, p);
    expect(g.setDevelopmentEnabled(id, true), isNull);
    return id;
  }

  PlannedTask start(
    GameEngine g,
    String id,
    String task, {
    int? target,
    int? repeats = 1,
  }) {
    expect(
      g.enqueueBuildingWork(
        id,
        task,
        targetPlotIndex: target,
        repeats: repeats,
      ),
      isNull,
    );
    return g.state.plans.last;
  }

  void work(GameEngine g, String id, String task, {int? target}) =>
      finish(g, start(g, id, task, target: target));

  test(
    'new worlds hide research buildings and normal plots have two real slots',
    () {
      final fresh = GameState.initial(epoch);
      expect(fresh.cityBuildings('earth_delta').single.id, 'base_lab');
      expect(fresh.mapBuildingUnlocked('orbital_gardens'), isFalse);
      final g = ready();
      build(g, 'orbital_gardens');
      build(g, 'local_resources', slot: 1);
      expect(
        g.state.cityBuildings('earth_delta').where((b) => !b.legacySite),
        hasLength(2),
      );
      expect(g.state.cityDevelopment('earth_delta').completedPlots, 1);
      expect(g.state.cityDevelopment('earth_delta').emptyPlots, 24);
      expect(
        g.enqueueMapBuilding(
          'battery_banks',
          cityId: 'earth_delta',
          plotIndex: 12,
        ),
        contains('使用中'),
      );
      expect(
        g.enqueueMapBuilding(
          'reusable_launch',
          cityId: 'earth_delta',
          plotIndex: 8,
          slotIndex: 1,
        ),
        contains('大型'),
      );
      expect(
        g.enqueueMapBuilding('ice_mining', cityId: 'earth_delta', plotIndex: 8),
        contains('天体'),
      );
      expect(g.enqueueDistrict('earth_delta', 12, 'campus'), contains('使用'));
      expect(copy(g.state).toJson(), g.state.toJson());
    },
  );

  test(
    'one district and one small building share a plot, large assets do not',
    () {
      final g = ready();
      expect(g.enqueueDistrict('earth_delta', 12, 'campus'), isNull);
      finish(g, g.state.plans.last);
      build(g, 'local_resources', slot: 1);
      expect(
        g.enqueueMapBuilding(
          'orbital_gardens',
          cityId: 'earth_delta',
          plotIndex: 12,
        ),
        contains('使用中'),
      );
      build(g, 'reusable_launch', plot: 8);
      expect(
        g.enqueueMapBuilding(
          'orbital_gardens',
          cityId: 'earth_delta',
          plotIndex: 8,
          slotIndex: 1,
        ),
        contains('使用中'),
      );
      expect(copy(g.state).toJson(), g.state.toJson());
    },
  );

  test('the same technology has independent city instances and one effect per asset', () {
    final g = ready();
    final first = build(g, 'orbital_gardens');
    final second = build(g, 'orbital_gardens', city: 'earth_highland');
    expect(first, isNot(second));
    expect(g.state.developmentWorkers, 2);
    expect(
      g.state.developmentEfficiencyBonus('factory'),
      2 * GameContent.developmentEfficiencyBonus('orbital_gardens'),
    );
    expect(g.state.developmentTechnologyId(first), 'orbital_gardens');
    expect(
      g.enqueueMapBuilding(
        'orbital_gardens',
        cityId: 'earth_highland',
        plotIndex: 8,
      ),
      contains('同系統'),
    );
    expect(
      g.enqueueDevelopment('orbital_gardens', cityId: 'earth_delta'),
      isNotNull,
    );
    work(g, first, 'building_import_water');
    work(g, first, 'building_grow_food');
    expect(g.state.cityStock('earth_delta', 'food'), 3);
    expect(g.state.cityStock('earth_highland', 'food'), 0);
    expect(copy(g.state).toJson(), g.state.toJson());
  });

  test('local production pays inputs once without research staffing', () {
    final g = ready();
    final id = build(g, 'orbital_gardens');
    work(g, id, 'building_import_water');
    expect(g.state.cityStock('earth_delta', 'water'), 4);
    expect(g.assignDevelopmentResearchers(id, 2), isNotNull);
    final p = start(g, id, 'building_grow_food');
    expect(g.state.cityStock('earth_delta', 'water'), 3);
    expect(g.assignDevelopmentResearchers(id, 0), isNotNull);
    final restored = GameEngine(copy(g.state));
    final paid = restored.state.plans.last;
    expect(restored.setDevelopmentEnabled(id, false), isNull);
    restored.advanceBy(const Duration(minutes: 10));
    expect(paid.remainingMs, p.remainingMs);
    expect(restored.state.cityStock('earth_delta', 'food'), 0);
    expect(restored.setDevelopmentEnabled(id, true), isNull);
    finish(restored, paid);
    expect(restored.state.cityStock('earth_delta', 'food'), 3);
    expect(restored.state.cityStock('earth_delta', 'water'), 3);
    restored.advanceBy(const Duration(minutes: 1));
    expect(restored.state.cityStock('earth_delta', 'food'), 3);
    expect(restored.assignDevelopmentResearchers(id, 4), isNotNull);
    expect(
      restored.state.buildingWorkLockReason(id, 'building_grow_food'),
      isNull,
    );
  });

  test(
    'batteries store existing power and high-demand jobs spend finite charge',
    () {
      final g = ready();
      final battery = build(g, 'battery_banks');
      final printer = build(g, 'process_design', slot: 1);
      work(g, printer, 'building_import_feedstock');
      expect(
        g.state.buildingWorkLockReason(printer, 'building_print_parts'),
        contains('電力不足'),
      );
      work(g, battery, 'building_charge');
      expect(g.state.cityBatteryCharge('earth_delta'), 5);
      final p = start(g, printer, 'building_print_parts');
      expect(g.state.cityBatteryCharge('earth_delta'), 4);
      expect(p.iterationBatteryUnits, 1);
      final resumed = GameEngine(copy(g.state));
      finish(resumed, resumed.state.plans.last);
      expect(resumed.state.cityStock('earth_delta', 'parts'), 3);
      expect(resumed.state.cityBatteryCharge('earth_delta'), 4);
      expect(
        resumed.state.cityPowerSupply('earth_delta'),
        GameContent.baseCityPower,
      );
    },
  );

  test('grid connects solar output and creates no electricity by itself', () {
    final g = ready();
    final grid = build(g, 'urban_planning');
    work(g, grid, 'building_import_parts');
    work(g, grid, 'building_connect_grid');
    expect(g.state.cityPowerSupply('earth_delta'), 2);
    expect(
      g.state.buildingWorkLockReason(grid, 'building_connect_grid'),
      contains('完了'),
    );
    final solar = DistrictState(
      cityId: 'earth_delta',
      plotIndex: 8,
      districtId: 'solar',
    );
    g.state.districts[solar.key] = solar;
    expect(g.state.cityPowerSupply('earth_delta'), 6);
    expect(g.setDevelopmentEnabled(grid, false), isNull);
    expect(g.state.cityPowerSupply('earth_delta'), 2);
    expect(copy(g.state).connectedGridCities, contains('earth_delta'));
  });

  test(
    'a surveyed site pays RP once across restart, cancellation and split time',
    () {
      final g = ready();
      final lab = build(g, 'local_resources');
      expect(
        g.enqueueBuildingWork(
          lab,
          'building_survey',
          targetPlotIndex: 4,
          repeats: 2,
        ),
        isNotNull,
      );
      final p = start(g, lab, 'building_survey', target: 4);
      expect(
        g.enqueueBuildingWork(lab, 'building_survey', targetPlotIndex: 4),
        contains('予約済み'),
      );
      final bulk = GameEngine(copy(g.state));
      final split = GameEngine(copy(g.state));
      bulk.advanceBy(Duration(milliseconds: p.remainingMs));
      split.advanceBy(const Duration(seconds: 7));
      split.advanceBy(Duration(milliseconds: p.remainingMs - 7000));
      expect(split.state.toJson(), bulk.state.toJson());
      expect(bulk.state.isSiteSurveyed('earth_delta', 4), isTrue);
      final rate = copy(g.state).researchPointUnitsPerMs;
      expect(
        bulk.state.researchPointUnits,
        g.state.researchPointUnits +
            rate * p.remainingMs +
            GameContent.surveyResearchPoints * GameState.researchPointScale,
      );
      expect(
        bulk.enqueueBuildingWork(lab, 'building_survey', targetPlotIndex: 4),
        contains('完了'),
      );
      final before = bulk.state.researchPointUnits;
      bulk.advanceTo(epoch.subtract(const Duration(hours: 1)));
      expect(bulk.state.researchPointUnits, before);
    },
  );

  test(
    'vehicle service consumes parts or service sets and waits for return',
    () {
      final g = ready();
      final id = build(g, 'reusable_launch');
      g.state.cityStocks['earth_delta'] = {'serviceCredit': 1};
      work(g, id, 'building_prepare_rocket');
      expect(g.state.cityStock('earth_delta', 'serviceCredit'), 0);
      expect(g.state.preparedVehicles, contains(id));
      g.state.earthKits = 4;
      final flight = start(g, id, 'building_reusable_delivery');
      expect(g.state.preparedVehicles, isNot(contains(id)));
      expect(
        g.state
            .cityBuildings('earth_delta')
            .singleWhere((b) => b.id == id)
            .vehiclePresent,
        isFalse,
      );
      expect(
        g.enqueueBuildingWork(id, 'building_prepare_rocket'),
        contains('帰還'),
      );
      final bad = g.state.toJson();
      bad['preparedVehicles'] = [id];
      expect(() => GameState.fromJson(bad), throwsFormatException);
      finish(g, flight);
      expect(g.state.marsKits, 3);
      expect(g.state.earthKits, 1);
      expect(
        g.state
            .cityBuildings('earth_delta')
            .singleWhere((b) => b.id == id)
            .vehiclePresent,
        isTrue,
      );
      expect(
        g.enqueueBuildingWork(id, 'building_reusable_delivery'),
        contains('整備'),
      );
    },
  );

  test('legacy lunar ground evidence moves explicitly and changes only its operation', () {
    final g = ready();
    expect(
      g.enqueueDevelopment('lunar_shuttles', cityId: 'earth_delta'),
      isNull,
    );
    finish(g, g.state.plans.last);
    final id = g.state.developments.single;
    expect(id, 'lunar_shuttles');
    expect(g.state.buildingLocations[id]!.legacySite, isTrue);
    expect(g.setDevelopmentEnabled(id, true), isNull);
    expect(g.state.developmentResearchCapacityFor(id), greaterThan(0));
    expect(
      g.enqueueBuildingWork(id, 'building_import_propellant'),
      contains('天体'),
    );
    expect(
      g.relocateMapBuilding(id, cityId: 'moon_south_pole', plotIndex: 12),
      isNull,
    );
    finish(g, g.state.plans.last);
    expect(g.state.developments, hasLength(1));
    expect(g.state.developmentResearchCapacityFor(id), 0);
    expect(g.state.developmentCrewFor(id), 2);
    expect(g.setDevelopmentEnabled(id, true), isNull);
    work(g, id, 'building_import_parts');
    work(g, id, 'building_import_propellant');
    work(g, id, 'building_prepare_shuttle');
    g.state.earthKits = 3;
    work(g, id, 'building_lunar_delivery');
    expect(g.state.moonKits, 3);
    expect(g.state.preparedVehicles, isNot(contains(id)));
    expect(copy(g.state).toJson(), g.state.toJson());
  });

  test('local supplies replace kit purchases exactly once without changing a paid run', () {
    final g = ready();
    g.state.cityStocks['earth_delta'] = {
      'parts': 2,
      'provisions': 1,
      'serviceCredit': 1,
    };
    final task = GameContent.tasks['habitat_kit']!;
    final cost = g.state.taskCost(task);
    expect(
      cost,
      task.cost -
          GameContent.kitPartCostReduction -
          GameContent.kitProvisionCostReduction -
          GameContent.kitServiceCostReduction,
    );
    expect(g.enqueue('habitat_kit'), isNull);
    final p = g.state.plans.last;
    expect(g.state.cityStock('earth_delta', 'parts'), 1);
    expect(g.state.cityStock('earth_delta', 'provisions'), 0);
    final money = g.state.moneyUnits;
    final restored = GameEngine(copy(g.state));
    expect(restored.state.moneyUnits, money);
    finish(restored, restored.state.plans.last);
    expect(restored.state.earthKits, 1);
    expect(restored.state.cityStock('earth_delta', 'parts'), 1);
    expect(p.status, 'running');
  });

  test('queued relocation retains both plots and can be cancelled safely', () {
    final g = ready();
    final id = build(g, 'orbital_gardens');
    expect(g.enqueue('factory_contract'), isNull);
    expect(
      g.relocateMapBuilding(id, cityId: 'earth_delta', plotIndex: 8),
      contains('作業中'),
    );
    final move = PlannedTask(
      id: 'plan-${g.state.nextPlanId++}',
      taskId: GameContent.developmentTaskId('orbital_gardens'),
      developmentCityId: 'earth_delta',
      buildingInstanceId: id,
      buildingPlotIndex: 8,
      buildingSlotIndex: 0,
      relocation: true,
    )..requiresManualStart = true;
    g.state.plans.add(move);
    g.advanceBy(Duration.zero);
    expect(move.status, 'queued');
    expect(
      g.state.cityBuildings('earth_delta').where((b) => b.id == id),
      hasLength(2),
    );
    expect(
      g.enqueueMapBuilding(
        'local_resources',
        cityId: 'earth_delta',
        plotIndex: 12,
      ),
      contains('使用中'),
    );
    expect(
      g.enqueueMapBuilding(
        'local_resources',
        cityId: 'earth_delta',
        plotIndex: 8,
      ),
      contains('使用中'),
    );
    expect(copy(g.state).toJson(), g.state.toJson());
    expect(g.cancelQueued(move.id), isNull);
    expect(
      g.state
          .cityBuildings('earth_delta')
          .singleWhere((b) => b.id == id)
          .plotIndex,
      12,
    );
    expect(copy(g.state).toJson(), g.state.toJson());
  });

  test('paid relocation releases the old plot and preserves one asset through restart', () {
    final g = ready();
    final id = build(g, 'orbital_gardens');
    work(g, id, 'building_import_water');
    expect(
      g.relocateMapBuilding(id, cityId: 'earth_highland', plotIndex: 8),
      isNull,
    );
    final move = g.state.plans.last;
    expect(move.status, 'running');
    expect(
      g.state
          .buildingPreview(
            'local_resources',
            cityId: 'earth_delta',
            plotIndex: 12,
          )
          .isValid,
      isTrue,
    );
    final restored = GameEngine(copy(g.state));
    final restoredMove = restored.state.plans.last;
    expect(restored.cancelQueued(restoredMove.id), isNull);
    finish(restored, restoredMove);
    expect(restored.state.developments, hasLength(1));
    expect(restored.state.developmentCityIds[id], 'earth_highland');
    expect(restored.state.cityStock('earth_delta', 'water'), 4);
    expect(restored.state.cityStock('earth_highland', 'water'), 0);
    expect(copy(restored.state).toJson(), restored.state.toJson());
  });

  test(
    'stock, position, saved output and instance corruption are rejected',
    () {
      final g = ready();
      final id = build(g, 'orbital_gardens');
      work(g, id, 'building_import_water');
      start(g, id, 'building_grow_food');
      final invalid = <void Function(Map<String, dynamic>)>[
        (j) => j.remove('buildingLocations'),
        (j) => (j['buildingLocations'] as Map).remove(id),
        (j) => (j['cityStocks'] as Map)['earth_delta'] = {'water': -1},
        (j) => (j['cityStocks'] as Map)['earth_delta'] = {
          'charge': GameContent.batteryCapacity + 1,
        },
        (j) => ((j['buildingLocations'] as Map)[id] as Map)['plotIndex'] = 99,
        (j) => ((j['buildingLocations'] as Map)[id] as Map)['slotIndex'] = 2,
        (j) => (j['developmentTechnologyIds'] as Map)[id] = 'unknown',
        (j) => ((j['plans'] as List).last as Map)['iterationLocalOutputs'] = {
          'food': 100,
        },
        (j) => ((j['plans'] as List).last as Map)['iterationBatteryUnits'] = -1,
      ];
      for (final mutate in invalid) {
        final snapshot =
            jsonDecode(jsonEncode(g.state.toJson())) as Map<String, dynamic>;
        mutate(snapshot);
        expect(() => GameState.fromJson(snapshot), throwsFormatException);
      }
    },
  );
  test(
    'survey results improve future local ice yield without retroactive output',
    () {
      final g = ready();
      const city = 'moon_south_pole';
      g.state.moonKits = 2;
      final ice = Iterable<int>.generate(GameContent.cities[city]!.plotCount)
          .firstWhere((p) => GameContent.cities[city]!.terrainAt(p) == 'ice');
      final mine = build(g, 'ice_mining', city: city, plot: ice);
      final lab = build(
        g,
        'local_resources',
        city: city,
        plot: ice == 12 ? 13 : 12,
      );
      work(g, mine, 'building_mine_ice');
      expect(g.state.cityStock(city, 'rawWater'), 4);
      expect(g.state.siteSurveyReport(city, ice), contains('未調査'));
      work(g, lab, 'building_survey', target: ice);
      expect(g.state.cityStock(city, 'rawWater'), 4);
      expect(g.state.siteSurveyReport(city, ice), contains('採水適性'));
      final paid = start(g, mine, 'building_mine_ice');
      expect(
        paid.iterationLocalOutputs['rawWater'],
        4 + GameContent.surveyedIceYieldBonus,
      );
      final restored = GameEngine(copy(g.state));
      finish(restored, restored.state.plans.last);
      expect(
        restored.state.cityStock(city, 'rawWater'),
        8 + GameContent.surveyedIceYieldBonus,
      );
    },
  );
  test(
    'storage saturation stops future repeats before another payment or input',
    () {
      final g = ready();
      final id = build(g, 'orbital_gardens');
      g.state.cityStocks['earth_delta'] = {
        'water': 4,
        'food': GameContent.buildingStockLimit - 3,
      };
      final p = start(g, id, 'building_grow_food', repeats: 2);
      g.advanceBy(Duration(milliseconds: p.remainingMs));
      expect(p.status, 'queued');
      expect(p.completedRuns, 1);
      expect(p.stopReason, contains('保管上限'));
      expect(
        g.state.cityStock('earth_delta', 'food'),
        GameContent.buildingStockLimit,
      );
      expect(g.state.cityStock('earth_delta', 'water'), 3);
      final restored = GameEngine(copy(g.state));
      restored.advanceBy(const Duration(minutes: 10));
      expect(
        restored.state.cityStock('earth_delta', 'food'),
        GameContent.buildingStockLimit,
      );
      expect(restored.state.cityStock('earth_delta', 'water'), 3);
    },
  );
  test('local construction quotes and consumes one delivered kit only at its paid start', () {
    final g = ready();
    const city = 'moon_south_pole';
    final quote = g.state.buildingPreview(
      'orbital_gardens',
      cityId: city,
      plotIndex: 12,
    );
    expect(quote.isValid, isTrue);
    expect(quote.resourceId, 'moonKits');
    expect(quote.requiredKits, 1);
    expect(quote.availableKits, 0);
    final before = g.state.moneyUnits;
    expect(
      g.enqueueMapBuilding('orbital_gardens', cityId: city, plotIndex: 12),
      contains('現在0基'),
    );
    expect(g.state.moneyUnits, before);
    expect(g.state.plans, isEmpty);
    g.state.moonKits = 1;
    expect(
      g.enqueueMapBuilding('orbital_gardens', cityId: city, plotIndex: 12),
      isNull,
    );
    final p = g.state.plans.last;
    expect(p.status, 'running');
    expect(g.state.moonKits, 0);
    expect(g.state.plannedInputResources(p), {'moonKits': 1});
    final restored = GameEngine(copy(g.state));
    expect(restored.state.moonKits, 0);
    finish(restored, restored.state.plans.last);
    expect(restored.state.moonKits, 0);
    expect(restored.state.developments, hasLength(1));
    final id = restored.state.developments.single;
    final move = restored.state.buildingPreview(
      id,
      cityId: city,
      plotIndex: 8,
      relocation: true,
    );
    expect(move.resourceId, isNull);
    expect(move.requiredKits, 0);
    expect(
      restored.relocateMapBuilding(id, cityId: city, plotIndex: 8),
      isNull,
    );
    expect(
      restored.state.plannedInputResources(restored.state.plans.last),
      isEmpty,
    );
    finish(restored, restored.state.plans.last);
    expect(restored.state.moonKits, 0);
    expect(
      restored.state
          .buildingPreview(
            'local_resources',
            cityId: 'earth_delta',
            plotIndex: 12,
          )
          .requiredKits,
      0,
    );
  });
  test('Mars construction requires local cargo while legacy installation remains a paid compatibility path', () {
    final g = ready();
    const city = 'mars_arcadia';
    expect(
      g.enqueueMapBuilding('orbital_gardens', cityId: city, plotIndex: 12),
      contains('資源不足'),
    );
    expect(g.state.plans, isEmpty);
    g.state.marsKits = 2;
    expect(
      g.enqueueMapBuilding('orbital_gardens', cityId: city, plotIndex: 12),
      isNull,
    );
    final p = g.state.plans.last;
    expect(p.status, 'running');
    expect(g.state.plannedInputResources(p), {'marsKits': 1});
    expect(g.state.marsKits, 1);
    finish(g, p);
    expect(g.state.marsKits, 1);
    final legacy = ready();
    expect(legacy.enqueueDevelopment('ice_mining', cityId: city), isNull);
    expect(
      legacy.state.plannedInputResources(legacy.state.plans.last),
      isEmpty,
    );
    finish(legacy, legacy.state.plans.last);
    expect(legacy.state.marsKits, 0);
    expect(legacy.state.buildingLocations['ice_mining']!.legacySite, isTrue);
  });
}
