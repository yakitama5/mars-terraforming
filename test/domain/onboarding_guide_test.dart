import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/onboarding_guide.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 15);
  OnboardingStep step(GameState state, String id) =>
      OnboardingGuide.fromState(state).steps
          .firstWhere((step) => step.id == id);

  test(
    'elapsed time never completes an unplayed tutorial or changes state',
    () {
      final state = GameState.initial(epoch)..simulatedMs = 7200000;
      final before = jsonEncode(state.toJson());
      final guide = OnboardingGuide.fromState(state);
      expect(guide.completedCount, 0);
      expect(guide.elapsedMs, 7200000);
      expect(guide.isComplete, isFalse);
      expect(step(state, 'first_research').status, OnboardingStatus.available);
      expect(step(state, 'first_district').status, OnboardingStatus.available);
      expect(step(state, 'first_kit').status, OnboardingStatus.locked);
      expect(jsonEncode(state.toJson()), before);
    },
  );

  test(
    'the guide opens each destination through launch and lunar milestones',
    () {
      final state = GameState.initial(epoch);
      expect(step(state, 'first_launch').isCompleted, isFalse);
      expect(step(state, 'moon_base').status, OnboardingStatus.locked);
      expect(step(state, 'mars_probe').status, OnboardingStatus.locked);
      expect(step(state, 'first_landing').reason, contains('月面基地'));
      state.achievements.add('first_launch');
      expect(step(state, 'first_launch').isCompleted, isTrue);
      expect(
        step(state, 'moon_base').destination,
        OnboardingDestination.operations,
      );
      expect(step(state, 'moon_base').target, '2');
      state.moonKits = 1;
      expect(step(state, 'moon_base').destination, OnboardingDestination.city);
      expect(step(state, 'moon_base').target, 'moon_south_pole');
      state.achievements.addAll(['first_launch', 'mars_route_open']);
      expect(step(state, 'moon_base').isCompleted, isTrue);
      expect(step(state, 'mars_probe').isCompleted, isTrue);
      expect(step(state, 'first_landing').isCompleted, isFalse);
    },
  );

  test('RP reservations and already-paid research retain their real state', () {
    final engine = GameEngine(
      GameState.initial(epoch)
        ..money = 100000
        ..researchPointUnits = 0,
    );
    engine.enqueue('life_support');
    expect(
      step(engine.state, 'first_research').status,
      OnboardingStatus.queued,
    );
    engine.advanceBy(const Duration(minutes: 10));
    expect(
      step(engine.state, 'first_research').status,
      OnboardingStatus.completed,
    );

    final legacy = PlannedTask(id: 'paid-research', taskId: 'life_support')
      ..status = 'running'
      ..remainingMs = 120000
      ..iterationDurationMs = 120000
      ..iterationSpecialists = GameContent.baselineDepartmentStaff;
    final running = GameEngine(GameState.initial(epoch)..plans.add(legacy));
    expect(
      step(running.state, 'first_research').status,
      OnboardingStatus.running,
    );
    final remaining = step(running.state, 'first_research').remainingMs;
    running.setFacilityEnabled('lab', false);
    final paused = step(running.state, 'first_research');
    expect(paused.status, OnboardingStatus.stopped);
    expect(paused.destination, OnboardingDestination.operations);
    expect(paused.target, '0');
    expect(paused.facilityId, 'lab');
    expect(paused.reason, contains('設備休止中'));
    expect(paused.remainingMs, remaining);
  });

  test('cancelled research is offered again and is never marked achieved', () {
    final engine = GameEngine(
      GameState.initial(epoch)
        ..money = 100000
        ..researchPointUnits = 0,
    );
    engine.enqueue('life_support');
    engine.cancelQueued(engine.state.plans.last.id);
    expect(
      step(engine.state, 'first_research').status,
      OnboardingStatus.available,
    );
    expect(OnboardingGuide.fromState(engine.state).completedCount, 0);
  });

  test('RP accumulation is a reservation and a paused source is stopped', () {
    final engine = GameEngine(GameState.initial(epoch)..researchPointUnits = 0);
    engine.assignResearchers(0);
    engine.enqueue('life_support');
    final waiting = step(engine.state, 'first_research');
    expect(waiting.status, OnboardingStatus.queued);
    expect(waiting.reason, contains('研究ポイント待ち'));
    expect(waiting.destination, OnboardingDestination.operations);
    engine.setFacilityEnabled('lab', false);
    expect(
      step(engine.state, 'first_research').status,
      OnboardingStatus.stopped,
    );
  });

  test(
    'kit milestone survives consumption by an in-flight delivery and reload',
    () {
      final engine = GameEngine(GameState.initial(epoch)..money = 100000);
      engine.state.research.add('life_support');
      engine.enqueue('habitat_kit');
      engine.advanceBy(const Duration(minutes: 3));
      expect(step(engine.state, 'first_kit').isCompleted, isTrue);
      engine.state.achievements.addAll(['first_launch', 'mars_route_open']);
      engine.enqueue('mars_delivery');
      expect(engine.state.earthKits, 0);
      expect(step(engine.state, 'first_kit').isCompleted, isTrue);
      final reloaded = GameState.fromJson(
        jsonDecode(jsonEncode(engine.state.toJson())) as Map<String, dynamic>,
      );
      expect(step(reloaded, 'first_kit').isCompleted, isTrue);
      expect(step(reloaded, 'first_landing').status, OnboardingStatus.running);
    },
  );

  test(
    'arrival requires an explicit habitat choice without choosing for player',
    () {
      final state = GameState.initial(epoch)
        ..achievements.add('first_landing')
        ..marsKits = 1;
      var landing = step(state, 'first_landing');
      expect(landing.status, OnboardingStatus.available);
      expect(landing.title, contains('方式'));
      expect(state.habitatChoice, isNull);
      expect(step(state, 'first_habitat').status, OnboardingStatus.locked);
      state.habitatChoice = 'dome';
      landing = step(state, 'first_landing');
      expect(landing.isCompleted, isTrue);
      expect(step(state, 'first_habitat').status, OnboardingStatus.available);
    },
  );

  test(
    'older saves recognize past development without needing task history',
    () {
      final state = GameState.initial(epoch)
        ..earthLevel = 2
        ..research.addAll(['life_support', 'urban_planning'])
        ..achievements.add('first_landing')
        ..habitatChoice = 'dome'
        ..marsHabitats = 1;
      expect(state.plans, isEmpty);
      final guide = OnboardingGuide.fromState(state);
      expect(guide.completedCount, 9);
      expect(guide.progress, 1);
      expect(guide.isComplete, isTrue);
    },
  );

  test('building a district is incomplete until construction finishes', () {
    final engine = GameEngine(GameState.initial(epoch)..money = 100000);
    expect(engine.enqueueDistrict('earth_delta', 0, 'housing'), isNull);
    expect(
      step(engine.state, 'first_district').status,
      OnboardingStatus.running,
    );
    expect(step(engine.state, 'first_district').facilityId, 'factory');
    engine.advanceBy(const Duration(minutes: 10));
    expect(step(engine.state, 'first_district').isCompleted, isTrue);
    expect(step(engine.state, 'first_district').facilityId, isNull);
    expect(step(engine.state, 'first_research').isCompleted, isFalse);
  });

  test(
    'batch production and cargo count toward the same starter milestones',
    () {
      final engine = GameEngine(GameState.initial(epoch)..money = 100000);
      engine.state.research.addAll([
        'life_support',
        'automated_fabrication',
        'orbital_logistics',
      ]);
      engine.enqueue('batch_habitat_kit');
      expect(step(engine.state, 'first_kit').status, OnboardingStatus.running);
      expect(step(engine.state, 'first_kit').facilityId, 'factory');
      engine.advanceBy(const Duration(minutes: 10));
      expect(step(engine.state, 'first_kit').isCompleted, isTrue);
      engine.state.achievements.addAll(['first_launch', 'mars_route_open']);
      engine.enqueue('cargo_delivery');
      expect(engine.state.earthKits, 0);
      expect(step(engine.state, 'first_kit').isCompleted, isTrue);
      expect(
        step(engine.state, 'first_landing').status,
        OnboardingStatus.running,
      );
      expect(step(engine.state, 'first_landing').facilityId, 'launch');
      // Finished history is bounded. Cargo already in flight still proves
      // that the player manufactured its input, even when that record is gone.
      engine.state.plans.removeWhere((plan) => plan.isFinished);
      expect(step(engine.state, 'first_kit').isCompleted, isTrue);
      engine.advanceBy(const Duration(minutes: 10));
      engine.chooseHabitat('underground');
      expect(step(engine.state, 'first_landing').isCompleted, isTrue);
    },
  );

  test(
    'legacy expansion and habitat orders retain their actual active status',
    () {
      final engine = GameEngine(GameState.initial(epoch)..money = 100000);
      engine.enqueue('earth_expansion');
      expect(
        step(engine.state, 'first_district').status,
        OnboardingStatus.running,
      );
      engine.advanceBy(const Duration(minutes: 2));
      expect(step(engine.state, 'first_district').isCompleted, isTrue);
      engine.state
        ..achievements.add('first_landing')
        ..habitatChoice = 'dome'
        ..marsKits = 1;
      engine.enqueue('build_habitat');
      expect(
        step(engine.state, 'first_habitat').status,
        OnboardingStatus.running,
      );
      expect(step(engine.state, 'first_habitat').facilityId, 'mars');
      engine.advanceBy(const Duration(minutes: 2));
      expect(step(engine.state, 'first_habitat').isCompleted, isTrue);
    },
  );

  test('a public-command first-hour route achieves every guide milestone', () {
    final engine = GameEngine(GameState.initial(epoch));
    final completed = <String>{};
    var events = 0;

    void inspect() {
      final before = jsonEncode(engine.state.toJson());
      final guide = OnboardingGuide.fromState(engine.state);
      final current = guide.steps
          .where((step) => step.isCompleted)
          .map((step) => step.id)
          .toSet();
      expect(current, containsAll(completed));
      completed.addAll(current);
      expect(engine.state.money, greaterThanOrEqualTo(0));
      expect(jsonEncode(engine.state.toJson()), before);
    }

    void until(bool Function() condition) {
      while (!condition()) {
        final running = engine.state.plans.where(
          (plan) =>
              plan.status == 'running' &&
              engine.state.facilities[plan.definition.facilityId] == true,
        );
        expect(
          running,
          isNotEmpty,
          reason: 'The tutorial must offer a way forward',
        );
        engine.advanceBy(
          Duration(
            milliseconds: running.map((plan) => plan.remainingMs).reduce(min),
          ),
        );
        expect(++events, lessThan(1000));
        expect(engine.state.simulatedMs, lessThanOrEqualTo(3600000));
        inspect();
      }
    }

    PlannedTask prioritize(String? error) {
      expect(error, isNull);
      final plan = engine.state.plans.last;
      final ahead = engine.state
          .upcomingPlansFor(plan.definition.facilityId)
          .where((other) => other.id != plan.id)
          .firstOrNull;
      if (ahead != null) {
        expect(
          engine.reorderPlan(plan.id, relativeToPlanId: ahead.id, before: true),
          isNull,
        );
      }
      inspect();
      return plan;
    }

    // No injected money or milestones: earn in both facilities, compare a
    // coastal plot and move development ahead of future contract iterations.
    expect(engine.enqueue('factory_contract', repeats: null), isNull);
    expect(engine.enqueue('launch_contract', repeats: null), isNull);
    expect(engine.enqueue('life_support'), isNull);
    final house = prioritize(
      engine.enqueueDistrict('earth_delta', 0, 'housing'),
    );
    until(() => engine.state.research.contains('life_support'));
    until(
      () =>
          engine.state.researchPoints >=
          GameContent.researchPointCost('orbital_gardens'),
    );
    expect(engine.enqueue('orbital_gardens'), isNull);
    until(() => house.isFinished);
    final kit = prioritize(engine.enqueue('habitat_kit'));
    until(() => kit.isFinished);
    final moonDelivery = prioritize(engine.enqueue('moon_delivery'));
    until(() => moonDelivery.isFinished);
    final outpost = prioritize(
      engine.enqueueDistrict('moon_south_pole', 2, 'moon_outpost'),
    );
    final secondKit = prioritize(engine.enqueue('habitat_kit'));
    until(() => secondKit.isFinished);
    final secondMoonDelivery = prioritize(engine.enqueue('moon_delivery'));
    until(() => outpost.isFinished && secondMoonDelivery.isFinished);
    final moonPort = prioritize(
      engine.enqueueDistrict('moon_south_pole', 3, 'moon_spaceport'),
    );
    until(() => moonPort.isFinished);
    final probe = prioritize(engine.enqueue('mars_probe'));
    final marsKit = prioritize(engine.enqueue('habitat_kit'));
    until(() => probe.isFinished && marsKit.isFinished);
    final delivery = prioritize(engine.enqueue('mars_delivery'));
    until(() => delivery.isFinished);
    expect(engine.chooseHabitat('dome'), isNull);
    inspect();
    final habitat = prioritize(
      engine.enqueueDistrict('mars_arcadia', 2, 'mars_habitat'),
    );
    until(
      () =>
          habitat.isFinished &&
          engine.state.research.contains('orbital_gardens'),
    );
    expect(OnboardingGuide.fromState(engine.state).isComplete, isTrue);
    expect(engine.state.marsResidents, 24);
    expect(engine.state.contractRevenue, greaterThan(0));
    expect(engine.state.simulatedMs, lessThan(3600000));
    final reloaded = GameState.fromJson(
      jsonDecode(jsonEncode(engine.state.toJson())) as Map<String, dynamic>,
    );
    expect(OnboardingGuide.fromState(reloaded).completedCount, 9);
    expect(reloaded.moneyUnits, engine.state.moneyUnits);
    expect(reloaded.claimedRewards, engine.state.claimedRewards);
  });
}
