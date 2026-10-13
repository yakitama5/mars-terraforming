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
    expect(result.maxDecisionGapMinutes, lessThanOrEqualTo(25));
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
