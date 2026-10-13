import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

/// Reproducible balance check using public player commands and event time only.
/// Run with `dart tools/verify_progression.dart`; failure returns nonzero even
/// when Dart assertions are disabled. This is one route, not an optimum.
void main() {
  try {
    stdout.writeln(
      jsonEncode({
        ...runProgressionVerification().toJson(),
        'onboarding': runOnboardingVerification().toJson(),
        'onboardingBaseline': runOnboardingVerification(parallelCargo: false)
            .toJson(),
      }),
    );
  } catch (error) {
    stderr.writeln(jsonEncode({'status': 'failed', 'error': '$error'}));
    exitCode = 1;
  }
}

class ProgressionVerification {
  const ProgressionVerification(this.state, this.milestones);
  final GameState state;
  final List<Map<String, Object>> milestones;

  Map<String, Object> toJson() => {
    'status': 'passed',
    'contentVersion': GameContent.version,
    'startingMoney': GameContent.initialMoney,
    'measurement': 'Simulated calendar time; active play time is not measured.',
    'scope': 'Available prototype research, not the global-environment ending.',
    'elapsedHours': state.simulatedMs / Duration.millisecondsPerHour,
    'elapsedDays': state.simulatedMs / Duration.millisecondsPerDay,
    'finalMoney': state.money,
    'researchCount': state.research.length,
    'developedMarsCities': state.developedMarsCityIds.toList(),
    'marsHabitats': state.marsHabitats,
    'marsResidents': state.marsResidents,
    'marsKits': state.marsKits,
    'milestones': milestones,
  };
}

ProgressionVerification runProgressionVerification() {
  final game = GameEngine(GameState.initial(DateTime.utc(2026, 10, 13)));
  final milestones = <Map<String, Object>>[];
  void require(bool condition, String reason) {
    if (!condition) throw StateError(reason);
  }

  void command(String? reason) {
    if (reason != null) throw StateError(reason);
  }

  void advanceUntil(bool Function() condition) {
    var events = 0;
    while (!condition()) {
      final running = game.state.plans.where(
        (plan) =>
            plan.status == 'running' &&
            game.state.facilities[plan.definition.facilityId] == true,
      );
      require(
        running.isNotEmpty,
        'Route is blocked: ${game.state.plans.where((p) => !p.isFinished).map((p) => '${p.taskId}: ${p.stopReason}').join(' / ')}',
      );
      game.advanceBy(
        Duration(milliseconds: running.map((p) => p.remainingMs).reduce(min)),
      );
      require(++events < 200000, 'Too many completion events');
      require(
        game.state.simulatedMs < const Duration(days: 30).inMilliseconds,
        'This prototype route exceeded 30 days',
      );
    }
  }

  void record(String step) {
    milestones.add({
      'step': step,
      'elapsedHours': game.state.simulatedMs / Duration.millisecondsPerHour,
      'money': game.state.money,
      'researchEfficiency': game.state.researchBonusPercent,
      'factoryEfficiency': game.state.factoryBonusPercent,
      'launchEfficiency': game.state.launchBonusPercent,
      'marsEfficiency': game.state.marsBonusPercent,
    });
  }

  void research(String id) {
    command(game.enqueue(id));
    advanceUntil(() => game.state.research.contains(id));
    record(id);
  }

  void prioritize(PlannedTask plan) {
    final candidates = game.state
        .upcomingPlansFor(plan.definition.facilityId)
        .where((p) => p.id != plan.id)
        .toList();
    if (candidates.isNotEmpty) {
      command(
        game.reorderPlan(
          plan.id,
          relativeToPlanId: candidates.first.id,
          before: true,
        ),
      );
    }
  }

  void job(String id) {
    command(game.enqueue(id));
    final plan = game.state.plans.last;
    prioritize(plan);
    advanceUntil(() => plan.isFinished);
    record(id);
  }

  void district(String cityId, int plotIndex, String districtId) {
    command(game.enqueueDistrict(cityId, plotIndex, districtId));
    final plan = game.state.plans.last;
    prioritize(plan);
    advanceUntil(() => plan.isFinished);
    record('$cityId:$plotIndex:$districtId');
  }

  void replaceContract(String oldId, String nextId) {
    final old = game.state.plans.firstWhere(
      (plan) => plan.taskId == oldId && !plan.isFinished,
    );
    command(game.cancelQueued(old.id));
    command(game.enqueue(nextId, repeats: null));
  }

  command(game.enqueue('factory_contract', repeats: null));
  command(game.enqueue('launch_contract', repeats: null));
  research('life_support');
  research('urban_planning');
  district('earth_highland', 0, 'campus');
  district('earth_highland', 1, 'solar');
  district('earth_highland', 3, 'industry');
  job('habitat_kit');
  job('mars_delivery');
  command(game.chooseHabitat('dome'));
  district('mars_arcadia', 2, 'mars_habitat');
  research('automated_fabrication');
  replaceContract('factory_contract', 'precision_contract');
  research('reusable_launch');
  district('earth_delta', 0, 'spaceport');
  research('orbital_logistics');
  replaceContract('launch_contract', 'orbital_contract');
  job('batch_habitat_kit');
  job('cargo_delivery');
  district('mars_elysium', 3, 'mars_habitat');
  research('closed_ecology');
  district('mars_arcadia', 0, 'greenhouse');
  research('local_resources');
  district('mars_arcadia', 1, 'extractor');
  research('intercity_logistics');
  research('industrial_network');
  research('regional_habitats');

  require(
    GameContent.tasks.values
        .where((task) => task.unique)
        .every((task) => game.state.research.contains(task.id)),
    'Not all available research was reachable',
  );
  require(
    game.state.developedMarsCityIds.length == 2,
    'Expected two Mars cities',
  );
  require(game.state.marsHabitats == 2, 'Expected two completed habitats');
  require(game.state.marsKits == 3, 'Cargo was duplicated or lost');
  final snapshot = jsonEncode(game.state.toJson());
  final restored = GameEngine(
    GameState.fromJson(jsonDecode(snapshot) as Map<String, dynamic>),
  );
  require(
    jsonEncode(restored.state.toJson()) == snapshot,
    'Reload changed state',
  );
  return ProgressionVerification(game.state, milestones);
}

/// A public-command route through the first real-time hour. It reports when
/// choices and completions become possible, not how long a person thinks.
class OnboardingVerification {
  const OnboardingVerification(this.state, this.events);
  final GameState state;
  final List<Map<String, Object>> events;

  List<Map<String, Object>> get decisions =>
      events.where((event) => event['kind'] == 'decision').toList();

  double get maxDecisionGapMinutes =>
      _maxGapUntil(state.simulatedMs / Duration.millisecondsPerMinute);

  double get maxDecisionGapBeforeSettlementMinutes => _maxGapUntil(
    events.singleWhere(
          (event) => event['step'] == 'First Mars settlement',
        )['elapsedMinutes']!
        as double,
  );

  double _maxGapUntil(double endMinutes) {
    final times = <double>[
      0,
      ...decisions
          .map((event) => event['elapsedMinutes']! as double)
          .where((time) => time <= endMinutes),
      endMinutes,
    ]..sort();
    var longest = 0.0;
    for (var i = 1; i < times.length; i++) {
      longest = max(longest, times[i] - times[i - 1]);
    }
    return longest;
  }

  Map<String, Object> toJson() => {
    'status': 'passed',
    'measurement':
        'Scripted decision opportunities in 60 simulated minutes; '
        'not measured active play time or an optimal route.',
    'startingMoney': GameContent.initialMoney,
    'elapsedMinutes': state.simulatedMs / Duration.millisecondsPerMinute,
    'finalMoney': state.money,
    'decisionCount': decisions.length,
    'distinctDecisionTimes': decisions
        .map((event) => event['elapsedMinutes'])
        .toSet()
        .length,
    'maxDecisionGapMinutes': maxDecisionGapMinutes,
    'maxDecisionGapBeforeSettlementMinutes':
        maxDecisionGapBeforeSettlementMinutes,
    'completedDistricts': state.districts.length,
    'research': state.research.toList(),
    'marsHabitats': state.marsHabitats,
    'marsResidents': state.marsResidents,
    'events': events,
  };
}

OnboardingVerification runOnboardingVerification({bool parallelCargo = true}) {
  final game = GameEngine(GameState.initial(DateTime.utc(2026, 10, 13)));
  final events = <Map<String, Object>>[];
  const limit = Duration(hours: 1);

  void record(String kind, String step) {
    events.add({
      'kind': kind,
      'step': step,
      'elapsedMinutes': game.state.simulatedMs / Duration.millisecondsPerMinute,
      'money': game.state.money,
      'completedDistricts': game.state.districts.length,
      'researchCount': game.state.research.length,
    });
  }

  void command(String? reason, String step) {
    if (reason != null) throw StateError('$step: $reason');
    record('decision', step);
  }

  void waitUntil(bool Function() condition, String step) {
    var eventCount = 0;
    while (!condition()) {
      final running = game.state.plans.where(
        (plan) =>
            plan.status == 'running' &&
            game.state.facilities[plan.definition.facilityId] == true,
      );
      if (running.isEmpty || ++eventCount > 1000) {
        throw StateError('Onboarding blocked before $step');
      }
      final delta = running.map((plan) => plan.remainingMs).reduce(min);
      if (game.state.simulatedMs + delta > limit.inMilliseconds) {
        throw StateError('Onboarding exceeded 60 minutes before $step');
      }
      game.advanceBy(Duration(milliseconds: delta));
    }
    record('completion', step);
  }

  void prioritize(PlannedTask plan) {
    final candidates = game.state
        .upcomingPlansFor(plan.definition.facilityId)
        .where((other) => other.id != plan.id)
        .toList();
    if (candidates.isNotEmpty) {
      command(
        game.reorderPlan(
          plan.id,
          relativeToPlanId: candidates.first.id,
          before: true,
        ),
        'Prioritize ${plan.taskId} over future contract iterations',
      );
    }
  }

  PlannedTask district(String city, int plot, String type) {
    command(game.enqueueDistrict(city, plot, type), '$city:$plot:$type');
    final plan = game.state.plans.last;
    prioritize(plan);
    return plan;
  }

  PlannedTask job(String id) {
    command(game.enqueue(id), id);
    final plan = game.state.plans.last;
    prioritize(plan);
    return plan;
  }

  command(game.enqueue('factory_contract', repeats: null), 'Earn with factory');
  command(
    game.enqueue('launch_contract', repeats: null),
    'Earn with launch pad',
  );
  command(game.enqueue('life_support'), 'Research life support');
  final firstHouse = district('earth_delta', 0, 'housing');
  waitUntil(() => game.state.research.contains('life_support'), 'Life support');
  waitUntil(
    () => game.state.money >= GameContent.tasks['urban_planning']!.cost + 200,
    'Fund urban research with a maintenance reserve',
  );
  command(game.enqueue('urban_planning'), 'Research urban planning');
  waitUntil(() => firstHouse.isFinished, 'First coastal housing');
  final secondHouse = district('earth_delta', 5, 'housing');
  waitUntil(
    () => game.state.research.contains('urban_planning'),
    'Urban planning',
  );
  final campus = district('earth_delta', 1, 'campus');
  final kit = parallelCargo ? job('habitat_kit') : null;
  waitUntil(() => secondHouse.isFinished, 'Second coastal housing');
  if (!parallelCargo) {
    waitUntil(() => campus.isFinished, 'Campus adjoining both houses');
  }
  final actualKit = kit ?? job('habitat_kit');
  waitUntil(() => actualKit.isFinished, 'Manufactured a habitat kit');
  final solar = parallelCargo ? null : district('earth_delta', 2, 'solar');
  final delivery = job('mars_delivery');
  waitUntil(() => delivery.isFinished, 'First Mars delivery');
  command(game.chooseHabitat('dome'), 'Choose dome habitation on plains');
  final habitat = district('mars_arcadia', 2, 'mars_habitat');
  if (parallelCargo) {
    waitUntil(() => campus.isFinished, 'Campus adjoining both houses');
  }
  final actualSolar = solar ?? district('earth_delta', 2, 'solar');
  if (parallelCargo) {
    waitUntil(() => habitat.isFinished, 'First Mars settlement');
    command(
      game.enqueue('reusable_launch'),
      'Reserve the next transport branch',
    );
  }
  waitUntil(() => actualSolar.isFinished, 'Power supports the campus');
  final industry = district('earth_delta', 8, 'industry');
  if (parallelCargo) {
    waitUntil(() => industry.isFinished, 'Mineral industry demonstration');
  } else {
    waitUntil(() => habitat.isFinished, 'First Mars settlement');
  }
  command(
    game.enqueue('automated_fabrication'),
    'Reserve automation behind its industry demonstration',
  );
  game.advanceBy(
    Duration(milliseconds: limit.inMilliseconds - game.state.simulatedMs),
  );
  record('checkpoint', '60-minute handoff to reserved offline work');

  if (game.state.districts.length < 5 ||
      industry.status == 'cancelled' ||
      game.state.marsHabitats != 1 ||
      game.state.marsResidents != 24 ||
      game.state.claimedRewards.length != 2 ||
      !game.state.research.containsAll(['life_support', 'urban_planning'])) {
    throw StateError(
      'Onboarding invariant: districts=${game.state.districts.length}, industry=${industry.status}, habitats=${game.state.marsHabitats}, residents=${game.state.marsResidents}, rewards=${game.state.claimedRewards}, research=${game.state.research}; events=${jsonEncode(events)}',
    );
  }
  final snapshot = game.state.toJson();
  final loaded = GameEngine(
    GameState.fromJson(
      jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>,
    ),
  );
  if (jsonEncode(loaded.state.toJson()) != jsonEncode(snapshot)) {
    throw StateError('Onboarding reload changed progress or rewards');
  }
  return OnboardingVerification(game.state, events);
}
