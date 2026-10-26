import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

import 'city_progression_route.dart';

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
  } catch (error, stack) {
    stderr.writeln(
      jsonEncode({'status': 'failed', 'error': '$error', 'stack': '$stack'}),
    );
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
    'measurement': 'Simulated calendar time after the real protected walkthrough, including its normal first-house construction help; opening reading and active play time are not measured.',
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
  final game = GameEngine(GameState.initial(DateTime.utc(2026, 10, 26)));
  final milestones = <Map<String, Object>>[];
  final route = CityProgressionRoute(
    game,
    onEvent: (kind, step) {
      if (kind != 'completion') return;
      milestones.add({
        'step': step,
        'elapsedHours': game.state.simulatedMs / Duration.millisecondsPerHour,
        'money': game.state.money,
        'population': game.state.totalPopulation,
        'researchEfficiency': game.state.researchBonusPercent,
        'factoryEfficiency': game.state.factoryBonusPercent,
        'launchEfficiency': game.state.launchBonusPercent,
        'marsEfficiency': game.state.marsBonusPercent,
      });
    },
  );
  route.introduction();
  route.earnings();
  route.research('life_support');
  route.research('deployable_solar_arrays');
  route.research('urban_planning');
  route.accessMars();
  route.habitats(1);
  for (final id in [
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
  ]) {
    route.research(id);
  }
  route.habitats(2);
  if (includeFrontiers) {
    route.district('mars_lab');
    for (final id in GameContent.optionalFrontierResearchIds) {
      route.research(id);
    }
  }
  if (game.state.developedMarsCityIds.length != 2 ||
      game.state.marsHabitats != 2 ||
      game.state.research.length >=
          ResearchCatalog.purchasableTechnologies.length) {
    throw StateError(
      'The selected two-city habitation route was not preserved',
    );
  }
  final snapshot = jsonEncode(game.state.toJson());
  final loaded = GameEngine(
    GameState.fromJson(jsonDecode(snapshot) as Map<String, dynamic>),
  );
  if (jsonEncode(loaded.state.toJson()) != snapshot) {
    throw StateError('Reload changed the completed city, balances or rewards');
  }
  return ProgressionVerification(
    game.state,
    milestones,
    includesFrontiers: includeFrontiers,
  );
}

enum EarlyInvestmentOrder { industryOnly, industryFirst, housingFirst }

/// A public-command route through the first hour or an explicitly extended
/// investment comparison. It reports opportunities, not a person's play time.
class OnboardingVerification {
  const OnboardingVerification(this.state, this.events);
  final GameState state;
  final List<Map<String, Object>> events;

  List<Map<String, Object>> get decisions =>
      events.where((event) => event['kind'] == 'decision').toList();

  double get maxDecisionGapMinutes =>
      _maxGapUntil(state.simulatedMs / Duration.millisecondsPerMinute);
  double get maxDecisionGapInFirstHourMinutes => _maxGapUntil(60);

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
        'Scripted decision opportunities in ${state.simulatedMs ~/ Duration.millisecondsPerMinute} simulated minutes; '
        'includes the normal tutorial construction help, excludes opening reading; '
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
    'maxDecisionGapInFirstHourMinutes': maxDecisionGapInFirstHourMinutes,
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
  Duration? horizon,
}) {
  if (!parallelCargo && investmentOrder != EarlyInvestmentOrder.industryOnly) {
    throw ArgumentError(
      'Early investment comparisons use the parallel-cargo route',
    );
  }
  return _FirstHourRoute(
    parallelCargo: parallelCargo,
    investmentOrder: investmentOrder,
    horizon:
        horizon ??
        (parallelCargo
            ? const Duration(hours: 1)
            : const Duration(minutes: 90)),
  ).run();
}

/// Event-driven public decisions. New construction waits for an idle facility
/// and its full budget; research is purchased explicitly after RP and city
/// conditions are met. Background earnings and started work continue normally.
class _FirstHourRoute {
  _FirstHourRoute({
    this.parallelCargo = true,
    this.investmentOrder = EarlyInvestmentOrder.industryOnly,
    this.partnershipChoice,
    this.horizon = const Duration(hours: 1),
  });
  final bool parallelCargo;
  final EarlyInvestmentOrder investmentOrder;
  final String? partnershipChoice;
  final Duration horizon;
  final game = GameEngine(GameState.initial(DateTime.utc(2026, 10, 26)));
  final events = <Map<String, Object>>[];
  final projects = <String, PlannedTask>{};
  final reported = <String>{};
  bool analysisEnabled = false;

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
      'population': game.state.totalPopulation,
      'completedDistricts': game.state.districts.length,
      'researchCount': game.state.research.length,
      if (game.state.researchPointsPerMinute > 0 &&
          (factory?.definition.districtId != null ||
              mars?.definition.districtId != null))
        'parallelWork': {
          'research': 'Facility RP production',
          if (factory?.definition.districtId != null)
            'factory': factory!.taskId,
          if (mars?.definition.districtId != null) 'mars': mars!.taskId,
        },
    });
  }

  bool prepare(String facility, int cost) {
    if (game.state.money < cost) return false;
    if (game.state.facilities[facility] != true) {
      final reason = game.setFacilityEnabled(facility, true);
      if (reason != null) return false;
      record('decision', 'Resume $facility');
    }
    final current = game.state.currentPlanFor(facility);
    if (current == null) return true;
    if (current.remainingRepeats == null) {
      final reason = game.cancelQueued(current.id);
      if (reason != null) throw StateError(reason);
      record('decision', 'Finish current ${current.taskId} before investment');
    }
    return false;
  }

  void task(String label, String id) {
    if (booked(label)) return;
    final task = GameContent.tasks[id]!;
    String? reason;
    if (task.unique) {
      if (game.researchRequirementReasons(id).isNotEmpty ||
          game.state.researchPoints < GameContent.researchPointCost(id)) {
        return;
      }
      reason = game.unlockResearch(id);
    } else {
      if (!prepare(task.facilityId, game.state.taskCost(task))) return;
      reason = game.enqueue(id);
    }
    if (reason != null) return;
    projects[label] = game.state.plans.last;
    record('decision', task.unique ? 'Unlock $id' : 'Start $id');
  }

  void district(String label, String city, int plot, String type) {
    if (booked(label)) return;
    final quote = game.state.districtPreview(city, plot, type);
    if (!quote.isValid) return;
    final planet = GameContent.districts[type]!.planet;
    if (!prepare(planet == 'earth' ? 'factory' : planet, quote.cost)) return;
    final reason = game.enqueueDistrict(city, plot, type);
    if (reason != null) throw StateError('$label: $reason');
    projects[label] = game.state.plans.last;
    record('decision', 'Develop $city:$plot:$type');
  }

  void upgradeHousing() {
    const label = 'Original coastal housing upgraded';
    if (booked(label)) return;
    final quote = game.state.districtPreview(
      'earth_delta',
      0,
      'housing',
      upgrade: true,
    );
    if (!quote.isValid || !prepare('factory', quote.cost)) return;
    final reason = game.upgradeDistrict('earth_delta', 0);
    if (reason != null) throw StateError(reason);
    projects[label] = game.state.plans.last;
    record('decision', 'Upgrade coastal housing');
  }

  void analysisLab() {
    const label = 'Next research installation';
    if (booked(label) || !game.state.research.contains('local_resources')) {
      return;
    }
    final quote = game.state.buildingPreview(
      'local_resources',
      cityId: 'earth_delta',
      plotIndex: 10,
    );
    if (!quote.isValid || !prepare('lab', quote.cost)) return;
    final reason = game.enqueueMapBuilding(
      'local_resources',
      cityId: 'earth_delta',
      plotIndex: 10,
    );
    if (reason != null) throw StateError(reason);
    projects[label] = game.state.plans.last;
    record('decision', 'Build local resource analysis laboratory');
  }

  void earnings() {
    for (final entry in {
      'factory': 'factory_contract',
      'launch': 'launch_contract',
    }.entries) {
      if (game.state.currentPlanFor(entry.key) != null ||
          game.state.plans.any(
            (p) => !p.isFinished && p.definition.facilityId == entry.key,
          )) {
        continue;
      }
      if (game.state.facilities[entry.key] != true &&
          game.state.money >=
              GameContent.facilities[entry.key]!.upkeepPerMinute) {
        final reason = game.setFacilityEnabled(entry.key, true);
        if (reason != null) continue;
      }
      final reason = game.enqueue(entry.value, repeats: null);
      if (reason == null) record('decision', 'Earn with ${entry.value}');
    }
  }

  OnboardingVerification run() {
    final introduction = CityProgressionRoute(game, onEvent: record);
    introduction.introduction();
    projects['First coastal housing'] = game.state.plans.firstWhere(
      (p) => p.taskId == 'district_housing',
    );
    projects['Life support'] = game.state.plans.firstWhere(
      (p) => p.taskId == 'life_support',
    );
    reported.addAll(['First coastal housing', 'Life support']);
    earnings();
    var iterations = 0;
    while (game.state.simulatedMs < horizon.inMilliseconds) {
      if (++iterations > 5000) {
        throw StateError('First-hour policy did not converge');
      }
      for (final project in projects.entries) {
        if (done(project.key) && reported.add(project.key)) {
          record('completion', project.key);
        }
      }
      task('Solar research', 'deployable_solar_arrays');
      if (done('Solar research')) task('Urban planning', 'urban_planning');
      if (done('Urban planning')) task('Resource survey', 'local_resources');
      if (done('Resource survey')) {
        task('Greenhouse research', 'orbital_gardens');
      }
      if (done('First coastal housing') && parallelCargo) {
        task('First habitat kit', 'habitat_kit');
      }
      if (done('First coastal housing') &&
          (!parallelCargo || done('First habitat kit'))) {
        district('Second coastal housing', 'earth_delta', 5, 'housing');
      }
      if (done('Second coastal housing')) {
        district('Power supports the campus', 'earth_delta', 2, 'solar');
      }
      if (done('Urban planning')) {
        if (!parallelCargo || booked('First Mars kit')) {
          district('Campus adjoining both houses', 'earth_delta', 1, 'campus');
        }
        if (partnershipChoice != null) {
          for (final offer in game.state.availablePartnerships.toList()) {
            final reason = game.choosePartnership(offer.id, partnershipChoice!);
            if (reason != null) throw StateError(reason);
            record('decision', 'Choose $partnershipChoice for ${offer.id}');
          }
        }
      }
      if (done('Campus adjoining both houses') && !parallelCargo) {
        task('First habitat kit', 'habitat_kit');
      }
      if (done('First habitat kit')) {
        task('First Moon delivery', 'moon_delivery');
      }
      if (done('First Moon delivery')) {
        district('Moon outpost', 'moon_south_pole', 2, 'moon_outpost');
        task('Second Moon kit', 'habitat_kit');
      }
      if (done('Second Moon kit')) {
        task('Second Moon delivery', 'moon_delivery');
      }
      if (done('Moon outpost') && done('Second Moon delivery')) {
        district('Moon launch base', 'moon_south_pole', 3, 'moon_spaceport');
      }
      if (done('Moon launch base')) {
        task('Mars exploration', 'mars_probe');
        task('First Mars kit', 'habitat_kit');
      }
      if (done('Mars exploration') && done('First Mars kit')) {
        task('First Mars delivery', 'mars_delivery');
      }
      if (done('First Mars delivery')) {
        if (game.state.habitatChoice == null) {
          final reason = game.chooseHabitat('dome');
          if (reason != null) throw StateError(reason);
          record('decision', 'Choose dome habitation');
        }
        district('First Mars settlement', 'mars_arcadia', 2, 'mars_habitat');
      }
      if (done('Campus adjoining both houses') &&
          booked('First Mars settlement')) {
        if (investmentOrder == EarlyInvestmentOrder.housingFirst) {
          upgradeHousing();
          if (done('Original coastal housing upgraded')) {
            district(
              'Mineral industry demonstration',
              'earth_delta',
              8,
              'industry',
            );
          }
        } else {
          district(
            'Mineral industry demonstration',
            'earth_delta',
            8,
            'industry',
          );
          if (investmentOrder == EarlyInvestmentOrder.industryFirst &&
              done('Mineral industry demonstration')) {
            upgradeHousing();
          }
        }
      }
      if (done('Mineral industry demonstration') &&
          done('Greenhouse research')) {
        task('Next robotics knowledge', 'autonomous_rovers');
      }
      if (booked('First Mars settlement') &&
          booked('Campus adjoining both houses')) {
        analysisLab();
      }
      if (done('Next research installation') && !analysisEnabled) {
        final instance =
            projects['Next research installation']!.buildingInstanceId!;
        final reason = game.setDevelopmentEnabled(instance, true);
        if (reason == null) {
          analysisEnabled = true;
          record('decision', 'Operate the resource analysis laboratory');
        }
      }
      if (analysisEnabled) {
        task('Next resource knowledge', 'subsurface_ice_mapping');
      }
      earnings();
      var wait = mathMin(
        horizon.inMilliseconds - game.state.simulatedMs,
        const Duration(minutes: 1).inMilliseconds,
      );
      for (final plan in game.state.plans.where((p) => p.status == 'running')) {
        if (game.state.facilities[plan.definition.facilityId] == true) {
          wait = mathMin(wait, plan.remainingMs);
        }
      }
      if (game.state.introductionPausesClock) {
        throw StateError(
          'First-hour time cannot advance during the protected introduction',
        );
      }
      game.advanceBy(Duration(milliseconds: wait));
    }
    for (final project in projects.entries) {
      if (done(project.key) && reported.add(project.key)) {
        record('completion', project.key);
      }
    }
    record(
      'checkpoint',
      '${horizon.inMinutes}-minute handoff to started offline work',
    );
    if (game.state.marsHabitats != 1 ||
        game.state.marsResidents != 24 ||
        game.state.districts.length < 5 ||
        !game.state.research.containsAll([
          'life_support',
          'deployable_solar_arrays',
          'urban_planning',
        ])) {
      throw StateError(
        '${horizon.inMinutes}-minute route goals were not reached: ${jsonEncode(events)}',
      );
    }
    final snapshot = jsonEncode(game.state.toJson());
    final loaded = GameEngine(
      GameState.fromJson(jsonDecode(snapshot) as Map<String, dynamic>),
    );
    if (jsonEncode(loaded.state.toJson()) != snapshot) {
      throw StateError('First-hour reload changed progress');
    }
    return OnboardingVerification(game.state, events);
  }

  int mathMin(int a, int b) => a < b ? a : b;
}

/// All three routes start with the same unmodified initial save and public
/// commands. The district-3 reference is a recorded run, not a re-simulation
/// using current prices. The two upgraded routes buy the same final facilities.
Map<String, Object> runEarlyInvestmentVerification() {
  final routes = {
    for (final order in EarlyInvestmentOrder.values)
      order.name: runOnboardingVerification(
        investmentOrder: order,
        horizon: const Duration(minutes: 90),
      ),
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
      route.state.simulatedMs == const Duration(minutes: 90).inMilliseconds,
      'Early investments must be measured at the same 90-minute horizon',
    );
    require(
      route.state.districtAt('earth_delta', 8)?.districtId == 'industry',
      'Each extended investment route must finish the industrial district',
    );
    require(
      route.state.marsHabitats == 1 && route.state.marsResidents == 24,
      'Investment changes must preserve the first Mars settlement',
    );
    require(
      route.maxDecisionGapInFirstHourMinutes < 21.46,
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
      'industryFirstCashAt90Minutes': industryFirst.state.money,
      'housingFirstCashAt90Minutes': housingFirst.state.money,
      'industryFirstPopulationAt90Minutes': industryFirst.state.population,
      'housingFirstPopulationAt90Minutes': housingFirst.state.population,
      'explanation':
          'Earlier housing produces revenue and research adjacency sooner; '
          'earlier industry produces factory efficiency sooner. '
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
              ? 'Start industry before upgrading housing; facility RP accrues alongside construction.'
              : 'Upgrade housing before starting industry, then invest in a research installation.',
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
          'population': route.value.state.totalPopulation,
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
