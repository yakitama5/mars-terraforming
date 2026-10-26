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
  final epoch = DateTime.utc(2026, 10, 20);

  Map<String, dynamic> oldSnapshot({required bool paidResearch}) {
    final state = GameState.initial(epoch)
      ..openingSeen = true
      ..firstRunTutorial = FirstRunTutorialStep.completed
      ..money = 100000
      ..specialistCount = 18
      ..researchers = 6
      ..nextPlanId = 10;
    state.research.add('oxygen_pilot');
    state.partnershipChoices['research_exchange'] = 'funding';
    state.claimedRewards.add('${state.worldId}:partnership:research_exchange');
    final snapshot = state.toJson()
      ..['contentVersion'] = 'district-6'
      ..['plans'] = [
        {
          'id': 'plan-9',
          'taskId': 'life_support',
          'remainingRepeats': 1,
          'completedRuns': 0,
          'status': paidResearch ? 'running' : 'queued',
          'stopReason': paidResearch ? '' : '資金不足',
          'remainingMs': paidResearch ? 90000 : 0,
          'iterationDurationMs': paidResearch ? 120000 : 0,
          'iterationSpecialists': paidResearch ? 6 : 0,
          'cityId': null,
          'plotIndex': null,
          'targetLevel': null,
        },
      ];
    for (final field in [
      'researchPointUnits',
      'developments',
      'developmentEnabled',
      'developmentResearchers',
      'developmentCityIds',
    ]) {
      snapshot.remove(field);
    }
    return jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  }

  for (final native in [true, false]) {
    test(
      '${native ? 'file' : 'browser'} v6 keeps paid research and never grants retrospective RP',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'mars-research-v7-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final storage = <String, String>{};
        SaveRepository repository() => native
            ? FileSaveStore(directory)
            : KeyValueSaveStore(
                read: (key) => storage[key],
                write: (key, value) => storage[key] = value,
              );
        final legacy = oldSnapshot(paidResearch: true);
        await repository().save(legacy);
        final first = GameController(repository(), now: () => epoch);
        addTearDown(first.dispose);
        await first.initialize(startTimer: false);
        expect(first.error, isNull);
        expect(first.state.worldId, legacy['worldId']);
        expect(first.state.moneyUnits, legacy['moneyUnits']);
        expect(first.state.specialistCount, 18);
        expect(first.state.researchers, 6);
        expect(first.state.researchPointUnits, 0);
        expect(first.state.developments, isEmpty);
        expect(first.state.research, {'oxygen_pilot'});
        expect(first.state.partnershipChoices, legacy['partnershipChoices']);
        expect(first.state.claimedRewards, legacy['claimedRewards']);
        final paid = first.state.plans.single;
        expect(paid.status, 'running');
        expect(paid.remainingMs, 90000);
        expect(paid.iterationDurationMs, 120000);
        expect(paid.iterationSpecialists, 6);
        expect(first.state.reservedResearchers, 6);
        expect(first.state.labResearchers, 0);
        expect(first.state.researchPointsPerMinute, greaterThan(0));
        expect(first.state.toJson()['contentVersion'], GameContent.version);
        final migrated = first.state.toJson();
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
        expect(finished.state.research, {'oxygen_pilot', 'life_support'});
        expect(finished.state.researchPointUnits, greaterThan(0));
        expect(finished.state.reservedResearchers, 0);
        expect(finished.state.developments, isEmpty);
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

  test('unpaid v6 research keeps its reservation and waits for common RP', () {
    final legacy = oldSnapshot(paidResearch: false);
    final state = GameState.fromJson(legacy);
    final money = state.moneyUnits;
    final engine = GameEngine(state);
    expect(state.researchPointUnits, 0);
    expect(state.plans.single.id, 'plan-9');
    expect(state.plans.single.status, 'queued');
    expect(state.plans.single.completedRuns, 0);
    expect(state.moneyUnits, money);
    expect(state.research, {'oxygen_pilot'});
    engine.advanceBy(const Duration(days: 1));
    expect(state.research, {'oxygen_pilot'});
    expect(state.plans.single.requiresManualStart, isTrue);
    expect(engine.startPlan(state.plans.single.id), isNull);
    expect(state.research, {'oxygen_pilot', 'life_support'});
    expect(state.plans.single.completedRuns, 1);
    expect(state.plans.single.status, 'completed');
    expect(state.developments, isEmpty);
    final saved = state.toJson();
    final roundTrip = GameEngine(GameState.fromJson(saved));
    roundTrip.advanceTo(epoch);
    expect(roundTrip.state.research, state.research);
    expect(roundTrip.state.researchPointUnits, state.researchPointUnits);
    expect(roundTrip.state.plans.single.completedRuns, 1);
  });

  test('restoring a v6 clock backwards does not retroactively produce research points', () {
    final legacy = oldSnapshot(paidResearch: false);
    final state = GameState.fromJson(legacy);
    final engine = GameEngine(state);
    engine.advanceTo(epoch.subtract(const Duration(days: 3)));
    expect(state.simulatedMs, 0);
    expect(state.researchPointUnits, 0);
    expect(state.research, {'oxygen_pilot'});
    expect(state.plans.single.status, 'queued');
    engine.advanceTo(
      epoch.subtract(const Duration(days: 3)).add(const Duration(minutes: 1)),
    );
    expect(state.simulatedMs, 60000);
    expect(state.researchPointUnits, greaterThanOrEqualTo(0));
  });

  for (final step in [
    FirstRunTutorialStep.placeHousing,
    FirstRunTutorialStep.income,
    FirstRunTutorialStep.startResearch,
  ]) {
    test(
      'v6 protected ${step.name} tutorial receives its first research budget once',
      () {
        final legacy = oldSnapshot(paidResearch: false)
          ..['firstRunTutorial'] = step.name
          ..['plans'] = [];
        final state = GameState.fromJson(legacy);
        final support =
            GameContent.researchPointCost('life_support') *
            GameState.researchPointScale;
        expect(state.introductionPausesClock, isTrue);
        expect(state.researchPointUnits, support);
        expect(state.research, isNot(contains('life_support')));
        expect(state.developments, isEmpty);

        final migrated = state.toJson();
        expect(migrated.containsKey('researchPointUnits'), isTrue);
        final restored = GameState.fromJson(migrated);
        expect(restored.researchPointUnits, support);

        // An explicit current-generation zero is a spent bank, even while the
        // protected tutorial still has not completed its first research.
        final spent = restored.toJson()..['researchPointUnits'] = 0;
        final reloaded = GameState.fromJson(spent);
        expect(reloaded.researchPointUnits, 0);
        expect(reloaded.research, isNot(contains('life_support')));
      },
    );
  }

  test('v6 protected research step can unlock immediately with its one-time support', () {
    final legacy = oldSnapshot(paidResearch: false)
      ..['firstRunTutorial'] = FirstRunTutorialStep.startResearch.name
      ..['plans'] = [];
    final engine = GameEngine(GameState.fromJson(legacy));
    final money = engine.state.moneyUnits;
    expect(engine.state.introductionPausesClock, isTrue);
    expect(engine.unlockResearch('life_support'), isNull);
    expect(engine.state.research, contains('life_support'));
    expect(engine.state.researchPointUnits, 0);
    expect(engine.state.moneyUnits, money);
    expect(engine.state.simulatedMs, 0);
    expect(GameState.fromJson(engine.state.toJson()).researchPointUnits, 0);
  });

  test(
    'v6 protected tutorial never duplicates an already paid first research',
    () {
      final legacy = oldSnapshot(paidResearch: true)
        ..['firstRunTutorial'] = FirstRunTutorialStep.startResearch.name;
      final state = GameState.fromJson(legacy);
      expect(state.introductionPausesClock, isTrue);
      expect(state.researchPointUnits, 0);
      expect(state.plans.single.status, 'running');
      expect(state.plans.single.remainingMs, 90000);
      expect(state.plans.single.iterationDurationMs, 120000);
      expect(GameState.fromJson(state.toJson()).researchPointUnits, 0);
    },
  );

  test('v6 protected tutorial receives no support after its first research was earned', () {
    final legacy = oldSnapshot(paidResearch: false)
      ..['firstRunTutorial'] = FirstRunTutorialStep.income.name
      ..['plans'] = []
      ..['research'] = ['oxygen_pilot', 'life_support'];
    final state = GameState.fromJson(legacy);
    expect(state.introductionPausesClock, isTrue);
    expect(state.researchPointUnits, 0);
    expect(state.research, {'oxygen_pilot', 'life_support'});
    expect(state.developments, isEmpty);
    expect(GameState.fromJson(state.toJson()).researchPointUnits, 0);
  });
}
