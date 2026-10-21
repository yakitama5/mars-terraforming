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
  Map<String, dynamic> oldSnapshot({bool paidCargo = false}) {
    final state = GameState.initial(epoch)
      ..openingSeen = true
      ..firstRunTutorial = FirstRunTutorialStep.completed
      ..money = 10000
      ..researchPointUnits = 789 * GameState.researchPointScale + 123
      ..nextPlanId = 2;
    state.research.add('life_support');
    if (paidCargo) {
      state.plans.add(
        PlannedTask(id: 'plan-1', taskId: 'mars_delivery')
          ..status = 'running'
          ..remainingMs = 90000
          ..iterationDurationMs = 180000,
      );
    }
    final snapshot = state.toJson()
      ..['contentVersion'] = 'district-8'
      ..remove('moonKits')
      ..remove('legacyUnlockedPlanets');
    (snapshot['facilities'] as Map).remove('moon');
    return jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  }

  for (final native in [true, false]) {
    test(
      '${native ? 'file' : 'browser'} v8 paid cargo migrates and completes exactly once',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'mars-content-v9-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final storage = <String, String>{};
        SaveRepository repository() => native
            ? FileSaveStore(directory)
            : KeyValueSaveStore(
                read: (key) => storage[key],
                write: (key, value) => storage[key] = value,
              );
        final old = oldSnapshot(paidCargo: true);
        await repository().save(old);
        final first = GameController(repository(), now: () => epoch);
        addTearDown(first.dispose);
        await first.initialize(startTimer: false);
        expect(first.error, isNull);
        expect(first.state.planetUnlocked('moon'), isTrue);
        expect(first.state.planetUnlocked('mars'), isTrue);
        expect(first.state.moonKits, 0);
        expect(first.state.facilities['moon'], isTrue);
        expect(first.state.districtCount('moon_outpost'), 0);
        expect(first.state.districtCount('moon_spaceport'), 0);
        for (final key in [
          'moneyUnits',
          'researchPointUnits',
          'plans',
          'research',
          'claimedRewards',
          'discoveredResearch',
        ]) {
          expect(first.state.toJson()[key], old[key], reason: key);
        }
        expect(first.state.toJson()['contentVersion'], GameContent.version);
        final migrated = first.state.toJson();
        expect((await repository().load()).data, migrated);
        final again = GameController(repository(), now: () => epoch);
        addTearDown(again.dispose);
        await again.initialize(startTimer: false);
        expect(again.error, isNull);
        expect(again.state.toJson(), migrated);

        final completionTime = epoch.add(const Duration(seconds: 90));
        final finished = GameController(
          repository(),
          now: () => completionTime,
        );
        addTearDown(finished.dispose);
        await finished.initialize(startTimer: false);
        expect(finished.error, isNull);
        expect(finished.state.marsKits, 1);
        expect(finished.state.earthKits, 0);
        expect(finished.state.plans.single.completedRuns, 1);
        final completed = finished.state.toJson();
        final restarted = GameController(
          repository(),
          now: () => completionTime,
        );
        addTearDown(restarted.dispose);
        await restarted.initialize(startTimer: false);
        expect(restarted.error, isNull);
        expect(restarted.state.toJson(), completed);
      },
    );
  }

  test('an unlaunched v8 world follows the new progression and keeps known research', () {
    final old = oldSnapshot();
    final state = GameState.fromJson(old);
    expect(state.planetUnlocked('earth'), isTrue);
    expect(state.planetUnlocked('moon'), isFalse);
    expect(state.planetUnlocked('mars'), isFalse);
    expect(
      state.discoveredResearchIds.toList()..sort(),
      old['discoveredResearch'],
    );
    expect(state.researchPointUnits, old['researchPointUnits']);
    expect(state.claimedRewards, isEmpty);
  });

  test('old completed launches open the Moon without inventing facilities or rewards', () {
    final old = oldSnapshot();
    old['plans'] = [
      PlannedTask(id: 'plan-1', taskId: 'launch_contract', remainingRepeats: 0)
        ..status = 'completed'
        ..completedRuns = 1,
    ].map((plan) => plan.toJson()).toList();
    final state = GameState.fromJson(old);
    expect(state.planetUnlocked('moon'), isTrue);
    expect(state.planetUnlocked('mars'), isFalse);
    expect(state.achievements, isEmpty);
    expect(state.claimedRewards, isEmpty);
    expect(state.moneyUnits, old['moneyUnits']);
  });

  test('all forms of old Mars progress retain access without free lunar construction', () {
    for (final field in ['marsKits', 'marsHabitats', 'marsResidents']) {
      final old = oldSnapshot()..[field] = 1;
      final state = GameState.fromJson(old);
      expect(state.planetUnlocked('moon'), isTrue, reason: field);
      expect(state.planetUnlocked('mars'), isTrue, reason: field);
      expect(state.districts, isEmpty);
      expect(state.claimedRewards, isEmpty);
      expect(GameState.fromJson(state.toJson()).legacyUnlockedPlanets, {
        'moon',
        'mars',
      });
    }
  });

  test(
    'old unpaid Mars reservations retain their route without free lunar assets',
    () {
      for (final taskId in [
        'mars_delivery',
        'cargo_delivery',
        'build_habitat',
      ]) {
        final old = oldSnapshot();
        old['plans'] = [PlannedTask(id: 'plan-1', taskId: taskId).toJson()];
        final state = GameState.fromJson(old);
        final game = GameEngine(state);
        expect(state.planetUnlocked('moon'), isTrue, reason: taskId);
        expect(state.planetUnlocked('mars'), isTrue, reason: taskId);
        expect(state.moonKits, 0);
        expect(state.districtCount('moon_outpost'), 0);
        expect(state.plans.single.status, 'queued');
        expect(state.plans.single.remainingMs, 0);
        expect(state.moneyUnits, old['moneyUnits']);
        expect(state.plans.single.stopReason, isNot(contains('火星探査機')));
        expect(state.plans.single.stopReason, isNot(contains('ロケット打ち上げ')));
        expect(GameState.fromJson(game.state.toJson()).legacyUnlockedPlanets, {
          'moon',
          'mars',
        });
      }
    },
  );

  test('current lunar cargo and access survive clock rollback with no duplicate delivery', () {
    final state = GameState.initial(epoch)
      ..money = 10000
      ..earthKits = 1;
    state.achievements.add('first_launch');
    final game = GameEngine(state);
    expect(game.enqueue('moon_delivery'), isNull);
    game.advanceTo(epoch.add(const Duration(seconds: 150)));
    expect(state.moonKits, 1);
    final before = state.toJson();
    final restart = GameEngine(GameState.fromJson(before));
    restart.advanceTo(epoch.subtract(const Duration(days: 1)));
    expect(restart.state.moonKits, 1);
    expect(restart.state.earthKits, 0);
    expect(restart.state.plans.single.completedRuns, 1);
    expect(restart.state.claimedRewards.toList(), before['claimedRewards']);
    restart.advanceTo(
      epoch.subtract(const Duration(days: 1)).add(const Duration(seconds: 150)),
    );
    expect(restart.state.moonKits, 1);
  });

  test('invalid lunar stock and unknown access flags fail without normalizing them', () {
    final current = GameState.initial(epoch).toJson();
    expect(
      () => GameState.fromJson({...current, 'moonKits': -1}),
      throwsFormatException,
    );
    expect(
      () => GameState.fromJson({
        ...current,
        'legacyUnlockedPlanets': ['jupiter'],
      }),
      throwsFormatException,
    );
  });
}
