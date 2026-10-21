import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 13);
  GameEngine fresh({int money = 900}) =>
      GameEngine(GameState.initial(epoch)..money = money);
  GameState roundTrip(GameState state) => GameState.fromJson(
    jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
  );

  test('only explicitly queued work progresses', () {
    final engine = fresh();
    engine.advanceTo(epoch.add(const Duration(minutes: 10)));
    expect(engine.state.research, isEmpty);
    expect(engine.state.earthKits, 0);
    expect(engine.state.marsHabitats, 0);
    expect(engine.state.money, 780);
  });

  test('one catch-up equals irregular partitions across rewards, queues and branch', () {
    final one = fresh(money: 10000);
    one.state.achievements.addAll(['first_launch', 'mars_route_open']);
    for (final task in ['factory_contract', 'launch_contract']) {
      expect(one.enqueue(task, repeats: 3), isNull);
    }
    for (final task in [
      'life_support',
      'habitat_kit',
      'mars_delivery',
      'build_habitat',
    ]) {
      expect(
        one.enqueue(task, repeats: task == 'life_support' ? 1 : 2),
        isNull,
      );
    }
    final split = GameEngine(roundTrip(one.state));
    one.advanceTo(epoch.add(const Duration(minutes: 15)));
    var elapsed = 0;
    for (final amount in [1, 999, 47001, 135009, 60000, 216987, 440003]) {
      elapsed += amount;
      split.advanceTo(epoch.add(Duration(milliseconds: elapsed)));
    }
    expect(elapsed, 900000);
    expect(split.state.toJson(), one.state.toJson());
    expect(one.state.marsKits, 2);
    expect(one.state.marsHabitats, 0);
    expect(one.state.plans.last.stopReason, contains('分岐待ち'));
    expect(one.chooseHabitat('dome'), isNull);
    expect(split.chooseHabitat('dome'), isNull);
    one.advanceTo(epoch.add(const Duration(minutes: 20)));
    for (var i = 1; i <= 30; i++) {
      split.advanceTo(epoch.add(Duration(seconds: 900 + i * 10)));
    }
    expect(split.state.toJson(), one.state.toJson());
    expect(one.state.marsHabitats, 2);
    expect(one.state.marsResidents, 24);
    expect(
      one.state.claimedRewards.where((id) => id.endsWith('dome_habitat')),
      hasLength(1),
    );
  });

  test(
    'shared factory order makes outside contracts delay own manufacture',
    () {
      final engine = fresh(money: 5000);
      engine.state.research.add('life_support');
      engine.enqueue('factory_contract', repeats: 3);
      engine.enqueue('habitat_kit');
      expect(engine.state.plans.last.stopReason, '共用設備の順番待ち');
      engine.advanceTo(epoch.add(const Duration(seconds: 270)));
      expect(engine.state.plans.first.completedRuns, 3);
      expect(engine.state.plans.first.status, 'completed');
      expect(engine.state.plans.last.status, 'running');
      expect(engine.state.earthKits, 0);
      engine.advanceTo(epoch.add(const Duration(seconds: 450)));
      expect(engine.state.earthKits, 1);
      expect(engine.state.contractRevenue, 660);
    },
  );

  test('three repeats finish exactly three times', () {
    final engine = fresh(money: 1000);
    engine.enqueue('factory_contract', repeats: 3);
    engine.advanceTo(epoch.add(const Duration(seconds: 270)));
    expect(engine.state.plans.single.completedRuns, 3);
    expect(engine.state.plans.single.remainingRepeats, 0);
    expect(engine.state.money, 1486);
    engine.advanceTo(epoch.add(const Duration(seconds: 360)));
    expect(engine.state.plans.single.completedRuns, 3);
    expect(engine.state.contractRevenue, 660);
  });

  test(
    'unlimited stops at an unselected branch without stopping other work',
    () {
      final engine = fresh(money: 5000);
      engine.state.marsKits = 2;
      engine.state.achievements.add('first_landing');
      engine.enqueue('build_habitat', repeats: null);
      engine.enqueue('factory_contract', repeats: 3);
      engine.advanceTo(epoch.add(const Duration(minutes: 5)));
      expect(engine.state.plans.first.stopReason, contains('分岐待ち'));
      expect(engine.state.plans.first.completedRuns, 0);
      expect(engine.state.plans.last.completedRuns, 3);
      engine.chooseHabitat('underground');
      engine.advanceTo(epoch.add(const Duration(minutes: 10)));
      expect(engine.state.plans.first.completedRuns, 2);
      expect(engine.state.plans.first.remainingRepeats, isNull);
      expect(engine.state.plans.first.stopReason, contains('資源不足'));
      expect(engine.state.marsResidents, 24);
      expect(engine.state.achievements, contains('underground_habitat'));
      expect(engine.state.achievements, isNot(contains('main_ending')));
    },
  );

  test('unlimited contract can be stopped after current paid run', () {
    final engine = fresh(money: 5000);
    engine.state.research.add('life_support');
    engine.enqueue('factory_contract', repeats: null);
    engine.enqueue('habitat_kit');
    engine.advanceTo(epoch.add(const Duration(seconds: 100)));
    expect(engine.state.plans.first.completedRuns, 1);
    engine.cancelQueued(engine.state.plans.first.id);
    engine.advanceTo(epoch.add(const Duration(seconds: 180)));
    expect(engine.state.plans.first.completedRuns, 2);
    expect(engine.state.plans.first.status, 'completed');
    expect(engine.state.plans.last.status, 'running');
  });

  test('affordability is an event boundary and passive rebuilding starts queued work', () {
    final state = GameState.initial(epoch)..money = 0;
    state.facilities['lab'] = false;
    state.facilities['launch'] = false;
    state.facilities['mars'] = false;
    final one = GameEngine(state);
    one.enqueue('factory_contract');
    expect(one.state.plans.single.stopReason, contains('資金不足'));
    final split = GameEngine(roundTrip(state));
    one.advanceTo(epoch.add(const Duration(seconds: 290)));
    for (var i = 1; i <= 290; i++) {
      split.advanceTo(epoch.add(Duration(seconds: i)));
    }
    expect(one.state.toJson(), split.state.toJson());
    expect(one.state.plans.single.status, 'completed');
    expect(one.state.money, 238);
  });

  test('insolvency suspends upkeep and recovers without debt or game over', () {
    final one = fresh(money: 1);
    final split = GameEngine(roundTrip(one.state));
    one.advanceTo(epoch.add(const Duration(minutes: 8)));
    for (var i = 1; i <= 480; i++) {
      split.advanceTo(epoch.add(Duration(seconds: i)));
    }
    expect(one.state.toJson(), split.state.toJson());
    expect(one.state.facilities['launch'], isFalse);
    expect(one.state.money, greaterThanOrEqualTo(14));
    expect(one.state.netPerMinute, greaterThan(0));
    expect(one.setFacilityEnabled('launch', true), isNull);
    expect(one.state.facilities['launch'], isTrue);
  });

  test(
    'paused transport keeps paid cargo and remaining work without double costs',
    () {
      final engine = fresh(money: 1000);
      engine.state.earthKits = 1;
      engine.state.achievements.addAll(['first_launch', 'mars_route_open']);
      engine.enqueue('mars_delivery');
      engine.advanceTo(epoch.add(const Duration(seconds: 30)));
      expect(engine.state.earthKits, 0);
      engine.setFacilityEnabled('launch', false);
      final remaining = engine.state.plans.single.remainingMs;
      engine.advanceTo(epoch.add(const Duration(seconds: 90)));
      expect(engine.state.plans.single.remainingMs, remaining);
      engine.setFacilityEnabled('launch', true);
      engine.advanceTo(epoch.add(const Duration(seconds: 240)));
      expect(engine.state.marsKits, 1);
      expect(engine.state.earthKits, 0);
      expect(engine.state.plans.single.completedRuns, 1);
    },
  );

  test(
    'save and same-clock reload never duplicate revenue, research or rewards',
    () {
      final engine = fresh(money: 5000);
      engine.state.marsKits = 1;
      engine.state.achievements.add('first_landing');
      engine.chooseHabitat('dome');
      engine.enqueue('build_habitat');
      engine.enqueue('factory_contract');
      engine.enqueue('life_support');
      final end = epoch.add(const Duration(seconds: 120));
      engine.advanceTo(end);
      final saved = engine.state.toJson();
      final restored = GameEngine(roundTrip(engine.state));
      restored.advanceTo(end);
      restored.advanceTo(end);
      expect(restored.state.toJson(), saved);
      expect(restored.state.research, {'life_support'});
      expect(restored.state.marsHabitats, 1);
      expect(restored.state.contractRevenue, 220);
      expect(restored.enqueue('life_support'), isNotNull);
    },
  );

  test('backwards device clock rebases without undoing completed events', () {
    final engine = fresh(money: 1000);
    engine.enqueue('factory_contract');
    engine.advanceTo(epoch.add(const Duration(seconds: 90)));
    final money = engine.state.moneyUnits;
    engine.advanceTo(epoch.subtract(const Duration(days: 1)));
    expect(engine.state.moneyUnits, money);
    expect(engine.state.simulatedMs, 90000);
    engine.advanceTo(
      epoch.subtract(const Duration(days: 1)).add(const Duration(seconds: 90)),
    );
    expect(engine.state.simulatedMs, 180000);
    expect(engine.state.plans.single.completedRuns, 1);
    expect(engine.state.contractRevenue, 220);
  });

  test('development skip does not shift wall-clock baseline', () {
    final engine = fresh();
    engine.advanceBy(const Duration(minutes: 1));
    expect(engine.state.lastWallClockMs, epoch.millisecondsSinceEpoch);
    engine.advanceTo(epoch.add(const Duration(seconds: 1)));
    expect(engine.state.simulatedMs, 61000);
  });

  test('long idle time aggregates, preserving all elapsed time', () {
    final engine = fresh(money: 0);
    engine.advanceTo(epoch.add(const Duration(days: 3650)));
    expect(engine.state.simulatedMs, const Duration(days: 3650).inMilliseconds);
    expect(engine.state.money, 3650 * 24 * 60 * 2);
  });

  test(
    'finite invalid repeats and duplicate research cannot become infinite',
    () {
      final engine = fresh();
      expect(engine.enqueue('factory_contract', repeats: 0), isNotNull);
      expect(engine.enqueue('factory_contract', repeats: -1), isNotNull);
      expect(engine.enqueue('life_support', repeats: null), isNotNull);
      expect(engine.enqueue('life_support'), isNull);
      expect(engine.enqueue('life_support'), isNotNull);
      expect(engine.state.plans, hasLength(1));
    },
  );

  test(
    'completed history is bounded while counters and plan IDs remain durable',
    () {
      final engine = fresh(money: 100000);
      for (var i = 0; i < 75; i++) {
        engine.enqueue('factory_contract');
        engine.advanceBy(const Duration(seconds: 90));
      }
      expect(engine.state.plans, hasLength(48));
      expect(engine.state.nextPlanId, 76);
      expect(engine.state.contractRevenue, 75 * 220);
      expect(engine.state.log, hasLength(40));
      expect(roundTrip(engine.state).nextPlanId, 76);
    },
  );

  test('serialization snapshot does not change after later actions', () {
    final engine = fresh();
    final snapshot = engine.state.toJson();
    final encoded = jsonEncode(snapshot);
    engine.setFacilityEnabled('factory', false);
    engine.enqueue('life_support');
    expect(jsonEncode(snapshot), encoded);
  });

  test('100 varied concurrent schedules are invariant to time partitions', () {
    for (var seed = 0; seed < 100; seed++) {
      final random = Random(seed);
      final state = GameState.initial(epoch)
        ..money = 200 + random.nextInt(4000)
        ..habitatChoice = seed.isEven ? 'dome' : 'underground'
        ..marsKits = random.nextInt(4)
        ..earthKits = random.nextInt(4);
      state.research.add('life_support');
      state.achievements.add('first_landing');
      final one = GameEngine(state);
      one.enqueue('factory_contract', repeats: 1 + random.nextInt(3));
      one.enqueue('habitat_kit', repeats: null);
      one.enqueue('launch_contract', repeats: 1 + random.nextInt(3));
      one.state.achievements.addAll(['first_launch', 'mars_route_open']);
      one.enqueue('mars_delivery', repeats: null);
      one.enqueue('build_habitat', repeats: null);
      final split = GameEngine(roundTrip(state));
      const totalMs = 7200000;
      one.advanceTo(epoch.add(const Duration(milliseconds: totalMs)));
      var elapsed = 0;
      while (elapsed < totalMs) {
        elapsed = min(totalMs, elapsed + 1 + random.nextInt(120000));
        split.advanceTo(epoch.add(Duration(milliseconds: elapsed)));
      }
      expect(split.state.toJson(), one.state.toJson(), reason: 'seed $seed');
    }
  });

  test(
    'one year of unlimited work retains every completion with bounded memory',
    () {
      final engine = fresh(money: 1000);
      engine.enqueue('factory_contract', repeats: null);
      engine.advanceBy(const Duration(days: 365));
      expect(engine.state.plans.single.completedRuns, 350400);
      expect(engine.state.contractRevenue, 350400 * 220);
      expect(engine.state.plans.single.status, 'running');
      expect(engine.state.plans.single.remainingMs, 90000);
      expect(engine.state.log, hasLength(40));
    },
  );

  test('unsupported save versions and broken resources are rejected', () {
    final state = fresh().state;
    expect(
      () => GameState.fromJson({
        ...state.toJson(),
        'schemaVersion': GameState.schemaVersion + 1,
      }),
      throwsFormatException,
    );
    expect(
      () => GameState.fromJson({...state.toJson(), 'contentVersion': 'future'}),
      throwsFormatException,
    );
    expect(
      () => GameState.fromJson({...state.toJson(), 'marsKits': -1}),
      throwsFormatException,
    );
  });
}
