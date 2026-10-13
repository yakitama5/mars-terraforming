import 'dart:convert';
import 'dart:io';

import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

/// Counterfactual balance comparisons. Unlike verify_progression.dart these
/// fixtures explicitly inject research, money, and existing urban layouts.
void main() {
  try {
    stdout.writeln(jsonEncode(runInvestmentVerification()));
  } catch (error) {
    stderr.writeln(jsonEncode({'status': 'failed', 'error': '$error'}));
    exitCode = 1;
  }
}

typedef Investment = ({String city, int plot, String district, bool upgrade});

Investment build(String city, int plot, String district) =>
    (city: city, plot: plot, district: district, upgrade: false);
Investment upgrade(String city, int plot, String district) =>
    (city: city, plot: plot, district: district, upgrade: true);

Map<String, Object> runInvestmentVerification() {
  final growing = _fixture(dense: false);
  final dense = _fixture(dense: true);
  final choices = <String, List<Investment>>{
    'isolated_housing_upgrade': [upgrade('earth_delta', 23, 'housing')],
    'clustered_housing_upgrade': [upgrade('earth_delta', 0, 'housing')],
    'current_city_housing': [build('earth_delta', 10, 'housing')],
    'new_city_housing': [build('earth_highland', 2, 'housing')],
    'clustered_campus_upgrade': [upgrade('earth_delta', 1, 'campus')],
    'current_city_ridge_campus': [build('earth_delta', 4, 'campus')],
    'new_city_ridge_campus': [build('earth_highland', 0, 'campus')],
  };
  final scenarios = <Map<String, Object>>[];
  for (final entry in {'growing': growing, 'dense': dense}.entries) {
    final results = [
      for (final choice in choices.entries)
        _run(entry.value, choice.key, choice.value),
    ];
    final packages = [
      _run(entry.value, 'three_existing_city_ridge_campuses', [
        build('earth_delta', 4, 'campus'),
        build('earth_delta', 9, 'campus'),
        build('earth_delta', 19, 'campus'),
      ]),
      _run(entry.value, 'three_new_city_ridge_campuses', [
        build('earth_highland', 0, 'campus'),
        build('earth_highland', 1, 'campus'),
        build('earth_highland', 5, 'campus'),
      ]),
    ];
    scenarios.add({
      'scenario': entry.key,
      'completedPlots': entry.value
          .cityDevelopment('earth_delta')
          .completedPlots,
      'startingEfficiencies': _efficiencies(entry.value),
      'singleInvestments': results,
      'strictlyDominatedSingleInvestments': _dominated(results),
      'threeInvestmentPackages': packages,
      'strictlyDominatedPackages': _dominated(packages),
    });
  }
  return {
    'status': 'passed',
    'contentVersion': GameContent.version,
    'measurement':
        'Counterfactual fixtures inject money, research, and layouts. '
        'Every candidate within a scenario starts from the exact same state. '
        'This is not a playable progression route or an active-time estimate.',
    'dominanceDefinition':
        'No greater cost, occupied equipment time, or additional plots; '
        'no lower net income or effective research/factory/launch/Mars efficiency; '
        'strictly better in at least one. Future land options are not monetized.',
    'opportunityCost':
        'Foregone gross contract margin assumes the same factory '
        'would continuously run the currently unlocked best contract. '
        'It excludes common facility upkeep, cash timing, and finite contract cycles.',
    'scenarios': scenarios,
  };
}

GameState _fixture({required bool dense}) {
  final state = GameState.initial(DateTime.utc(2026, 10, 13))..money = 10000000;
  state.research.addAll([
    'life_support',
    'urban_planning',
    'automated_fabrication',
    'reusable_launch',
    'orbital_logistics',
    'closed_ecology',
    'local_resources',
  ]);
  void add(int plot, String district) {
    final item = DistrictState(
      cityId: 'earth_delta',
      plotIndex: plot,
      districtId: district,
    );
    state.districts[item.key] = item;
  }

  add(0, 'housing');
  add(5, 'housing');
  add(23, 'housing');
  add(1, 'campus');
  add(2, 'solar');
  add(8, 'industry');
  if (dense) {
    // Mature mixed residential city; retain the same investment candidates.
    for (final plot in [3, 6, 7, 11, 12, 13, 14, 15, 16, 17, 18, 20]) {
      add(plot, 'housing');
    }
  }
  state.population = 120 + state.districtCount('housing') * 60;
  return state;
}

Map<String, int> _efficiencies(GameState state) => {
  'research': state.researchBonusPercent,
  'factory': state.factoryBonusPercent,
  'launch': state.launchBonusPercent,
  'mars': state.marsBonusPercent,
};

GameState _copy(GameState state) => GameState.fromJson(
  jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
);

Map<String, Object> _run(
  GameState baseline,
  String name,
  List<Investment> steps,
) {
  final game = GameEngine(_copy(baseline));
  final before = _efficiencies(game.state);
  final startingNet = game.state.netPerMinute;
  final startingPlots = game.state.districts.length;
  final factoryTask =
      GameContent.tasks[game.state.research.contains('automated_fabrication')
          ? 'precision_contract'
          : 'factory_contract']!;
  var cost = 0, setup = 0, occupation = 0;
  var foregoneMargin = 0.0;
  final quotes = <Map<String, Object>>[];
  for (final step in steps) {
    final quote = game.state.districtPreview(
      step.city,
      step.plot,
      step.district,
      upgrade: step.upgrade,
    );
    if (!quote.isValid) throw StateError('$name: ${quote.blockedReason}');
    cost += quote.cost;
    setup += quote.setupCost;
    occupation += quote.durationMs;
    foregoneMargin +=
        (factoryTask.reward - factoryTask.cost) *
        quote.durationMs /
        game.state.currentTaskDurationMs(factoryTask.id);
    quotes.add({
      'city': step.city,
      'plot': step.plot,
      'district': step.district,
      'upgrade': step.upgrade,
      'cost': quote.cost,
      'setupCost': quote.setupCost,
      'developmentPercent': quote.developmentPercent,
      'equipmentMinutes': quote.durationMs / Duration.millisecondsPerMinute,
      'netPerMinute': quote.netDeltaPerMinute,
      'rawResearchDelta': quote.rawResearchBonusDelta,
      'effectiveResearchDelta': quote.researchBonusDelta,
    });
    final priorNet = game.state.netPerMinute;
    final priorEfficiency = _efficiencies(game.state);
    final reason = step.upgrade
        ? game.upgradeDistrict(step.city, step.plot)
        : game.enqueueDistrict(step.city, step.plot, step.district);
    if (reason != null) throw StateError('$name: $reason');
    final plan = game.state.plans.last;
    if (plan.status != 'running' || plan.remainingMs != quote.durationMs) {
      throw StateError('$name: reserved cost/time differs from the comparison');
    }
    game.advanceBy(Duration(milliseconds: plan.remainingMs));
    if (!plan.isFinished ||
        game.state.netPerMinute - priorNet != quote.netDeltaPerMinute ||
        game.state.researchBonusPercent - priorEfficiency['research']! !=
            quote.researchBonusDelta ||
        game.state.factoryBonusPercent - priorEfficiency['factory']! !=
            quote.factoryBonusDelta ||
        game.state.launchBonusPercent - priorEfficiency['launch']! !=
            quote.launchBonusDelta ||
        game.state.marsBonusPercent - priorEfficiency['mars']! !=
            quote.marsBonusDelta) {
      throw StateError('$name: realized effects differ from the comparison');
    }
    final restored = GameEngine(_copy(game.state));
    if (jsonEncode(restored.state.toJson()) !=
        jsonEncode(game.state.toJson())) {
      throw StateError(
        '$name: reloading duplicated or lost investment effects',
      );
    }
  }
  final after = _efficiencies(game.state);
  final netDelta = game.state.netPerMinute - startingNet;
  return {
    'name': name,
    'constructionCost': cost,
    'setupCost': setup,
    'equipmentMinutes': occupation / Duration.millisecondsPerMinute,
    'additionalPlots': game.state.districts.length - startingPlots,
    'netPerMinute': netDelta,
    'efficiencyDelta': {
      for (final key in before.keys) key: after[key]! - before[key]!,
    },
    'foregoneFactoryMarginEstimate': foregoneMargin,
    if (netDelta > 0) 'directCostPaybackMinutes': cost / netDelta,
    if (netDelta > 0)
      'costAndForegoneMarginPaybackMinutes': (cost + foregoneMargin) / netDelta,
    'quotes': quotes,
  };
}

List<Map<String, String>> _dominated(List<Map<String, Object>> candidates) {
  bool dominates(Map<String, Object> a, Map<String, Object> b) {
    final ae = a['efficiencyDelta']! as Map<String, int>;
    final be = b['efficiencyDelta']! as Map<String, int>;
    final comparisons = [
      for (final key in [
        'constructionCost',
        'equipmentMinutes',
        'additionalPlots',
      ])
        (b[key]! as num) - (a[key]! as num),
      (a['netPerMinute']! as num) - (b['netPerMinute']! as num),
      for (final key in ae.keys) ae[key]! - be[key]!,
    ];
    return comparisons.every((value) => value >= 0) &&
        comparisons.any((value) => value > 0);
  }

  return [
    for (final candidate in candidates)
      for (final alternative in candidates)
        if (dominates(alternative, candidate))
          {
            'candidate': candidate['name']! as String,
            'dominatedBy': alternative['name']! as String,
          },
  ];
}
