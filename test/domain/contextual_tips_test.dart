import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/contextual_tips.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

void main() {
  GameEngine fresh() => GameEngine(GameState.initial(DateTime.utc(2026, 1, 1)));
  List<ContextualTip> tips(GameEngine engine) =>
      evaluateContextualTips(engine.state, limit: 20);

  test('fresh game adds no tips over the tutorial', () {
    expect(tips(fresh()), isEmpty);
  });

  test('paused work outranks optional parallel-development advice', () {
    final engine = fresh();
    engine.enqueue('life_support');
    engine.enqueue('launch_contract');
    engine.setFacilityEnabled('launch', false);
    final result = tips(engine);
    expect(result.first.id, 'paused:launch:plan-2');
    expect(result.first.facilityId, 'launch');
    expect(result.any((tip) => tip.id == 'parallel-city'), isTrue);
    engine.setFacilityEnabled('launch', true);
    expect(
      tips(engine).any((tip) => tip.id.startsWith('paused:launch:')),
      isFalse,
    );
  });

  test('paused empty facility does not demand attention', () {
    final engine = fresh();
    engine.setFacilityEnabled('launch', false);
    expect(tips(engine), isEmpty);
  });

  test('unlimited warning follows actual future queue order', () {
    final engine = fresh();
    engine.state.research.add('life_support');
    engine.enqueue('factory_contract', repeats: null);
    engine.enqueue('habitat_kit');
    final contract = engine.state.plans.first;
    final kit = engine.state.plans.last;
    expect(tips(engine).first.id, 'unlimited:${contract.id}');
    engine.reorderPlan(kit.id, relativeToPlanId: contract.id, before: true);
    expect(engine.state.currentPlanFor('factory'), contract);
    expect(tips(engine).any((tip) => tip.id.startsWith('unlimited:')), isFalse);
  });

  test('finite repetition and a lone unlimited plan are not a blockage', () {
    for (final repeats in <int?>[3, null]) {
      final engine = fresh();
      engine.enqueue('factory_contract', repeats: repeats);
      if (repeats != null) engine.enqueue('habitat_kit');
      expect(
        tips(engine).any((tip) => tip.id.startsWith('unlimited:')),
        isFalse,
      );
    }
  });

  test('staff blockage directs to allocation and uses resolved reason', () {
    final engine = fresh();
    engine.assignResearchers(0);
    engine.enqueue('life_support');
    final tip = tips(engine).first;
    expect(tip.destination, ContextualTipDestination.agency);
    expect(tip.id, startsWith('staff:'));
    expect(tip.agencySection, ContextualTipAgencySection.staffing);
    expect(tip.detail, contains(engine.state.plans.first.stopReason));
  });

  test('resource blockage uses the engine reason and clears when supplied', () {
    final engine = fresh();
    engine.enqueue('mars_delivery');
    final tip = tips(engine).first;
    expect(tip.id, startsWith('resource:'));
    expect(tip.operationsSection, ContextualTipOperationsSection.production);
    expect(tip.detail, contains(engine.state.plans.first.stopReason));
    engine.state.earthKits = 1;
    engine.advanceBy(Duration.zero);
    expect(tips(engine).any((tip) => tip.id.startsWith('resource:')), isFalse);
  });

  test('a dismissal is scoped to the exact queued plan', () {
    final engine = fresh();
    engine.enqueue('mars_delivery');
    final dismissed = tips(engine).first.id;
    expect(
      evaluateContextualTips(engine.state, dismissedIds: {dismissed}),
      isEmpty,
    );
    engine.cancelQueued(engine.state.plans.first.id);
    engine.enqueue('mars_delivery');
    expect(
      evaluateContextualTips(engine.state, dismissedIds: {dismissed}).first.id,
      isNot(dismissed),
    );
  });

  test('reads never mutate progress, money, queue, or save generation', () {
    final engine = fresh();
    engine.enqueue('life_support');
    final before = engine.state.toJson();
    for (var i = 0; i < 10; i++) {
      tips(engine);
    }
    expect(engine.state.toJson(), before);
  });

  test('ordinary seconds do not rotate suggestions or their text', () {
    final engine = fresh();
    engine.enqueue('life_support');
    final before = tips(engine).first;
    engine.advanceBy(const Duration(seconds: 1));
    final after = tips(engine).first;
    expect(after.id, before.id);
    expect(after.title, before.title);
    expect(after.detail, before.detail);
  });

  test('limit and dismissed tips are applied after priority selection', () {
    final engine = fresh();
    engine.enqueue('life_support');
    engine.enqueue('launch_contract');
    engine.setFacilityEnabled('launch', false);
    expect(evaluateContextualTips(engine.state, limit: 0), isEmpty);
    expect(evaluateContextualTips(engine.state, limit: 1), hasLength(1));
    expect(
      evaluateContextualTips(
        engine.state,
        dismissedIds: {'paused:launch:plan-2'},
        limit: 1,
      ).first.id,
      'parallel-city',
    );
  });

  test('zero industrial staff directs idle factory to allocation', () {
    final engine = fresh();
    engine.assignResearchers(engine.state.specialistCount);
    engine.enqueue('life_support');
    final tip = tips(engine).first;
    expect(tip.id, 'unassigned:factory');
    expect(tip.destination, ContextualTipDestination.agency);
    expect(tips(engine).any((tip) => tip.id == 'parallel-city'), isFalse);
  });

  test('all completed research suppresses the empty research suggestion', () {
    final engine = fresh();
    engine.state.research.addAll(
      GameContent.tasks.values
          .where((task) => task.unique)
          .map((task) => task.id),
    );
    engine.enqueue('factory_contract');
    expect(tips(engine).any((tip) => tip.id == 'parallel-research'), isFalse);
  });

  test('resolved warnings are forgotten and reappear on recurrence', () {
    final engine = fresh();
    engine.enqueue('life_support');
    engine.setFacilityEnabled('lab', false);
    final id = tips(engine).first.id;
    var retained = retainedContextualTipDismissals(engine.state, {id});
    expect(retained, {id});
    expect(
      evaluateContextualTips(engine.state, dismissedIds: retained),
      isEmpty,
    );
    engine.setFacilityEnabled('lab', true);
    retained = retainedContextualTipDismissals(engine.state, retained);
    expect(retained, isEmpty);
    engine.setFacilityEnabled('lab', false);
    expect(
      evaluateContextualTips(engine.state, dismissedIds: retained).first.id,
      id,
    );
  });

  test('missing Mars cargo directs to transport instead of manufacturing', () {
    final engine = fresh();
    engine.state.achievements.add('first_landing');
    engine.chooseHabitat('dome');
    engine.enqueue('build_habitat');
    final tip = tips(engine).first;
    expect(tip.id, startsWith('resource:'));
    expect(tip.destination, ContextualTipDestination.operations);
    expect(tip.operationsSection, ContextualTipOperationsSection.transport);
  });

  test('locked manufacturing directs to the missing research', () {
    final engine = fresh();
    engine.enqueue('habitat_kit');
    final tip = tips(engine).first;
    expect(tip.destination, ContextualTipDestination.research);
    expect(tip.taskId, 'life_support');
  });

  test('before landing the branch tip explains the required delivery', () {
    final engine = fresh();
    engine.enqueue('build_habitat');
    final tip = tips(engine).first;
    expect(tip.id, startsWith('branch:'));
    expect(tip.operationsSection, ContextualTipOperationsSection.transport);
    expect(tip.detail, contains('輸送を完了してください'));
    expect(tip.detail, isNot(contains('方針を決めると')));
  });

  test('after landing the habitat choice opens the transport section', () {
    final engine = fresh();
    engine.state.achievements.add('first_landing');
    final tip = tips(engine).first;
    expect(tip.id, 'habitat-choice');
    expect(tip.operationsSection, ContextualTipOperationsSection.transport);
  });

  test('available partnerships explicitly open the partnerships section', () {
    final engine = fresh();
    engine.state.research.add('urban_planning');
    engine.state.districts['earth_delta:0'] = const DistrictState(
      cityId: 'earth_delta',
      plotIndex: 0,
      districtId: 'housing',
    );
    final tip = tips(engine).first;
    expect(tip.id, startsWith('partnership:'));
    expect(tip.destination, ContextualTipDestination.agency);
    expect(tip.agencySection, ContextualTipAgencySection.partnerships);
  });

  test(
    'parallel research opens an unfinished research instead of a known one',
    () {
      final engine = fresh();
      engine.state.research.add('life_support');
      engine.enqueue('factory_contract');
      final tip = tips(engine)
          .firstWhere((tip) => tip.id == 'parallel-research');
      expect(tip.taskId, isNotNull);
      expect(engine.state.research, isNot(contains(tip.taskId)));
    },
  );

  test('training at the staff cap needs cancellation rather than waiting', () {
    final engine = fresh();
    engine.state.specialistCount = GameContent.maxSpecialists;
    engine.enqueue('train_specialists');
    engine.enqueue('life_support');
    final tip = tips(engine).first;
    expect(tip.id, startsWith('training-limit:'));
    expect(tip.detail, contains('育成の予約を取り消す'));
    expect(tip.detail, isNot(contains('自動で始まります')));
    expect(tip.operationsSection, ContextualTipOperationsSection.queues);
    engine.cancelQueued(engine.state.plans.first.id);
    expect(engine.state.currentPlanFor('lab')?.taskId, 'life_support');
  });

  test(
    'dismissed habitat choice is not repeated as the same branch warning',
    () {
      final engine = fresh();
      engine.state.achievements.add('first_landing');
      engine.enqueue('build_habitat');
      expect(tips(engine).first.id, 'habitat-choice');
      expect(
        evaluateContextualTips(engine.state, dismissedIds: {'habitat-choice'}),
        isEmpty,
      );
    },
  );

  test('funding wait clears only after funds actually start the work', () {
    final engine = fresh();
    engine.state.money = 100;
    engine.setFacilityEnabled('factory', false);
    engine.enqueue('life_support');
    final id = tips(engine).first.id;
    expect(id, startsWith('budget:'));
    engine.advanceBy(const Duration(minutes: 10));
    expect(tips(engine).first.id, id);
    engine.advanceBy(const Duration(minutes: 4));
    expect(engine.state.currentPlanFor('lab')?.taskId, 'life_support');
    expect(tips(engine).any((tip) => tip.id == id), isFalse);
  });

  test('a funding wait in deficit does not claim waiting will restart it', () {
    final engine = fresh();
    engine.state.money = 100;
    engine.enqueue('life_support');
    expect(engine.state.netPerMinute, lessThan(0));
    engine.advanceBy(const Duration(minutes: 1));
    final tip = tips(engine).first;
    expect(tip.id, startsWith('budget:'));
    expect(tip.detail, isNot(contains('自動で始まります')));
    expect(engine.state.currentPlanFor('lab'), isNull);
  });

  test('waiting for cargo does not stop an independent research', () {
    final engine = fresh();
    engine.enqueue('mars_delivery');
    engine.enqueue('life_support');
    final id = tips(engine).first.id;
    expect(id, startsWith('resource:'));
    engine.advanceBy(const Duration(minutes: 2));
    expect(engine.state.research, contains('life_support'));
    expect(tips(engine).first.id, id);
    expect(engine.state.currentPlanFor('launch'), isNull);
  });

  test('dismissals remain bounded as completed and unknown IDs accumulate', () {
    final engine = fresh();
    final dismissed = <String>{'parallel-city', 'parallel-research'};
    for (var index = 0; index < 100; index++) {
      engine.enqueue('mars_delivery');
      dismissed.add(tips(engine).first.id);
      engine.cancelQueued(engine.state.plans.last.id);
      dismissed.add('unknown:$index');
    }
    engine.enqueue('mars_delivery');
    final active = tips(engine).first.id;
    dismissed.add(active);
    final before = engine.state.toJson();
    final retained = retainedContextualTipDismissals(engine.state, dismissed);
    expect(retained, {'parallel-city', 'parallel-research', active});
    expect(engine.state.toJson(), before);
    engine.cancelQueued(engine.state.plans.last.id);
    expect(retainedContextualTipDismissals(engine.state, retained), {
      'parallel-city',
      'parallel-research',
    });
  });
}
