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
        'researchFrontiers': runProgressionVerification(includeFrontiers: true)
            .toJson(),
        'onboarding': runOnboardingVerification().toJson(),
        'onboardingBaseline': runOnboardingVerification(parallelCargo: false)
            .toJson(),
        'earlyInvestments': runEarlyInvestmentVerification(),
        'parallelStrategy': runParallelStrategyComparison(),
      }),
    );
  } catch (error) {
    stderr.writeln(jsonEncode({'status': 'failed', 'error': '$error'}));
    exitCode = 1;
  }
}

class ProgressionVerification {
  const ProgressionVerification(
    this.state,
    this.milestones, {
    this.includesFrontiers = false,
  });
  final GameState state;
  final List<Map<String, Object>> milestones;
  final bool includesFrontiers;

  Map<String, Object> toJson() => {
    'status': 'passed',
    'contentVersion': GameContent.version,
    'startingMoney': GameContent.initialMoney,
    'measurement': 'Simulated calendar time; active play time is not measured.',
    'scope': includesFrontiers
        ? 'All available prototype research, not the global-environment ending.'
        : 'Established 13-research route; optional frontiers are checked separately.',
    'optionalResearchIncluded': includesFrontiers,
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

ProgressionVerification runProgressionVerification({
  bool includeFrontiers = false,
}) {
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
  for (final id in [
    'process_design',
    'cargo_packaging',
    'habitat_operations',
  ]) {
    research(id);
  }
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

  if (includeFrontiers) {
    // A real local laboratory consumes one of the remaining imported kits.
    // Optional research remains an investment after the established route,
    // so its arrival times can still be compared without rewriting history.
    district('mars_arcadia', 4, 'mars_lab');
    for (final id in GameContent.optionalFrontierResearchIds) {
      research(id);
    }
  }

  require(
    GameContent.tasks.values
        .where(
          (task) =>
              task.unique &&
              (includeFrontiers ||
                  !GameContent.optionalFrontierResearchIds.contains(task.id)),
        )
        .every((task) => game.state.research.contains(task.id)),
    'Not all requested research was reachable',
  );
  require(
    game.state.developedMarsCityIds.length == 2,
    'Expected two Mars cities',
  );
  require(game.state.marsHabitats == 2, 'Expected two completed habitats');
  require(
    game.state.marsKits == (includeFrontiers ? 2 : 3),
    'Cargo was duplicated or lost',
  );
  final snapshot = jsonEncode(game.state.toJson());
  final restored = GameEngine(
    GameState.fromJson(jsonDecode(snapshot) as Map<String, dynamic>),
  );
  require(
    jsonEncode(restored.state.toJson()) == snapshot,
    'Reload changed state',
  );
  return ProgressionVerification(
    game.state,
    milestones,
    includesFrontiers: includeFrontiers,
  );
}

enum EarlyInvestmentOrder { industryOnly, industryFirst, housingFirst }

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
    'completedLevels': state.districts.values.fold<int>(
      0,
      (sum, district) => sum + district.level,
    ),
    'coastalHousingLevel': state.districtAt('earth_delta', 0)?.level ?? 0,
    'netPerMinute': state.netPerMinute,
    'research': state.research.toList(),
    'marsHabitats': state.marsHabitats,
    'marsResidents': state.marsResidents,
    'events': events,
  };
}

OnboardingVerification runOnboardingVerification({
  bool parallelCargo = true,
  EarlyInvestmentOrder investmentOrder = EarlyInvestmentOrder.industryOnly,
}) {
  if (!parallelCargo && investmentOrder != EarlyInvestmentOrder.industryOnly) {
    throw ArgumentError(
      'Early investment comparisons use the parallel-cargo route',
    );
  }
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

  void upgradeCoastalHousing() {
    command(
      game.upgradeDistrict('earth_delta', 0),
      'Upgrade the original coastal housing',
    );
    final plan = game.state.plans.last;
    prioritize(plan);
    waitUntil(() => plan.isFinished, 'Original coastal housing upgraded');
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
  if (investmentOrder == EarlyInvestmentOrder.housingFirst) {
    upgradeCoastalHousing();
  }
  final industry = district('earth_delta', 8, 'industry');
  if (parallelCargo) {
    waitUntil(() => industry.isFinished, 'Mineral industry demonstration');
  } else {
    waitUntil(() => habitat.isFinished, 'First Mars settlement');
  }
  if (investmentOrder == EarlyInvestmentOrder.industryFirst) {
    upgradeCoastalHousing();
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

/// All three routes start with the same unmodified initial save and public
/// commands. The district-3 reference is a recorded run, not a re-simulation
/// using current prices. The two upgraded routes buy the same final facilities.
Map<String, Object> runEarlyInvestmentVerification() {
  final routes = {
    for (final order in EarlyInvestmentOrder.values)
      order.name: runOnboardingVerification(investmentOrder: order),
  };
  double completion(OnboardingVerification route, String step) =>
      route.events.singleWhere(
            (event) => event['step'] == step,
          )['elapsedMinutes']!
          as double;
  void require(bool condition, String reason) {
    if (!condition) throw StateError(reason);
  }

  final industryOnly = routes['industryOnly']!;
  final industryFirst = routes['industryFirst']!;
  final housingFirst = routes['housingFirst']!;
  for (final route in routes.values) {
    require(
      route.state.simulatedMs == const Duration(hours: 1).inMilliseconds,
      'Early investments must be measured at the same 60-minute horizon',
    );
    require(
      route.state.districtAt('earth_delta', 8)?.districtId == 'industry',
      'Each first-hour investment route must finish the industrial district',
    );
    require(
      route.state.marsHabitats == 1 && route.state.marsResidents == 24,
      'Investment changes must preserve the first Mars settlement',
    );
    require(
      route.maxDecisionGapMinutes < 21.46,
      'The observed first-hour gap did not improve on district-3',
    );
  }
  for (final route in [industryFirst, housingFirst]) {
    require(
      route.state.districtAt('earth_delta', 0)?.level == 2,
      'The chosen coastal housing upgrade was not completed',
    );
    require(
      !route.state.research.contains('automated_fabrication'),
      'The early housing choice unexpectedly needed advanced automation',
    );
  }
  require(
    completion(industryFirst, 'Mineral industry demonstration') <
        completion(housingFirst, 'Mineral industry demonstration'),
    'Industry-first must demonstrate manufacturing earlier',
  );
  require(
    completion(housingFirst, 'Original coastal housing upgraded') <
        completion(industryFirst, 'Original coastal housing upgraded'),
    'Housing-first must realize its income and adjacency earlier',
  );
  require(
    industryOnly.state.population < industryFirst.state.population &&
        industryFirst.state.population == housingFirst.state.population,
    'The two upgraded routes must buy the same additional housing capacity',
  );
  require(
    industryFirst.state.netPerMinute == housingFirst.state.netPerMinute &&
        industryFirst.state.researchBonusPercent ==
            housingFirst.state.researchBonusPercent &&
        industryFirst.state.factoryBonusPercent ==
            housingFirst.state.factoryBonusPercent,
    'Ordering identical investments must not change their final effects',
  );
  return {
    'status': 'passed',
    'measurement':
        'Public-command routes with no injected money, research, '
        'resources, or districts. Timing is simulated calendar time, '
        'not measured active play time.',
    'district3Reference': {
      'contentVersion': 'district-3',
      'sourceCommit': '9808084',
      'measurement':
          'Recorded parallel-cargo, industry-only route before this change.',
      'industryCost': 1500,
      'industryBaseMinutes': 12,
      'industryCompletedMinutes': 58.76,
      'maxDecisionGapMinutes': 21.46,
      'finalMoney': 3037,
      'completedDistricts': 6,
      'firstMarsSettlementMinutes': 35,
    },
    'currentContentVersion': GameContent.version,
    'currentIndustryCost': GameContent.districts['industry']!.cost,
    'currentIndustryBaseMinutes':
        GameContent.districts['industry']!.durationSeconds / 60,
    'routes': {
      for (final route in routes.entries) route.key: route.value.toJson(),
    },
    'tradeoffs': {
      'industryFirstIndustryCompletedMinutes': completion(
        industryFirst,
        'Mineral industry demonstration',
      ),
      'housingFirstIndustryCompletedMinutes': completion(
        housingFirst,
        'Mineral industry demonstration',
      ),
      'industryFirstHousingCompletedMinutes': completion(
        industryFirst,
        'Original coastal housing upgraded',
      ),
      'housingFirstHousingCompletedMinutes': completion(
        housingFirst,
        'Original coastal housing upgraded',
      ),
      'industryFirstCashAt60Minutes': industryFirst.state.money,
      'housingFirstCashAt60Minutes': housingFirst.state.money,
      'industryFirstPopulationAt60Minutes': industryFirst.state.population,
      'housingFirstPopulationAt60Minutes': housingFirst.state.population,
      'explanation':
          'Earlier housing produces revenue and research adjacency sooner; '
          'earlier industry produces factory efficiency and its research demonstration sooner. '
          'No route is declared globally optimal.',
    },
  };
}

/// React to actual research, construction, training and milestone completions.
/// External contracts fund the route but their automatic repeats are never
/// recorded as player decisions or meaningful development completions.
OnboardingVerification runParallelStrategyVerification({
  String partnershipChoice = 'funding',
}) {
  if (!['funding', 'technology'].contains(partnershipChoice)) {
    throw ArgumentError.value(partnershipChoice, 'partnershipChoice');
  }
  final technologyPath = partnershipChoice == 'technology';
  final game = GameEngine(GameState.initial(DateTime.utc(2026, 10, 14)));
  final events = <Map<String, Object>>[];
  final projects = <String, PlannedTask>{};
  final reported = <String>{};
  const horizon = Duration(hours: 1);
  var shiftedIdleResearchers = false;
  var allocatedFirstCohort = false;
  var allocatedSecondCohort = false;

  void record(String kind, String step) {
    final lab = game.state.currentPlanFor('lab');
    final factory = game.state.currentPlanFor('factory');
    final mars = game.state.currentPlanFor('mars');
    events.add({
      'kind': kind,
      'step': step,
      'elapsedMinutes': game.state.simulatedMs / Duration.millisecondsPerMinute,
      'money': game.state.money,
      'researchers': game.state.researchers,
      'industrialWorkers': game.state.industrialWorkers,
      'completedDistricts': game.state.districts.length,
      if (lab != null &&
          (factory?.definition.districtId != null ||
              mars?.definition.districtId != null))
        'parallelWork': {
          'lab': lab.taskId,
          if (factory?.definition.districtId != null)
            'factory': factory!.taskId,
          if (mars?.definition.districtId != null) 'mars': mars!.taskId,
        },
    });
  }

  void command(String? error, String step) {
    if (error != null) throw StateError('$step: $error');
    record('decision', step);
  }

  void prioritize(PlannedTask plan) {
    final others = game.state
        .upcomingPlansFor(plan.definition.facilityId)
        .where((other) => other.id != plan.id)
        .toList();
    if (others.isNotEmpty) {
      command(
        game.reorderPlan(
          plan.id,
          relativeToPlanId: others.first.id,
          before: true,
        ),
        'Prioritize ${plan.taskId} over future work',
      );
    }
  }

  void track(String key, String? error, String action, {bool first = false}) {
    command(error, action);
    final plan = game.state.plans.last;
    projects[key] = plan;
    if (first) prioritize(plan);
  }

  bool done(String key) => projects[key]?.status == 'completed';
  bool booked(String key) => projects.containsKey(key);
  void task(String key, String id, {bool first = false}) =>
      track(key, game.enqueue(id), 'Reserve $id', first: first);
  void district(String key, String city, int plot, String type) => track(
    key,
    game.enqueueDistrict(city, plot, type),
    'Develop $city:$plot:$type',
    first: true,
  );
  void moveResearchers(int count, String reason) {
    if (game.state.researchers != count) {
      command(game.assignResearchers(count), reason);
    }
  }

  command(
    game.enqueue('factory_contract', repeats: null),
    'Fund development with the factory',
  );
  command(
    game.enqueue('launch_contract', repeats: null),
    'Fund development with launch services',
  );
  task('Life support', 'life_support');
  district('First coastal housing', 'earth_delta', 0, 'housing');

  var iterations = 0;
  while (game.state.simulatedMs < horizon.inMilliseconds) {
    if (++iterations > 5000) {
      throw StateError('Parallel strategy did not converge');
    }
    for (final project in projects.entries.toList()) {
      if (done(project.key) && reported.add(project.key)) {
        record('completion', project.key);
      }
    }
    for (final offer in game.state.availablePartnerships.toList()) {
      command(
        game.choosePartnership(offer.id, partnershipChoice),
        'Choose $partnershipChoice for ${offer.id}',
      );
    }
    if (done('Life support') &&
        !booked('Urban planning') &&
        game.state.money >= GameContent.tasks['urban_planning']!.cost + 200) {
      task('Urban planning', 'urban_planning');
    }
    if (done('First coastal housing') && !booked('Second coastal housing')) {
      district('Second coastal housing', 'earth_delta', 5, 'housing');
    }
    if (done('Urban planning') && !booked('Campus adjoining both houses')) {
      district('Campus adjoining both houses', 'earth_delta', 1, 'campus');
      task('First habitat kit', 'habitat_kit', first: true);
    }
    if (done('First habitat kit') && !booked('First Mars delivery')) {
      task('First Mars delivery', 'mars_delivery', first: true);
    }
    if (done('First Mars delivery') && !booked('First Mars settlement')) {
      command(game.chooseHabitat('dome'), 'Choose dome habitation on plains');
      district('First Mars settlement', 'mars_arcadia', 2, 'mars_habitat');
    }
    if (projects['First Mars settlement']?.status == 'running' &&
        !shiftedIdleResearchers &&
        game.state.currentPlanFor('lab') == null) {
      // The factory retains all staff already committed to its paid work.
      // Move only idle researchers to prepare the following construction.
      moveResearchers(
        4,
        'Assign two idle researchers to upcoming construction',
      );
      shiftedIdleResearchers = true;
    }
    if (done('Campus adjoining both houses') &&
        !booked('Power supports the campus')) {
      district('Power supports the campus', 'earth_delta', 2, 'solar');
    }
    // Funding permits industry first; technology partnerships make early
    // housing revenue valuable. Do not block the factory's income behind an
    // unaffordable industry reservation in the cash-constrained route.
    if ((technologyPath
            ? done('Original coastal housing upgraded') &&
                  game.state.money >=
                      game.state
                          .districtPreview('earth_delta', 8, 'industry')
                          .cost
            : done('Power supports the campus')) &&
        !booked('Mineral industry demonstration')) {
      district('Mineral industry demonstration', 'earth_delta', 8, 'industry');
    }
    if ((technologyPath
            ? done('Power supports the campus')
            : done('Mineral industry demonstration')) &&
        !booked('Original coastal housing upgraded')) {
      track(
        'Original coastal housing upgraded',
        game.upgradeDistrict('earth_delta', 0),
        'Upgrade coastal housing while extending the Mars supply line',
        first: true,
      );
      task('Second habitat kit', 'habitat_kit', first: true);
    }
    if (done('Second habitat kit') && !booked('Second Mars delivery')) {
      task('Second Mars delivery', 'mars_delivery', first: true);
    }
    if (done('Second Mars delivery') && !booked('Second Mars settlement')) {
      district('Second Mars settlement', 'mars_arcadia', 3, 'mars_habitat');
    }

    if (done('First specialist cohort') && !allocatedFirstCohort) {
      final reason = game.state.staffAllocationReason(6);
      if (reason == null) {
        moveResearchers(
          6,
          'Assign the first cohort: six researchers and eight industrial workers',
        );
        allocatedFirstCohort = true;
      }
    }
    if (done('Second specialist cohort') && !allocatedSecondCohort) {
      final reason = game.state.staffAllocationReason(8);
      if (reason == null) {
        moveResearchers(
          8,
          'Assign the second cohort: eight researchers and eight industrial workers',
        );
        allocatedSecondCohort = true;
      }
    }
    if (game.state.currentPlanFor('lab') == null) {
      if (technologyPath) {
        // With no grants, invest in inexpensive useful research before staff.
        // Each decision is made when work or financing actually permits it.
        if (done('Campus adjoining both houses') &&
            !booked('Process design') &&
            game.state.money >=
                GameContent.tasks['process_design']!.cost + 100) {
          task('Process design', 'process_design');
        } else if (done('Process design') &&
            !booked('Cargo packaging') &&
            game.state.money >=
                GameContent.tasks['cargo_packaging']!.cost + 100) {
          task('Cargo packaging', 'cargo_packaging');
        } else if (done('Cargo packaging') &&
            !booked('First specialist cohort') &&
            game.state.money >=
                GameContent.tasks['train_specialists']!.cost + 100) {
          task('First specialist cohort', 'train_specialists');
        } else if (allocatedFirstCohort &&
            !booked('Habitat operations') &&
            game.state.money >=
                GameContent.tasks['habitat_operations']!.cost + 100) {
          task('Habitat operations', 'habitat_operations');
        } else if (done('Habitat operations') &&
            !booked('Second specialist cohort') &&
            game.state.money >=
                GameContent.tasks['train_specialists']!.cost + 100) {
          task('Second specialist cohort', 'train_specialists');
        } else if (allocatedSecondCohort &&
            done('Original coastal housing upgraded') &&
            !booked('Next transport project')) {
          task('Next transport project', 'reusable_launch');
        }
      } else if (shiftedIdleResearchers &&
          !booked('First specialist cohort') &&
          game.state.money >=
              GameContent.tasks['train_specialists']!.cost + 200) {
        task('First specialist cohort', 'train_specialists');
      } else if (done('First Mars settlement') &&
          allocatedFirstCohort &&
          !booked('Process design')) {
        task('Process design', 'process_design');
      } else if (done('Process design') && !booked('Cargo packaging')) {
        task('Cargo packaging', 'cargo_packaging');
      } else if (done('Cargo packaging') && !booked('Habitat operations')) {
        task('Habitat operations', 'habitat_operations');
      } else if (done('Habitat operations') &&
          !booked('Second specialist cohort') &&
          game.state.money >=
              GameContent.tasks['train_specialists']!.cost + 200) {
        task('Second specialist cohort', 'train_specialists');
      } else if (allocatedSecondCohort &&
          done('Original coastal housing upgraded') &&
          !booked('Next transport project')) {
        task('Next transport project', 'reusable_launch');
      }
    }
    // Every wait ends at a real job completion. Contract repeats provide income
    // but do not become decisions unless a concrete new plan is chosen there.
    final running = game.state.plans.where(
      (plan) =>
          plan.status == 'running' &&
          game.state.facilities[plan.definition.facilityId] == true,
    );
    if (running.isEmpty) {
      throw StateError('Parallel strategy has no running work');
    }
    final step = min(
      horizon.inMilliseconds - game.state.simulatedMs,
      running.map((plan) => plan.remainingMs).reduce(min),
    );
    game.advanceBy(Duration(milliseconds: step));
  }
  for (final project in projects.entries) {
    if (done(project.key) && reported.add(project.key)) {
      record('completion', project.key);
    }
  }
  record('checkpoint', '60-minute transition to reserved work');
  if (!done('First Mars settlement') ||
      !(technologyPath
          ? booked('Mineral industry demonstration')
          : done('Mineral industry demonstration')) ||
      !done('Original coastal housing upgraded') ||
      !done('Second specialist cohort') ||
      !allocatedSecondCohort ||
      !game.state.research.containsAll([
        'process_design',
        'cargo_packaging',
        'habitat_operations',
      ]) ||
      !booked('Second Mars settlement') ||
      game.state.partnershipChoices.length != (technologyPath ? 2 : 3)) {
    throw StateError(
      'Parallel strategy missed its first-hour objectives: ${jsonEncode(events)}',
    );
  }
  final snapshot = jsonEncode(game.state.toJson());
  final loaded = GameEngine(
    GameState.fromJson(jsonDecode(snapshot) as Map<String, dynamic>),
  );
  if (jsonEncode(loaded.state.toJson()) != snapshot) {
    throw StateError('Reload duplicated or lost staff, support or development');
  }
  final result = OnboardingVerification(game.state, events);
  if (result.maxDecisionGapMinutes > 6) {
    throw StateError('Parallel strategy left a decision gap over six minutes');
  }
  return result;
}

Map<String, Object> runParallelStrategyComparison() {
  double completionGap(OnboardingVerification route) {
    final times = [
      0.0,
      ...route.events
          .where((event) => event['kind'] == 'completion')
          .map((event) => event['elapsedMinutes']! as double),
      60.0,
    ]..sort();
    var longest = 0.0;
    for (var i = 1; i < times.length; i++) {
      longest = max(longest, times[i] - times[i - 1]);
    }
    return longest;
  }

  final routes = {
    for (final choice in ['funding', 'technology'])
      choice: runParallelStrategyVerification(partnershipChoice: choice),
  };
  return {
    'status': 'passed',
    'measurement':
        'Public commands from the initial save. Funding is earned '
        'only by explicit milestone choices; no state is injected. Decisions '
        'and meaningful completions exclude automatic contract repetitions. '
        'The routes adapt their order to available funds, so outcomes do not '
        'isolate partnership effects or prove an optimal choice. '
        'This does not measure a person’s active play time.',
    'district4Reference': {
      'sourceCommit': 'f385948',
      'maxDecisionGapMinutes': 13.54,
    },
    'routes': {
      for (final route in routes.entries)
        route.key: {
          ...route.value.toJson(),
          'investmentPolicy': route.key == 'funding'
              ? 'Industry before housing upgrade; early staff training.'
              : 'Housing upgrade before industry; inexpensive applied research '
                    'before training; preserve external factory income until '
                    'industry is affordable.',
          'unfinishedDevelopment': route.value.state.plans
              .where(
                (plan) =>
                    !plan.isFinished && !plan.taskId.endsWith('_contract'),
              )
              .map(
                (plan) => {
                  'task': plan.taskId,
                  'status': plan.status,
                  'stopReason': plan.stopReason,
                },
              )
              .toList(),
          'maxMeaningfulCompletionGapMinutes': completionGap(route.value),
          'meaningfulCompletionCount': route.value.events
              .where((event) => event['kind'] == 'completion')
              .length,
          'specialists': route.value.state.specialistCount,
          'researchers': route.value.state.researchers,
          'industrialWorkers': route.value.state.industrialWorkers,
          'partnershipChoices': route.value.state.partnershipChoices,
          'researchEfficiency': route.value.state.researchBonusPercent,
          'factoryEfficiency': route.value.state.factoryBonusPercent,
          'launchEfficiency': route.value.state.launchBonusPercent,
          'marsEfficiency': route.value.state.marsBonusPercent,
          'parallelWorkWitnesses': route.value.events
              .where((event) => event.containsKey('parallelWork'))
              .toList(),
        },
    },
  };
}
