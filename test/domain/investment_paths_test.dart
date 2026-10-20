import 'package:flutter_test/flutter_test.dart';

import '../../tools/verify_investments.dart';
import '../../tools/verify_progression.dart';

void main() {
  test('the first hour funds multiple placement decisions and Mars settlement without grants', () {
    final result = runOnboardingVerification();
    final summary = result.toJson();
    expect(result.state.simulatedMs, const Duration(hours: 1).inMilliseconds);
    expect(result.state.districts.length, greaterThanOrEqualTo(5));
    expect(
      result.state.research,
      containsAll(['life_support', 'urban_planning']),
    );
    expect(result.state.marsResidents, 24);
    expect(result.state.marsHabitats, 1);
    expect(result.state.money, greaterThanOrEqualTo(0));
    expect(summary['distinctDecisionTimes'], greaterThanOrEqualTo(8));
    expect(result.maxDecisionGapMinutes, lessThanOrEqualTo(14));
    expect(result.maxDecisionGapBeforeSettlementMinutes, lessThanOrEqualTo(10));
    final firstHome = result.events.singleWhere(
      (event) => event['step'] == 'First coastal housing',
    );
    expect(firstHome['elapsedMinutes'], lessThanOrEqualTo(8));
    final firstHabitat = result.events.singleWhere(
      (event) => event['step'] == 'First Mars settlement',
    );
    expect(firstHabitat['elapsedMinutes'], lessThan(60));
    final automation = result.state.plans.singleWhere(
      (plan) => plan.taskId == 'automated_fabrication',
    );
    expect(automation.isFinished, isFalse);
    expect(summary['measurement'], contains('not measured active play time'));
  });

  test(
    'prioritizing cargo uses other equipment during campus construction',
    () {
      final baseline = runOnboardingVerification(parallelCargo: false);
      final parallel = runOnboardingVerification();
      double time(OnboardingVerification route, String step) =>
          route.events.singleWhere(
                (event) => event['step'] == step,
              )['elapsedMinutes']!
              as double;
      expect(
        time(parallel, 'First Mars delivery'),
        lessThan(time(baseline, 'First Mars delivery')),
      );
      expect(
        time(parallel, 'First Mars settlement'),
        lessThan(time(baseline, 'First Mars settlement')),
      );
      expect(
        time(parallel, 'Campus adjoining both houses'),
        greaterThan(time(baseline, 'Campus adjoining both houses')),
      );
      expect(
        parallel.maxDecisionGapBeforeSettlementMinutes,
        lessThan(baseline.maxDecisionGapBeforeSettlementMinutes),
      );
    },
  );

  test('housing-first and industry-first offer different benefits in the first hour', () {
    final report = runEarlyInvestmentVerification();
    expect(report['status'], 'passed');
    final tradeoffs = report['tradeoffs']! as Map<String, Object>;
    expect(
      tradeoffs['housingFirstHousingCompletedMinutes'],
      lessThan(tradeoffs['industryFirstHousingCompletedMinutes']! as num),
    );
    expect(
      tradeoffs['industryFirstIndustryCompletedMinutes'],
      lessThan(tradeoffs['housingFirstIndustryCompletedMinutes']! as num),
    );
    expect(
      tradeoffs['housingFirstCashAt60Minutes'],
      greaterThan(tradeoffs['industryFirstCashAt60Minutes']! as num),
    );
  });

  test('both partnership strategies keep meaningful first-hour decisions within six minutes', () {
    for (final choice in ['funding', 'technology']) {
      final route = runParallelStrategyVerification(partnershipChoice: choice);
      expect(route.state.simulatedMs, const Duration(hours: 1).inMilliseconds);
      expect(route.state.money, greaterThanOrEqualTo(0));
      expect(route.maxDecisionGapMinutes, lessThanOrEqualTo(6));
      expect(
        route.state.research,
        containsAll([
          'life_support',
          'urban_planning',
          'deployable_solar_arrays',
          'local_resources',
          'orbital_gardens',
          'autonomous_rovers',
        ]),
      );
      expect(route.state.specialistCount, 18);
      expect(route.state.researchers, 10);
      expect(route.state.industrialWorkers, 8);
      expect(route.state.districtAt('earth_delta', 0)?.level, 2);
      expect(route.state.marsResidents, greaterThanOrEqualTo(24));
      expect(
        route.state.plans.where(
          (plan) =>
              plan.taskId == 'train_specialists' && plan.status == 'completed',
        ),
        hasLength(3),
      );
      expect(
        route.state.plans.where(
          (plan) => plan.taskId == 'district_mars_habitat',
        ),
        hasLength(2),
      );
      final parallel = route.events.where(
        (event) => event.containsKey('parallelWork'),
      );
      expect(parallel, isNotEmpty);
      expect(
        parallel.any(
          (event) => (event['parallelWork']! as Map).containsKey('factory'),
        ),
        isTrue,
      );
      expect(
        parallel.any(
          (event) => (event['parallelWork']! as Map).containsKey('mars'),
        ),
        isTrue,
      );
      expect(
        route.events
            .where((event) => event['kind'] == 'completion')
            .any((event) => '${event['step']}'.contains('contract')),
        isFalse,
      );
    }
  });

  test('cash and technology choices retain different benefits without disguising unfinished work', () {
    final funding = runParallelStrategyVerification();
    final technology = runParallelStrategyVerification(
      partnershipChoice: 'technology',
    );
    expect(funding.state.money, greaterThan(technology.state.money));
    expect(funding.state.districtAt('earth_delta', 8)?.districtId, 'industry');
    expect(
      technology.state.districtAt('earth_delta', 8)?.districtId,
      'industry',
    );
    for (final route in [funding, technology]) {
      final advancedResearch = route.state.plans.singleWhere(
        (plan) => plan.taskId == 'automated_fabrication',
      );
      expect(advancedResearch.isFinished, isFalse);
      expect(
        route.state.researchWaitMs('automated_fabrication'),
        greaterThan(0),
      );
      expect(
        route.state.plans.where(
          (plan) => plan.taskId == 'district_mars_habitat' && !plan.isFinished,
        ),
        hasLength(1),
      );
    }
    expect(
      technology.state.researchBonusPercent,
      greaterThan(funding.state.researchBonusPercent),
    );
    expect(
      technology.state.launchBonusPercent,
      greaterThan(funding.state.launchBonusPercent),
    );
    expect(funding.state.partnershipChoices.values, everyElement('funding'));
    expect(
      technology.state.partnershipChoices.values,
      everyElement('technology'),
    );
    expect(funding.state.partnershipChoices, hasLength(3));
    expect(technology.state.partnershipChoices, hasLength(3));
  });

  test('decision opportunities and actual development completions are reported separately', () {
    final report = runParallelStrategyComparison();
    final routes = report['routes']! as Map<String, Object>;
    final technology = routes['technology']! as Map<String, Object>;
    expect(
      technology['maxMeaningfulCompletionGapMinutes'],
      greaterThan(technology['maxDecisionGapMinutes']! as num),
    );
    expect(technology['unfinishedDevelopment'], isNotEmpty);
    expect(report['measurement'], contains('no state is injected'));
    expect(
      report['measurement'],
      contains('do not isolate partnership effects'),
    );
  });

  final report = runInvestmentVerification();
  final scenarios = (report['scenarios']! as List<Map<String, Object>>);
  Map<String, Object> scenario(String name) =>
      scenarios.singleWhere((item) => item['scenario'] == name);
  Map<String, Object> candidate(String size, String collection, String name) =>
      (scenario(size)[collection]! as List<Map<String, Object>>).singleWhere(
        (item) => item['name'] == name,
      );

  test('clustered upgrades trade some initial cash for equipment time and adjacency', () {
    final upgrade = candidate(
      'growing',
      'singleInvestments',
      'clustered_housing_upgrade',
    );
    final infill = candidate(
      'growing',
      'singleInvestments',
      'current_city_housing',
    );
    expect(
      upgrade['constructionCost'],
      greaterThan(infill['constructionCost']! as num),
    );
    expect(
      upgrade['equipmentMinutes'],
      lessThan(infill['equipmentMinutes']! as num),
    );
    expect(
      upgrade['netPerMinute'],
      greaterThan(infill['netPerMinute']! as num),
    );
    expect(upgrade['additionalPlots'], 0);
    final isolated = candidate(
      'growing',
      'singleInvestments',
      'isolated_housing_upgrade',
    );
    expect(upgrade['constructionCost'], isolated['constructionCost']);
    expect(
      upgrade['netPerMinute'],
      greaterThan(isolated['netPerMinute']! as num),
    );
  });

  test(
    'a new science city amortizes its opening burden across three real builds',
    () {
      final oldSingle = candidate(
        'growing',
        'singleInvestments',
        'current_city_ridge_campus',
      );
      final newSingle = candidate(
        'growing',
        'singleInvestments',
        'new_city_ridge_campus',
      );
      expect(
        newSingle['constructionCost'],
        greaterThan(oldSingle['constructionCost']! as num),
      );
      expect(
        newSingle['equipmentMinutes'],
        greaterThan(oldSingle['equipmentMinutes']! as num),
      );
      final oldPackage = candidate(
        'growing',
        'threeInvestmentPackages',
        'three_existing_city_ridge_campuses',
      );
      final newPackage = candidate(
        'growing',
        'threeInvestmentPackages',
        'three_new_city_ridge_campuses',
      );
      expect(
        newPackage['constructionCost'],
        lessThan(oldPackage['constructionCost']! as num),
      );
      expect(
        newPackage['equipmentMinutes'],
        lessThan(oldPackage['equipmentMinutes']! as num),
      );
      expect(newPackage['efficiencyDelta'], oldPackage['efficiencyDelta']);
      expect(newPackage['setupCost'], newSingle['setupCost']);
      final quotes = newPackage['quotes']! as List<Map<String, Object>>;
      expect(quotes.skip(1).every((quote) => quote['setupCost'] == 0), isTrue);
    },
  );

  test(
    'a mature city retains adjacency value against a cheaper new urban package',
    () {
      final oldPackage = candidate(
        'dense',
        'threeInvestmentPackages',
        'three_existing_city_ridge_campuses',
      );
      final newPackage = candidate(
        'dense',
        'threeInvestmentPackages',
        'three_new_city_ridge_campuses',
      );
      expect(
        newPackage['constructionCost'],
        lessThan(oldPackage['constructionCost']! as num),
      );
      expect(
        newPackage['equipmentMinutes'],
        lessThan(oldPackage['equipmentMinutes']! as num),
      );
      expect(
        oldPackage['netPerMinute'],
        greaterThan(newPackage['netPerMinute']! as num),
      );
      final oldEfficiency = oldPackage['efficiencyDelta']! as Map<String, int>;
      final newEfficiency = newPackage['efficiencyDelta']! as Map<String, int>;
      expect(
        oldEfficiency['research'],
        greaterThan(newEfficiency['research']!),
      );
      expect(scenario('dense')['strictlyDominatedPackages'], isEmpty);
      expect(report['measurement'], contains('Counterfactual fixtures inject'));
    },
  );
}
