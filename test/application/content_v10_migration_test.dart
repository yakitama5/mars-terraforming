import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/infrastructure/file_save_store.dart';
import 'package:mars_terraforming/infrastructure/key_value_save_store.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 21);
  Map<String, dynamic> oldSnapshot() {
    final s = GameState.initial(epoch)
      ..money = 10000
      ..firstRunTutorial = FirstRunTutorialStep.completed
      ..researchPointUnits = 135 * GameState.researchPointScale + 123
      ..nextPlanId = 2;
    s.research.addAll(['lunar_shuttles', 'orbital_gardens']);
    s.developments.add('lunar_shuttles');
    s.developmentEnabled['lunar_shuttles'] = true;
    s.developmentResearchers['lunar_shuttles'] = 2;
    s.developmentCityIds['lunar_shuttles'] = 'earth_delta';
    s.plans.add(
      PlannedTask(
          id: 'plan-1',
          taskId: GameContent.developmentTaskId('orbital_gardens'),
          developmentCityId: 'earth_delta',
        )
        ..status = 'running'
        ..remainingMs = 90000
        ..iterationDurationMs = 300000
        ..iterationSpecialists = 6,
    );
    final old = s.toJson()..['contentVersion'] = 'district-9';
    for (final key in [
      'developmentTechnologyIds',
      'buildingLocations',
      'cityStocks',
      'surveyedSites',
      'connectedGridCities',
      'preparedVehicles',
      'nextBuildingId',
    ]) {
      old.remove(key);
    }
    for (final plan in old['plans'] as List) {
      for (final key in [
        'buildingInstanceId',
        'buildingPlotIndex',
        'buildingSlotIndex',
        'surveyPlotIndex',
        'relocation',
        'iterationLocalOutputs',
        'iterationBatteryUnits',
      ]) {
        (plan as Map).remove(key);
      }
    }
    return jsonDecode(jsonEncode(old)) as Map<String, dynamic>;
  }

  for (final native in [true, false]) {
    test(
      '${native ? 'file' : 'browser'} v9 paid installations retain ownership, staffing and progress without extra grants',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'mars-content-v10-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final storage = <String, String>{};
        SaveRepository repository() => native
            ? FileSaveStore(directory)
            : KeyValueSaveStore(
                read: (key) => storage[key],
                write: (key, value) => storage[key] = value,
              );
        final old = oldSnapshot();
        await repository().save(old);
        final c = GameController(repository(), now: () => epoch);
        addTearDown(c.dispose);
        await c.initialize(startTimer: false);
        expect(c.error, isNull);
        for (final key in [
          'moneyUnits',
          'researchPointUnits',
          'research',
          'developments',
          'developmentEnabled',
          'developmentResearchers',
          'developmentCityIds',
          'specialistCount',
          'researchers',
          'claimedRewards',
          'discoveredResearch',
        ]) {
          expect(c.state.toJson()[key], old[key], reason: key);
        }
        expect(c.state.developments, {'lunar_shuttles'});
        expect(c.state.developmentCityIds['lunar_shuttles'], 'earth_delta');
        expect(c.state.buildingLocations['lunar_shuttles']!.legacySite, isTrue);
        expect(c.state.buildingLocations['lunar_shuttles']!.plotIndex, -1);
        expect(c.state.cityStocks, isEmpty);
        expect(c.state.surveyedSites, isEmpty);
        expect(c.state.preparedVehicles, isEmpty);
        expect(
          c.state.developmentResearchCapacityFor('lunar_shuttles'),
          GameContent.developmentResearchCapacity('lunar_shuttles'),
        );
        expect(c.state.plans.single.remainingMs, 90000);
        expect(c.state.plans.single.iterationDurationMs, 300000);
        expect(c.state.plans.single.iterationSpecialists, 6);
        final migrated = c.state.toJson();
        expect((await repository().load()).data, migrated);
        final next = GameController(repository(), now: () => epoch);
        addTearDown(next.dispose);
        await next.initialize(startTimer: false);
        expect(next.error, isNull);
        expect(next.state.toJson(), migrated);
        final completed = GameController(
          repository(),
          now: () => epoch.add(const Duration(seconds: 90)),
        );
        addTearDown(completed.dispose);
        await completed.initialize(startTimer: false);
        expect(completed.error, isNull);
        expect(completed.state.developments, {
          'lunar_shuttles',
          'orbital_gardens',
        });
        expect(
          completed.state.buildingLocations['orbital_gardens']!.legacySite,
          isTrue,
        );
        expect(completed.state.developmentEnabled['orbital_gardens'], isFalse);
        expect(completed.state.plans.single.completedRuns, 1);
        final once = completed.state.toJson();
        final finalRestart = GameController(
          repository(),
          now: () => epoch.add(const Duration(seconds: 90)),
        );
        addTearDown(finalRestart.dispose);
        await finalRestart.initialize(startTimer: false);
        expect(finalRestart.error, isNull);
        expect(finalRestart.state.toJson(), once);
      },
    );
  }
  test('migration adds only existing HQ and paid legacy sites, and creates no new research discoveries', () {
    final old = oldSnapshot();
    final s = GameState.fromJson(old);
    expect(s.buildingLocations.keys, {'base_lab', 'lunar_shuttles'});
    expect(s.cityBuildings('moon_south_pole'), isEmpty);
    expect(s.discoveredResearchIds.toList()..sort(), old['discoveredResearch']);
    expect(s.achievements.toList(), old['achievements']);
    expect(s.claimedRewards.toList(), old['claimedRewards']);
    expect(s.cityDevelopment('earth_delta').emptyPlots, 25);
    expect(GameState.fromJson(s.toJson()).toJson(), s.toJson());
  });
  test('a paid local job survives restart and a backwards clock without paying or producing twice', () {
    final s = GameState.initial(epoch)
      ..money = 10000
      ..firstRunTutorial = FirstRunTutorialStep.completed;
    s.research.add('orbital_gardens');
    final g = GameEngine(s);
    expect(
      g.enqueueMapBuilding(
        'orbital_gardens',
        cityId: 'earth_delta',
        plotIndex: 12,
      ),
      isNull,
    );
    g.advanceBy(Duration(milliseconds: s.plans.last.remainingMs));
    final id = s.developments.single;
    expect(g.setDevelopmentEnabled(id, true), isNull);
    expect(g.enqueueBuildingWork(id, 'building_import_water'), isNull);
    g.advanceBy(Duration(milliseconds: s.plans.last.remainingMs));
    expect(g.enqueueBuildingWork(id, 'building_grow_food'), isNull);
    final p = s.plans.last;
    g.advanceBy(const Duration(seconds: 10));
    final paid = GameEngine(GameState.fromJson(s.toJson()));
    final money = paid.state.moneyUnits;
    paid.advanceTo(epoch.subtract(const Duration(hours: 1)));
    expect(paid.state.moneyUnits, money);
    expect(paid.state.cityStock('earth_delta', 'water'), 3);
    expect(paid.state.cityStock('earth_delta', 'food'), 0);
    paid.advanceBy(Duration(milliseconds: p.remainingMs));
    expect(paid.state.cityStock('earth_delta', 'food'), 3);
    expect(paid.state.cityStock('earth_delta', 'water'), 3);
    final restarted = GameEngine(GameState.fromJson(paid.state.toJson()));
    expect(restarted.state.toJson(), paid.state.toJson());
  });
}
