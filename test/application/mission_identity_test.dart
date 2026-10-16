import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/onboarding_guide.dart';
import 'package:mars_terraforming/domain/save_repository.dart';

class _MissionSave implements SaveRepository {
  Map<String, dynamic>? data;
  bool fail = false;

  @override
  Future<SaveLoadResult> load() async =>
      SaveLoadResult(data: data, recovered: false, generation: 1);

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    if (fail) throw StateError('disk full');
    data = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  }
}

void main() {
  final epoch = DateTime.utc(2026, 10, 16);

  test('only a newly created world requires the opening', () {
    final state = GameState.initial(epoch);
    expect(state.openingSeen, isFalse);
    final old = state.toJson()
      ..remove('missionIdentity')
      ..remove('openingSeen');
    final restored = GameState.fromJson(old);
    expect(restored.openingSeen, isTrue);
    expect(
      restored.cityName('earth_delta'),
      GameContent.cities['earth_delta']!.name,
    );
    expect(restored.rocketName, 'あかつき');
    expect(restored.worldId, state.worldId);
    expect(restored.moneyUnits, state.moneyUnits);
  });

  for (final fixture in [
    'prototype_v1',
    'district_v2',
    'district_v3',
    'district_v4',
  ]) {
    test('$fixture migrates directly into its existing world', () {
      final saved = jsonDecode(
        File('test/fixtures/$fixture.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final state = GameState.fromJson(saved);
      expect(state.openingSeen, isTrue);
      expect(state.worldId, saved['worldId']);
      expect(state.claimedRewards, saved['claimedRewards']);
    });
  }

  test('custom names preserve plans, stable IDs, payouts and progress after restart', () async {
    final store = _MissionSave();
    final controller = GameController(store, now: () => epoch);
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    await controller.command(
      (engine) => engine.enqueueDistrict('earth_delta', 0, 'housing'),
    );
    final before = controller.state.toJson();
    await controller.updateMissionIdentity(
      cities: {'earth_delta': '  青空市  ', 'mars_arcadia': '夜明け'},
      rocket: 'はるか',
      finishOpening: true,
    );
    expect(controller.state.cityName('earth_delta'), '青空市');
    expect(controller.state.rocketName, 'はるか');
    expect(controller.state.worldId, before['worldId']);
    expect(controller.state.moneyUnits, before['moneyUnits']);
    expect(controller.state.plans.single.cityId, 'earth_delta');
    expect(
      controller.state.plans.single.toJson(),
      (before['plans'] as List).single,
    );
    final resumed = GameController(store, now: () => epoch);
    await resumed.initialize(startTimer: false);
    addTearDown(resumed.dispose);
    expect(resumed.state.openingSeen, isTrue);
    expect(resumed.state.toJson(), controller.state.toJson());
    final bulk = GameEngine(GameState.fromJson(resumed.state.toJson()));
    final split = GameEngine(GameState.fromJson(resumed.state.toJson()));
    bulk.advanceBy(const Duration(minutes: 10));
    for (var i = 0; i < 10; i++) {
      split.advanceBy(const Duration(minutes: 1));
    }
    expect(split.state.toJson(), bulk.state.toJson());
    expect(bulk.state.districtAt('earth_delta', 0), isNotNull);
    expect(bulk.state.identity.toJson(), resumed.state.identity.toJson());
  });

  test(
    'invalid names cannot finish the opening or partly change identity',
    () async {
      final controller = GameController(_MissionSave(), now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      final initial = controller.state.identity.toJson();
      for (final invalid in ['', '   ', 'あ' * 25, '街\n街', '\u202e街']) {
        await controller.updateMissionIdentity(
          cities: {'earth_delta': '青空市'},
          rocket: invalid,
          finishOpening: true,
        );
        expect(controller.state.identity.toJson(), initial);
        expect(controller.state.openingSeen, isFalse);
      }
      expect(
        () => const MissionIdentity().renamed(cities: {'missing_city': '街'}),
        throwsFormatException,
      );
    },
  );

  test(
    'save failure keeps setup pending and can be retried with the same names',
    () async {
      final store = _MissionSave();
      final controller = GameController(store, now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      store.fail = true;
      await controller.updateMissionIdentity(
        cities: {'earth_delta': '青空市'},
        rocket: 'はるか',
        finishOpening: true,
      );
      expect(controller.error, isNotNull);
      expect(controller.state.openingSeen, isFalse);
      expect(store.data!['openingSeen'], isFalse);
      store.fail = false;
      await controller.updateMissionIdentity(
        cities: {'earth_delta': '青空市'},
        rocket: 'はるか',
        finishOpening: true,
      );
      expect(controller.error, isNull);
      expect(controller.state.openingSeen, isTrue);
      expect(GameState.fromJson(store.data!).cityName('earth_delta'), '青空市');
    },
  );

  test(
    'skipping introduction retains milestones and can survive restart',
    () async {
      final store = _MissionSave();
      final controller = GameController(store, now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await controller.skipOpening();
      expect(controller.state.openingSeen, isTrue);
      expect(OnboardingGuide.fromState(controller.state).completedCount, 0);
      expect(controller.state.research, isEmpty);
      expect(controller.state.claimedRewards, isEmpty);
      expect(GameState.fromJson(store.data!).openingSeen, isTrue);
    },
  );

  test(
    'story uses chosen names without modifying onboarding completion rules',
    () {
      final state = GameState.initial(epoch);
      state.identity = state.identity.renamed(
        cities: {'earth_delta': '青空市', 'mars_arcadia': '夜明け'},
        rocket: 'はるか',
      );
      final guide = OnboardingGuide.fromState(state);
      expect(
        guide.steps.firstWhere((step) => step.id == 'first_district').story,
        contains('青空市'),
      );
      expect(
        guide.steps.firstWhere((step) => step.id == 'first_landing').story,
        contains('はるか'),
      );
      expect(
        guide.steps.firstWhere((step) => step.id == 'first_landing').story,
        contains('夜明け'),
      );
      expect(guide.completedCount, 0);
    },
  );
  test(
    'reading and interrupted setup never spend money, including clock changes',
    () async {
      var now = epoch;
      final store = _MissionSave();
      final controller = GameController(store, now: () => now);
      await controller.initialize(startTimer: false);
      // Exercise the OP clock independently of the required hands-on tutorial.
      controller.state.firstRunTutorial = FirstRunTutorialStep.completed;
      controller.beginOpening();
      await controller.save();
      final money = controller.state.moneyUnits;
      now = epoch.add(const Duration(hours: 3));
      await controller.resume();
      expect(controller.state.simulatedMs, 0);
      expect(controller.state.moneyUnits, money);
      now = epoch.subtract(const Duration(days: 2));
      await controller.resume();
      expect(controller.state.moneyUnits, money);
      expect(controller.state.lastWallClockMs, now.millisecondsSinceEpoch);
      controller.dispose();
      now = epoch.add(const Duration(days: 2));
      final restarted = GameController(store, now: () => now);
      await restarted.initialize(startTimer: false);
      addTearDown(restarted.dispose);
      expect(restarted.state.simulatedMs, 0);
      expect(restarted.state.moneyUnits, money);
      await restarted.skipOpening();
      await restarted.resume();
      expect(restarted.state.simulatedMs, 0);
      now = now.add(const Duration(minutes: 1));
      await restarted.resume();
      expect(restarted.state.simulatedMs, 60000);
      expect(
        restarted.state.moneyUnits,
        money + restarted.state.netPerMinute * GameState.moneyScale,
      );
      final saved = restarted.state.toJson();
      final again = GameController(store, now: () => now);
      await again.initialize(startTimer: false);
      addTearDown(again.dispose);
      expect(again.state.toJson(), saved);
    },
  );

  test('successful naming fixes the clock baseline and replay does not suspend play', () async {
    var now = epoch;
    final controller = GameController(_MissionSave(), now: () => now);
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    controller.state.firstRunTutorial = FirstRunTutorialStep.completed;
    controller.beginOpening();
    now = epoch.add(const Duration(hours: 2));
    await controller.updateMissionIdentity(
      cities: {},
      rocket: 'はるか',
      finishOpening: true,
    );
    expect(controller.state.simulatedMs, 0);
    final baseline = controller.state.moneyUnits;
    controller
        .beginOpening(); // Replaying an already seen OP cannot freeze a world.
    now = now.add(const Duration(minutes: 1));
    await controller.resume();
    expect(controller.state.simulatedMs, 60000);
    expect(
      controller.state.moneyUnits,
      baseline + controller.state.netPerMinute * GameState.moneyScale,
    );
  });
}
