import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 20);
  const pointScale = GameState.researchPointScale;

  String idFor(String catalogId) => GameContent.researchTechnologies.values
      .singleWhere((technology) => technology.catalogId == catalogId)
      .id;

  GameEngine fresh() => GameEngine(
    GameState.initial(epoch)
      ..firstRunTutorial = FirstRunTutorialStep.completed
      ..openingSeen = true
      ..money = 1000000,
  );

  GameState copy(GameState state) => GameState.fromJson(
    jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
  );

  void givePoints(GameState state, int points) {
    state.researchPointUnits = points * pointScale;
  }

  String cityFor(String technologyId) => GameContent.cities.values
      .firstWhere(
        (city) => city.planet == GameContent.developmentPlanet(technologyId),
      )
      .id;

  PlannedTask buildDevelopment(GameEngine engine, String technologyId) {
    expect(
      engine.enqueueDevelopment(technologyId, cityId: cityFor(technologyId)),
      isNull,
    );
    final plan = engine.state.plans.last;
    expect(plan.taskId, GameContent.developmentTaskId(technologyId));
    expect(plan.status, 'running');
    engine.advanceBy(Duration(milliseconds: plan.remainingMs));
    expect(plan.status, 'completed');
    return plan;
  }

  test(
    'new world reveals one entrance per field and funds the protected tutorial',
    () {
      final state = GameState.initial(epoch);
      expect(state.discoveredResearchIds, {
        idFor('B01'),
        idFor('M22'),
        idFor('R01'),
        idFor('E01'),
      });
      expect(state.discoveredResearchIds, isNot(contains(idFor('M26'))));
      expect(state.discoveredResearchIds, isNot(contains(idFor('B02'))));
      expect(
        state.researchPointUnits,
        greaterThanOrEqualTo(
          GameContent.researchPointCost('life_support') * pointScale,
        ),
      );
      expect(state.introductionPausesClock, isTrue);
      state.firstRunTutorial = FirstRunTutorialStep.startResearch;
      final engine = GameEngine(state);
      expect(engine.unlockResearch('life_support'), isNull);
      expect(state.research, contains('life_support'));
    },
  );

  test('common points unlock immediately without charging money or granting equipment', () {
    final engine = fresh();
    final id = idFor('B01');
    final cost = GameContent.researchPointCost(id);
    engine.state.researchPointUnits = cost * pointScale + 1;
    final money = engine.state.moneyUnits;
    final clock = engine.state.simulatedMs;
    expect(engine.unlockResearch(id), isNull);
    expect(engine.state.research, contains(id));
    expect(engine.state.researchPointUnits, 1);
    expect(engine.state.moneyUnits, money);
    expect(engine.state.simulatedMs, clock);
    expect(engine.state.developments, isEmpty);
    expect(engine.state.plans.where((plan) => !plan.isFinished), isEmpty);
  });

  test(
    'a fraction below the required points cannot unlock or consume progress',
    () {
      final engine = fresh();
      final id = idFor('B01');
      final available = GameContent.researchPointCost(id) * pointScale - 1;
      engine.state.researchPointUnits = available;
      final money = engine.state.moneyUnits;
      expect(engine.unlockResearch(id), isNotNull);
      expect(engine.state.researchPointUnits, available);
      expect(engine.state.moneyUnits, money);
      expect(engine.state.research, isNot(contains(id)));
    },
  );

  test('different fields spend from one bank and completed research cannot charge twice', () {
    final engine = fresh();
    final bio = idFor('B01');
    final energy = idFor('E01');
    final total =
        GameContent.researchPointCost(bio) +
        GameContent.researchPointCost(energy);
    engine.state.researchPointUnits = total * pointScale + 37;
    expect(engine.unlockResearch(bio), isNull);
    expect(engine.unlockResearch(energy), isNull);
    expect(engine.state.researchPointUnits, 37);
    final notices = engine.state.completionNotices.length;
    expect(engine.unlockResearch(bio), isNotNull);
    expect(engine.state.researchPointUnits, 37);
    expect(engine.state.completionNotices.length, notices);
    expect(engine.state.research, {bio, energy});
  });

  test('future research stays unavailable and discovered children retain urban conditions', () {
    final engine = fresh();
    givePoints(engine.state, 1000000);
    final parent = idFor('B01');
    final child = idFor('B02');
    final hidden = idFor('M26');
    final before = engine.state.researchPointUnits;
    expect(engine.unlockResearch(child), isNotNull);
    expect(engine.unlockResearch(hidden), isNotNull);
    expect(engine.state.researchPointUnits, before);
    expect(engine.unlockResearch(parent), isNull);
    expect(engine.state.discoveredResearchIds, contains(child));
    expect(engine.state.discoveredResearchIds, isNot(contains(hidden)));
    expect(engine.unlockResearch(child), isNotNull);
    expect(engine.state.research, isNot(contains(child)));
  });

  test(
    'idle work only accumulates RP and never chooses research or branches',
    () {
      final engine = fresh();
      engine.state.researchPointUnits = 0;
      expect(engine.state.researchPointsPerMinute, greaterThan(0));
      engine.advanceBy(const Duration(minutes: 8));
      expect(engine.state.researchPointUnits, greaterThan(0));
      expect(engine.state.research, isEmpty);
      expect(engine.state.developments, isEmpty);
    },
  );

  test(
    'paused lab stops RP while deprecated staffing never changes its output',
    () {
      final engine = fresh();
      engine.state.researchPointUnits = 53;
      expect(engine.setFacilityEnabled('lab', false), isNull);
      expect(engine.state.researchPointsPerMinute, 0);
      engine.advanceBy(const Duration(minutes: 5));
      expect(engine.state.researchPointUnits, 53);
      expect(engine.setFacilityEnabled('lab', true), isNull);
      final rate = engine.state.researchPointsPerMinute;
      expect(engine.assignResearchers(0), isNotNull);
      engine.state.researchers = 0;
      expect(engine.state.researchPointsPerMinute, rate);
      engine.advanceBy(const Duration(minutes: 5));
      expect(engine.state.researchPointUnits, greaterThan(53));
    },
  );

  test('RP accrual and contracts match partitions without automatically starting research', () {
    final one = fresh();
    one.state.researchPointUnits = 0;
    expect(one.enqueue('life_support'), contains('不足'));
    expect(one.state.plans, isEmpty);
    expect(one.enqueue('factory_contract', repeats: 3), isNull);
    expect(one.enqueue('launch_contract', repeats: 2), isNull);
    final split = GameEngine(copy(one.state));
    const duration = Duration(days: 1);
    one.advanceTo(epoch.add(duration));
    var elapsed = 0;
    for (final step in [1, 17, 999, 57003, 411119, 600001, 719999]) {
      elapsed += step;
      split.advanceTo(epoch.add(Duration(milliseconds: elapsed)));
    }
    split.advanceTo(epoch.add(duration));
    expect(split.state.toJson(), one.state.toJson());
    expect(one.state.research, isNot(contains('life_support')));
    expect(one.unlockResearch('life_support'), isNull);
    expect(
      one.state.plans
          .where((plan) => plan.taskId == 'life_support')
          .single
          .completedRuns,
      1,
    );
  });

  test('budget suspension keeps RP integration invariant across save and split updates', () {
    final state = GameState.initial(epoch)
      ..firstRunTutorial = FirstRunTutorialStep.completed
      ..openingSeen = true
      ..researchPointUnits = 0
      ..money = 1;
    final one = GameEngine(state);
    final split = GameEngine(copy(one.state));
    one.advanceTo(epoch.add(const Duration(hours: 3)));
    for (var second = 1; second <= 10800; second += 37) {
      split.advanceTo(epoch.add(Duration(seconds: second)));
    }
    split.advanceTo(epoch.add(const Duration(hours: 3)));
    expect(split.state.toJson(), one.state.toJson());
    expect(one.state.moneyUnits, greaterThanOrEqualTo(0));
    expect(one.state.researchPointUnits, greaterThanOrEqualTo(0));
  });

  test('save and repeated same-clock reload never grant RP, research or equipment twice', () {
    final engine = fresh();
    givePoints(engine.state, GameContent.researchPointCost('life_support'));
    expect(engine.unlockResearch('life_support'), isNull);
    engine.advanceTo(epoch.add(const Duration(milliseconds: 81013)));
    final snapshot = engine.state.toJson();
    final restored = GameEngine(copy(engine.state));
    restored.advanceTo(epoch.add(const Duration(milliseconds: 81013)));
    restored.advanceTo(epoch.add(const Duration(milliseconds: 81013)));
    expect(restored.state.toJson(), snapshot);
    expect(restored.unlockResearch('life_support'), isNotNull);
    expect(restored.state.research, {'life_support'});
    expect(restored.state.developments, isEmpty);
  });

  test(
    'clock rollback keeps earned RP and rebases only subsequent elapsed time',
    () {
      final engine = fresh();
      engine.state.researchPointUnits = 0;
      engine.advanceTo(epoch.add(const Duration(seconds: 83)));
      final units = engine.state.researchPointUnits;
      final clock = engine.state.simulatedMs;
      engine.advanceTo(epoch.subtract(const Duration(days: 2)));
      expect(engine.state.researchPointUnits, units);
      expect(engine.state.simulatedMs, clock);
      engine.advanceTo(
        epoch
            .subtract(const Duration(days: 2))
            .add(const Duration(seconds: 83)),
      );
      expect(engine.state.simulatedMs, clock * 2);
      expect(engine.state.researchPointUnits, units * 2);
      expect(engine.state.research, isEmpty);
    },
  );

  test('development must be paid and completed before it can be operated', () {
    final engine = fresh();
    final id = idFor('B01');
    expect(engine.enqueueDevelopment(id, cityId: cityFor(id)), isNotNull);
    givePoints(engine.state, GameContent.researchPointCost(id));
    expect(engine.unlockResearch(id), isNull);
    expect(engine.state.developments, isEmpty);
    expect(engine.setDevelopmentEnabled(id, true), isNotNull);
    final money = engine.state.moneyUnits;
    expect(engine.enqueueDevelopment(id, cityId: cityFor(id)), isNull);
    final plan = engine.state.plans.last;
    expect(plan.status, 'running');
    expect(engine.state.moneyUnits, lessThan(money));
    expect(engine.state.developments, isEmpty);
    expect(engine.enqueueDevelopment(id, cityId: cityFor(id)), isNotNull);
    engine.advanceBy(Duration(milliseconds: plan.remainingMs));
    expect(engine.state.developments, {id});
    expect(engine.state.developmentEnabled[id], isFalse);
    expect(engine.state.developmentUpkeepPerMinute, 0);
    expect(engine.enqueueDevelopment(id, cityId: cityFor(id)), isNotNull);
  });

  test('operational research facilities produce RP without allocation and survive reload', () {
    final engine = fresh();
    final id = idFor('R01');
    givePoints(engine.state, GameContent.researchPointCost(id));
    expect(engine.unlockResearch(id), isNull);
    buildDevelopment(engine, id);
    final baseline = engine.state.researchPointsPerMinute;
    expect(engine.setDevelopmentEnabled(id, true), isNull);
    expect(engine.state.researchPointsPerMinute, greaterThan(baseline));
    final runningRate = engine.state.researchPointsPerMinute;
    expect(engine.assignDevelopmentResearchers(id, 1), isNotNull);
    engine.state.developmentResearchers[id] = 4;
    engine.state.researchers = 0;
    expect(engine.state.researchPointsPerMinute, runningRate);
    expect(engine.state.isDevelopmentOperational(id), isTrue);
    expect(engine.state.developmentUpkeepPerMinute, greaterThan(0));
    expect(engine.assignResearchers(0), isNotNull);
    expect(
      engine.assignDevelopmentResearchers(
        id,
        GameContent.developmentResearchCapacity(id) + 1,
      ),
      isNotNull,
    );
    expect(engine.state.developmentResearchers[id], 4);
    expect(copy(engine.state).toJson(), engine.state.toJson());
    expect(engine.setDevelopmentEnabled(id, false), isNull);
    expect(engine.state.isDevelopmentOperational(id), isFalse);
    expect(engine.state.developmentUpkeepPerMinute, 0);
  });

  test('operating equipment needs no staff reserved by paid factory work', () {
    final engine = fresh();
    final id = idFor('M25');
    engine.state.research.add(id);
    buildDevelopment(engine, id);
    expect(GameContent.developmentCrewRequirement(id), greaterThan(0));
    expect(engine.enqueue('factory_contract'), isNull);
    final contract = engine.state.plans.last;
    expect(contract.status, 'running');
    expect(contract.iterationSpecialists, 0);
    expect(engine.setDevelopmentEnabled(id, true), isNull);
    expect(engine.state.developmentEnabled[id], isTrue);
    engine.advanceBy(Duration(milliseconds: contract.remainingMs));
    expect(engine.setDevelopmentEnabled(id, true), isNull);
    expect(engine.state.developmentWorkers, greaterThan(0));
    expect(engine.state.isDevelopmentOperational(id), isTrue);
  });

  test(
    'pausing a shared facility resumes without hidden staffing constraints',
    () {
      final engine = fresh();
      final id = idFor('B01');
      givePoints(engine.state, GameContent.researchPointCost(id));
      expect(engine.unlockResearch(id), isNull);
      buildDevelopment(engine, id);
      expect(engine.setDevelopmentEnabled(id, true), isNull);
      engine.state.developmentResearchers[id] = 4;
      final facilityId = GameContent.developmentFacilityId(id);
      expect(engine.setFacilityEnabled(facilityId, false), isNull);
      engine.state.researchers = 0;
      engine.setFacilityEnabled(facilityId, true);
      expect(engine.setDevelopmentEnabled(id, true), isNull);
      expect(engine.state.isDevelopmentOperational(id), isTrue);
      expect(() => copy(engine.state), returnsNormally);
    },
  );

  test(
    'development placement rejects a city on the wrong planet without payment',
    () {
      final engine = fresh();
      final id = idFor('B01');
      givePoints(engine.state, GameContent.researchPointCost(id));
      expect(engine.unlockResearch(id), isNull);
      final wrongCity = GameContent.cities.values.firstWhere(
        (city) => city.planet != GameContent.developmentPlanet(id),
      );
      final money = engine.state.moneyUnits;
      expect(engine.enqueueDevelopment(id, cityId: wrongCity.id), isNotNull);
      expect(engine.state.moneyUnits, money);
      expect(engine.state.developments, isEmpty);
      expect(engine.state.plans.where((plan) => !plan.isFinished), isEmpty);
    },
  );

  test(
    'invalid new persistent counters and unknown equipment reject the save',
    () {
      final state = fresh().state;
      expect(
        () => GameState.fromJson({...state.toJson(), 'researchPointUnits': -1}),
        throwsFormatException,
      );
      expect(
        () => GameState.fromJson({
          ...state.toJson(),
          'developments': ['future-equipment'],
        }),
        throwsFormatException,
      );
    },
  );
}
