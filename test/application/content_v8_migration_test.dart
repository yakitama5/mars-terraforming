import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/infrastructure/file_save_store.dart';
import 'package:mars_terraforming/infrastructure/key_value_save_store.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 20);
  String technology(String catalogId) =>
      ResearchCatalog.idForCatalog(catalogId);

  Map<String, dynamic> oldSnapshot() {
    final state = GameState.initial(epoch)
      ..openingSeen = true
      ..firstRunTutorial = FirstRunTutorialStep.completed
      ..simulatedMs = 45000
      ..money = 123456
      ..specialistCount = 18
      ..researchers = 6
      ..researchPointUnits = 7 * GameState.researchPointScale + 123
      ..nextPlanId = 10
      ..contractRevenue = 321;
    state.research.addAll([
      technology('B01'),
      technology('B02'),
      technology('E01'),
      technology('E02'),
      technology('E03'),
      technology('E04'),
    ]);
    state.developments.add(technology('B01'));
    state.developmentEnabled[technology('B01')] = false;
    state.developmentResearchers[technology('B01')] = 0;
    state.developmentCityIds[technology('B01')] = 'earth_delta';
    state.partnershipChoices['research_exchange'] = 'funding';
    state.claimedRewards.add('${state.worldId}:partnership:research_exchange');
    state.plans.add(
      PlannedTask(id: 'plan-9', taskId: 'life_support')
        ..status = 'running'
        ..remainingMs = 90000
        ..iterationDurationMs = 120000
        ..iterationSpecialists = 6,
    );
    final snapshot = state.toJson()
      ..['contentVersion'] = 'district-7'
      ..remove('discoveredResearch');
    // v7 had no physical building metadata or local-work iteration fields.
    for (final key in [
      'developmentTechnologyIds',
      'buildingLocations',
      'cityStocks',
      'surveyedSites',
      'connectedGridCities',
      'preparedVehicles',
      'nextBuildingId',
    ]) {
      snapshot.remove(key);
    }
    for (final plan in snapshot['plans'] as List) {
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
    return jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  }

  // These were the visible roots after two bio and four energy completions in
  // v7. In particular, they include unresearched, unreserved independent roots.
  final historicalRoots = {
    for (final id in [
      'B01',
      'B05',
      'B09',
      'M22',
      'R01',
      'E01',
      'E13',
      'E09',
      'E21',
      'E10',
    ])
      technology(id),
  };

  for (final native in [true, false]) {
    test(
      '${native ? 'file' : 'browser'} v7 preserves its known frontier, agency and paid reservation',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'mars-research-v8-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final storage = <String, String>{};
        SaveRepository repository() => native
            ? FileSaveStore(directory)
            : KeyValueSaveStore(
                read: (key) => storage[key],
                write: (key, value) => storage[key] = value,
              );
        final legacy = oldSnapshot();
        await repository().save(legacy);
        final first = GameController(repository(), now: () => epoch);
        addTearDown(first.dispose);
        await first.initialize(startTimer: false);
        expect(first.error, isNull);
        final state = first.state;
        for (final key in [
          'worldId',
          'lastWallClockMs',
          'simulatedMs',
          'moneyUnits',
          'specialistCount',
          'researchers',
          'researchPointUnits',
          'contractRevenue',
          'research',
          'partnershipChoices',
          'claimedRewards',
          'developments',
          'developmentEnabled',
          'developmentResearchers',
          'developmentCityIds',
        ]) {
          expect(state.toJson()[key], legacy[key], reason: key);
        }
        for (final entry in (legacy['plans'] as List).single.entries) {
          expect(
            state.plans.single.toJson()[entry.key],
            entry.value,
            reason: 'paid plan ${entry.key}',
          );
        }
        expect(state.discoveredResearchIds, containsAll(historicalRoots));
        expect(state.research, isNot(contains(technology('B09'))));
        expect(state.plans.single.taskId, isNot(technology('B09')));
        expect(state.researchPointsPerMinute, greaterThan(0));
        final migrated = state.toJson();
        expect(migrated['contentVersion'], GameContent.version);
        expect(migrated['discoveredResearch'], containsAll(historicalRoots));
        expect((await repository().load()).data, migrated);

        final again = GameController(repository(), now: () => epoch);
        addTearDown(again.dispose);
        await again.initialize(startTimer: false);
        expect(again.error, isNull);
        expect(again.state.toJson(), migrated);

        final end = epoch.add(const Duration(seconds: 90));
        final finished = GameController(repository(), now: () => end);
        addTearDown(finished.dispose);
        await finished.initialize(startTimer: false);
        expect(finished.error, isNull);
        expect(finished.state.plans.single.status, 'completed');
        expect(finished.state.plans.single.completedRuns, 1);
        expect(finished.state.research, contains('life_support'));
        expect(
          finished.state.researchPointUnits,
          greaterThan(legacy['researchPointUnits'] as int),
        );
        expect(
          finished.state.discoveredResearchIds,
          containsAll(historicalRoots),
        );
        final completed = finished.state.toJson();

        final repeat = GameController(repository(), now: () => end);
        addTearDown(repeat.dispose);
        await repeat.initialize(startTimer: false);
        expect(repeat.error, isNull);
        expect(repeat.state.toJson(), completed);
        expect(repeat.engine!.unlockResearch('life_support'), isNotNull);
        expect(
          repeat.state.researchPointUnits,
          finished.state.researchPointUnits,
        );
        expect(repeat.state.plans.single.completedRuns, 1);
      },
    );
  }

  test(
    'all earlier supported contents restore the historical known frontier',
    () {
      for (final version in [
        'prototype-1',
        'district-2',
        'district-3',
        'district-4',
        'district-5',
        'district-6',
      ]) {
        final snapshot = oldSnapshot()
          ..['contentVersion'] = version
          ..['schemaVersion'] = version == 'prototype-1'
              ? 1
              : GameState.schemaVersion
          ..['plans'] = []
          ..['developments'] = []
          ..['developmentEnabled'] = <String, bool>{}
          ..['developmentResearchers'] = <String, int>{}
          ..['developmentCityIds'] = <String, String>{}
          ..['partnershipChoices'] = <String, String>{};
        final migrated = GameState.fromJson(snapshot);
        expect(
          migrated.discoveredResearchIds,
          containsAll(historicalRoots),
          reason: version,
        );
        expect(
          GameState.fromJson(migrated.toJson()).discoveredResearchIds,
          migrated.discoveredResearchIds,
          reason: version,
        );
        expect(
          migrated.researchPointUnits,
          snapshot['researchPointUnits'],
          reason: version,
        );
      }
    },
  );

  test('saved knowledge is unioned with newly eligible candidates', () {
    final saved = GameState.initial(epoch).toJson()
      ..['discoveredResearch'] = [technology('E10')]
      ..['research'] = [technology('B01')]
      ..['nextPlanId'] = 2
      ..['plans'] = [
        PlannedTask(id: 'plan-1', taskId: 'intercity_logistics').toJson(),
      ];
    final state = GameState.fromJson(saved);
    expect(state.discoveredResearchIds, contains(technology('E10')));
    expect(state.research, isNot(contains(technology('E10'))));
    expect(state.discoveredResearchIds, contains(technology('B02')));
    expect(state.discoveredResearchIds, contains('intercity_logistics'));
    expect(state.plans.single.status, 'queued');
    expect(
      state.discoveredResearchIds,
      containsAll(GameContent.starterResearchCatalogIds.map(technology)),
    );
    expect(
      GameState.fromJson(state.toJson()).discoveredResearchIds,
      state.discoveredResearchIds,
    );
    expect(saved['discoveredResearch'], [technology('E10')]);
  });

  test('reading new candidates does not mutate the stored knowledge', () {
    final candidate = ResearchCatalog.purchasableTechnologies.firstWhere(
      (technology) =>
          GameContent.researchDiscoveryParentIds(technology.id).isNotEmpty,
    );
    final parents = GameContent.researchDiscoveryParentIds(candidate.id);
    final state = GameState.initial(epoch);
    state.research.addAll(parents);
    expect(state.discoveredResearchIds, contains(candidate.id));
    expect(state.discoveredResearchIds, contains(candidate.id));
    state.research.removeAll(parents);
    expect(state.discoveredResearchIds, isNot(contains(candidate.id)));
  });

  test(
    'a current fixture without the optional key uses only current discovery',
    () {
      final saved = GameState.fromJson(oldSnapshot()).toJson()
        ..['plans'] = []
        ..remove('discoveredResearch');
      final current = GameState.fromJson(saved);
      final expected = GameState.initial(epoch);
      expected.research.addAll((saved['research'] as List).cast<String>());
      expect(current.discoveredResearchIds, expected.discoveredResearchIds);
      expect(current.toJson()['discoveredResearch'], isA<List<String>>());
    },
  );

  for (final invalid in <Object?>[
    null,
    'B01',
    <String, String>{},
    [42],
    ['unknown_future_technology'],
    ['factory_contract'],
    [technology('E06')],
  ]) {
    test(
      'invalid current known research is rejected without overwriting: $invalid',
      () async {
        final snapshot = GameState.initial(epoch).toJson()
          ..['discoveredResearch'] = invalid;
        expect(() => GameState.fromJson(snapshot), throwsFormatException);
        final storage = <String, String>{};
        KeyValueSaveStore repository() => KeyValueSaveStore(
          read: (key) => storage[key],
          write: (key, value) => storage[key] = value,
        );
        await repository().save(snapshot);
        final original = Map<String, String>.of(storage);
        final controller = GameController(repository(), now: () => epoch);
        addTearDown(controller.dispose);
        await controller.initialize(startTimer: false);
        expect(controller.engine, isNull);
        expect(controller.error, contains('既知の研究'));
        expect(storage, original);
      },
    );
  }
}
