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
        ? 'A selected habitation and six-frontier route, not all research or the global-environment ending.'
        : 'A selected habitation route with its discovered prerequisites; other branches remain optional.',
    'optionalResearchIncluded': includesFrontiers,
    'elapsedHours': state.simulatedMs / Duration.millisecondsPerHour,
    'elapsedDays': state.simulatedMs / Duration.millisecondsPerDay,
    'finalMoney': state.money,
    'researchCount': state.research.length,
    'researchPoints': state.researchPoints,
    'researchPointsPerMinute': state.researchPointsPerMinute,
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
      final waits = [
        ...running.map((plan) => plan.remainingMs),
        for (final plan in game.state.plans.where(
          (plan) => !plan.isFinished && plan.definition.unique,
        ))
          if (game.state.researchWaitMs(plan.taskId) case final int milliseconds
              when milliseconds > 0)
            milliseconds,
      ];
      require(
        waits.isNotEmpty,
        'Route is blocked: ${game.state.plans.where((p) => !p.isFinished).map((p) => '${p.taskId}: ${p.stopReason}').join(' / ')}',
      );
      game.advanceBy(Duration(milliseconds: waits.reduce(min)));
      require(++events < 200000, 'Too many completion events');
      require(
        game.state.simulatedMs < const Duration(days: 30).inMilliseconds,
        'The selected habitation route exceeded its 30-day watchdog; this is not an all-research or global-ending target',
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
    _studyPublicResearch(
      game,
      id,
      command: command,
      waitUntil: advanceUntil,
      onCompleted: record,
    );
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
    game.state.research.containsAll([
      'life_support',
      'urban_planning',
      'process_design',
      'cargo_packaging',
      'habitat_operations',
      'automated_fabrication',
      'reusable_launch',
      'orbital_logistics',
      'closed_ecology',
      'local_resources',
      'intercity_logistics',
      'industrial_network',
      'regional_habitats',
      if (includeFrontiers) ...GameContent.optionalFrontierResearchIds,
    ]),
    'The selected route or a requested frontier was not reachable',
  );
  require(
    game.state.research.length < ResearchCatalog.purchasableTechnologies.length,
    'Habitation must leave other research branches available',
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

/// Visit only the exposed research frontier. Dependencies determine the chosen
/// goal, while hidden roots are reached by completing affordable visible work
/// in the same field. No knowledge, points, money or facilities are injected.
void _studyPublicResearch(
  GameEngine game,
  String id, {
  required void Function(String? reason) command,
  required void Function(bool Function()) waitUntil,
  required void Function(String id) onCompleted,
}) {
  if (game.state.research.contains(id)) return;
  final target = GameContent.researchTechnologies[id]!;
  for (final parent in target.prerequisiteIds) {
    _studyPublicResearch(
      game,
      parent,
      command: command,
      waitUntil: waitUntil,
      onCompleted: onCompleted,
    );
  }
  if (target.alternativePrerequisiteIds.isNotEmpty &&
      !target.alternativePrerequisiteIds.any(game.state.research.contains)) {
    _studyPublicResearch(
      game,
      target.alternativePrerequisiteIds.first,
      command: command,
      waitUntil: waitUntil,
      onCompleted: onCompleted,
    );
  }
  var discoverySteps = 0;
  while (!game.state.isResearchDiscovered(id)) {
    final candidates =
        GameContent.researchTechnologies.values
            .where(
              (candidate) =>
                  candidate.isPurchasable &&
                  candidate.field == target.field &&
                  game.state.isResearchDiscovered(candidate.id) &&
                  !game.state.research.contains(candidate.id) &&
                  game.researchRequirementReasons(candidate.id).isEmpty,
            )
            .toList()
          ..sort((a, b) {
            final cost = GameContent.researchPointCost(a.id)
                .compareTo(GameContent.researchPointCost(b.id));
            return cost != 0 ? cost : a.catalogId.compareTo(b.catalogId);
          });
    if (candidates.isEmpty || ++discoverySteps > 30) {
      throw StateError('No exposed research can reveal ${target.catalogId}');
    }
    final candidate = candidates.first;
    command(game.enqueue(candidate.id));
    waitUntil(() => game.state.research.contains(candidate.id));
    onCompleted(candidate.id);
  }
  if (!game.state.research.contains(id)) {
    command(game.enqueue(id));
    waitUntil(() => game.state.research.contains(id));
    onCompleted(id);
  }
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
  return _FirstHourRoute(
    parallelCargo: parallelCargo,
    investmentOrder: investmentOrder,
  ).run();
}

/// A reproducible first-hour policy. It reacts to exposed knowledge, actual
/// completions and earned money. Research production runs alongside other work;
/// paid training consumes the laboratory and its researchers instead of an
/// obsolete research timer. No state is injected into these playable routes.
class _FirstHourRoute {
  _FirstHourRoute({
    this.parallelCargo = true,
    this.investmentOrder = EarlyInvestmentOrder.industryOnly,
    this.partnershipChoice,
  });
  final bool parallelCargo;
  final EarlyInvestmentOrder investmentOrder;
  final String? partnershipChoice;
  final game = GameEngine(GameState.initial(DateTime.utc(2026, 10, 14)));
  final events = <Map<String, Object>>[];
  final projects = <String, PlannedTask>{};
  final reported = <String>{};
  static const horizon = Duration(hours: 1);
  bool firstCohortAllocated = false;
  bool secondCohortAllocated = false;
  bool stoppedContractForStaff = false;
  bool thirdCohortAllocated = false;

  bool booked(String label) => projects.containsKey(label);
  bool done(String label) => projects[label]?.status == 'completed';

  void record(String kind, String step) {
    final factory = game.state.currentPlanFor('factory');
    final mars = game.state.currentPlanFor('mars');
    events.add({
      'kind': kind,
      'step': step,
      'elapsedMinutes': game.state.simulatedMs / Duration.millisecondsPerMinute,
      'money': game.state.money,
      'researchPoints': game.state.researchPoints,
      'researchPointsPerMinute': game.state.researchPointsPerMinute,
      'researchers': game.state.researchers,
      'industrialWorkers': game.state.industrialWorkers,
      'completedDistricts': game.state.districts.length,
      'researchCount': game.state.research.length,
      if (game.state.researchPointsPerMinute > 0 &&
          (factory?.definition.districtId != null ||
              mars?.definition.districtId != null))
        'parallelWork': {
          'research': 'Common RP production',
          if (factory?.definition.districtId != null)
            'factory': factory!.taskId,
          if (mars?.definition.districtId != null) 'mars': mars!.taskId,
        },
    });
  }

  void command(String? reason, String action) {
    if (reason != null) throw StateError('$action: $reason');
    record('decision', action);
  }

  void prioritize(PlannedTask plan, {bool first = false}) {
    final others = game.state
        .upcomingPlansFor(plan.definition.facilityId)
        .where(
          (other) =>
              other.id != plan.id &&
              (first || other.taskId.endsWith('_contract')),
        )
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

  void track(
    String label,
    String? result,
    String action, {
    bool first = false,
  }) {
    command(result, action);
    final plan = game.state.plans.last;
    projects[label] = plan;
    prioritize(plan, first: first);
  }

  void task(String label, String id, {bool first = false}) =>
      track(label, game.enqueue(id), 'Reserve $id', first: first);
  void district(String label, String city, int plot, String type) => track(
    label,
    game.enqueueDistrict(city, plot, type),
    'Develop $city:$plot:$type',
  );
  void upgradeHousing() => track(
    'Original coastal housing upgraded',
    game.upgradeDistrict('earth_delta', 0),
    'Upgrade coastal housing',
  );

  void collectCompletions() {
    for (final project in projects.entries) {
      if (done(project.key) && reported.add(project.key)) {
        record('completion', project.key);
      }
    }
  }

  OnboardingVerification run() {
    command(
      game.enqueue('factory_contract', repeats: null),
      'Fund development with the factory',
    );
    command(
      game.enqueue('launch_contract', repeats: null),
      'Fund development with launch services',
    );
    task('Life support', 'life_support');
    task('Solar research', 'deployable_solar_arrays');
    district('First coastal housing', 'earth_delta', 0, 'housing');
    var iterations = 0;
    while (game.state.simulatedMs < horizon.inMilliseconds) {
      if (++iterations > 5000)
        throw StateError('The first-hour policy did not converge');
      collectCompletions();
      if (done('Solar research') && !booked('Urban planning')) {
        task('Urban planning', 'urban_planning');
      }
      if (done('Urban planning') && !booked('Resource survey')) {
        task('Resource survey', 'local_resources');
      }
      if (done('Resource survey') && !booked('Greenhouse research')) {
        task('Greenhouse research', 'orbital_gardens');
      }
      if (done('First coastal housing') &&
          parallelCargo &&
          !booked('First habitat kit')) {
        task('First habitat kit', 'habitat_kit');
      }
      if (done('First coastal housing') &&
          (!parallelCargo || done('First habitat kit')) &&
          !booked('Second coastal housing')) {
        district('Second coastal housing', 'earth_delta', 5, 'housing');
      }
      if (done('Second coastal housing') &&
          !booked('Power supports the campus')) {
        district('Power supports the campus', 'earth_delta', 2, 'solar');
      }
      if (done('Power supports the campus') &&
          done('Urban planning') &&
          !booked('First specialist cohort')) {
        task('First specialist cohort', 'train_specialists', first: true);
      }
      if (done('First specialist cohort') && !firstCohortAllocated) {
        // Keep the six researchers already supporting paid laboratory work;
        // the first new cohort becomes industrial capacity immediately.
        command(
          game.assignResearchers(6),
          'Keep six researchers and add industrial capacity',
        );
        firstCohortAllocated = true;
      }
      if (done('Urban planning') && !booked('Campus adjoining both houses')) {
        district('Campus adjoining both houses', 'earth_delta', 1, 'campus');
      }
      if (partnershipChoice != null && done('Urban planning')) {
        for (final offer in game.state.availablePartnerships.toList()) {
          command(
            game.choosePartnership(offer.id, partnershipChoice!),
            'Choose $partnershipChoice for ${offer.id}',
          );
        }
      }
      if (done('Urban planning') &&
          firstCohortAllocated &&
          !booked('Second specialist cohort')) {
        task('Second specialist cohort', 'train_specialists', first: true);
      }
      if (done('Second specialist cohort') && !secondCohortAllocated) {
        if (game.state.staffAllocationReason(8) == null) {
          command(
            game.assignResearchers(8),
            'Assign eight researchers and eight industrial workers',
          );
          secondCohortAllocated = true;
          if (stoppedContractForStaff) {
            command(
              game.enqueue('factory_contract', repeats: null),
              'Resume factory earnings after preserving paid staffing',
            );
          }
        } else if (!stoppedContractForStaff) {
          final contract = game.state.plans.firstWhere(
            (plan) => plan.taskId == 'factory_contract' && !plan.isFinished,
          );
          command(
            game.cancelQueued(contract.id),
            'Finish paid factory work before reallocating trained staff',
          );
          stoppedContractForStaff = true;
        }
      }
      if (done('Greenhouse research') &&
          secondCohortAllocated &&
          !booked('Next robotics knowledge')) {
        task('Next robotics knowledge', 'autonomous_rovers');
      }
      if (partnershipChoice != null &&
          booked('Next robotics knowledge') &&
          !done('Next robotics knowledge') &&
          !booked('Third specialist cohort') &&
          game.state.researchPoints >=
              GameContent.researchPointCost('autonomous_rovers') / 2) {
        task('Third specialist cohort', 'train_specialists', first: true);
      }
      if (done('Third specialist cohort') &&
          !thirdCohortAllocated &&
          game.state.staffAllocationReason(10) == null) {
        command(
          game.assignResearchers(10),
          'Invest the third cohort in faster common RP production',
        );
        thirdCohortAllocated = true;
      }
      if (done('Next robotics knowledge') && !booked('Next research project')) {
        task('Next research project', 'automated_fabrication');
      }
      if (done('Campus adjoining both houses') &&
          !parallelCargo &&
          !booked('First habitat kit')) {
        task('First habitat kit', 'habitat_kit');
      }
      if (done('First habitat kit') && !booked('First Mars delivery')) {
        task('First Mars delivery', 'mars_delivery');
      }
      if (done('First Mars delivery') && !booked('First Mars settlement')) {
        command(game.chooseHabitat('dome'), 'Choose dome habitation on plains');
        district('First Mars settlement', 'mars_arcadia', 2, 'mars_habitat');
      }
      if (done('Campus adjoining both houses') &&
          (parallelCargo || booked('First habitat kit'))) {
        if (investmentOrder == EarlyInvestmentOrder.housingFirst) {
          if (!booked('Original coastal housing upgraded')) upgradeHousing();
          if (done('Original coastal housing upgraded') &&
              !booked('Mineral industry demonstration')) {
            district(
              'Mineral industry demonstration',
              'earth_delta',
              8,
              'industry',
            );
          }
        } else {
          if (!booked('Mineral industry demonstration')) {
            district(
              'Mineral industry demonstration',
              'earth_delta',
              8,
              'industry',
            );
          }
          if (investmentOrder == EarlyInvestmentOrder.industryFirst &&
              booked('Mineral industry demonstration') &&
              !booked('Original coastal housing upgraded')) {
            upgradeHousing();
          }
        }
      }
      final nextSupplyBudget =
          GameContent.tasks['habitat_kit']!.cost +
          GameContent.tasks['mars_delivery']!.cost +
          game.state.districtPreview('mars_arcadia', 3, 'mars_habitat').cost;
      if (partnershipChoice != null &&
          done('Next robotics knowledge') &&
          booked('Original coastal housing upgraded') &&
          booked('Mineral industry demonstration') &&
          game.state.money >= nextSupplyBudget &&
          !booked('Second habitat kit')) {
        task('Second habitat kit', 'habitat_kit');
      }
      if (partnershipChoice != null &&
          done('Original coastal housing upgraded') &&
          booked('Second habitat kit') &&
          !booked('Second Mars settlement')) {
        district('Second Mars settlement', 'mars_arcadia', 3, 'mars_habitat');
      }
      if (done('Second habitat kit') && !booked('Second Mars delivery')) {
        task('Second Mars delivery', 'mars_delivery');
      }
      final waits = <int>[
        horizon.inMilliseconds - game.state.simulatedMs,
        if (partnershipChoice != null &&
            booked('Next robotics knowledge') &&
            !done('Next robotics knowledge') &&
            !booked('Third specialist cohort') &&
            game.state.researchPointUnitsPerMs > 0 &&
            game.state.researchPoints <
                GameContent.researchPointCost('autonomous_rovers') / 2)
          ((GameContent.researchPointCost('autonomous_rovers') *
                          GameState.researchPointScale ~/
                          2 -
                      game.state.researchPointUnits) +
                  game.state.researchPointUnitsPerMs -
                  1) ~/
              game.state.researchPointUnitsPerMs,
        for (final plan in game.state.plans.where(
          (plan) =>
              plan.status == 'running' &&
              game.state.facilities[plan.definition.facilityId] == true,
        ))
          plan.remainingMs,
        for (final plan in game.state.plans.where(
          (plan) => !plan.isFinished && plan.definition.unique,
        ))
          if (game.state.researchWaitMs(plan.taskId) case final int milliseconds
              when milliseconds > 0)
            milliseconds,
      ];
      game.advanceBy(Duration(milliseconds: waits.reduce(min)));
    }
    collectCompletions();
    record(
      'checkpoint',
      '${horizon.inMinutes}-minute handoff to reserved offline work',
    );
    if (game.state.marsHabitats != 1 ||
        game.state.marsResidents != 24 ||
        game.state.districts.length < 5 ||
        !done('Mineral industry demonstration') ||
        !secondCohortAllocated ||
        game.state.specialistCount != (partnershipChoice == null ? 16 : 18) ||
        (partnershipChoice != null && !thirdCohortAllocated) ||
        !game.state.research.containsAll([
          'life_support',
          'deployable_solar_arrays',
          'local_resources',
          'orbital_gardens',
          'urban_planning',
        ])) {
      throw StateError(
        'First-hour goals were not reached: ${jsonEncode(events)}',
      );
    }
    final snapshot = jsonEncode(game.state.toJson());
    final loaded = GameEngine(
      GameState.fromJson(jsonDecode(snapshot) as Map<String, dynamic>),
    );
    if (jsonEncode(loaded.state.toJson()) != snapshot) {
      throw StateError(
        'The first-hour reload changed money, RP, staff, districts or rewards',
      );
    }
    return OnboardingVerification(game.state, events);
  }
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
  return _FirstHourRoute(
    investmentOrder: partnershipChoice == 'funding'
        ? EarlyInvestmentOrder.industryFirst
        : EarlyInvestmentOrder.housingFirst,
    partnershipChoice: partnershipChoice,
  ).run();
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
              ? 'Reserve industry before upgrading housing; train three staff '
                    'cohorts while common research points accrue.'
              : 'Upgrade housing before reserving industry; train three staff '
                    'cohorts and preserve paid factory work before reallocating '
                    'new researchers.',
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
