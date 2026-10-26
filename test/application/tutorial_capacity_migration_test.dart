import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 26);
  Map<String, dynamic> legacy({bool paid = false}) {
    final state = GameState.initial(epoch)
      ..openingSeen = true
      ..firstRunTutorial = FirstRunTutorialStep.startResearch
      ..researchPointUnits = 0
      ..nextPlanId = 2;
    final plan = PlannedTask(id: 'plan-1', taskId: 'life_support');
    if (paid) {
      plan.status = 'running';
      plan.iterationDurationMs = 120000;
      plan.remainingMs = 90000;
    }
    state.plans.add(plan);
    return state.toJson()..['contentVersion'] = 'district-10';
  }

  test('only an old protected unpaid research reservation recovers starter RP once', () {
    final old = legacy();
    final state = GameState.fromJson(old);
    final budget =
        GameContent.researchPointCost('life_support') *
        GameState.researchPointScale;
    expect(state.researchPointUnits, budget);
    expect(state.plans.single.requiresManualStart, isTrue);
    final game = GameEngine(state);
    expect(game.startPlan(state.plans.single.id), isNull);
    expect(state.researchPointUnits, 0);
    expect(state.firstRunTutorial, FirstRunTutorialStep.researchStarted);
    expect(state.research, {'life_support'});
    expect(GameState.fromJson(state.toJson()).researchPointUnits, 0);
  });

  test('current, ordinary and already-paid worlds receive no starter RP compensation', () {
    final current = legacy()..['contentVersion'] = GameContent.version;
    expect(GameState.fromJson(current).researchPointUnits, 0);
    final ordinary = legacy()
      ..['firstRunTutorial'] = FirstRunTutorialStep.completed.name;
    expect(GameState.fromJson(ordinary).researchPointUnits, 0);
    expect(GameState.fromJson(legacy(paid: true)).researchPointUnits, 0);
  });

  test(
    'protected migration never lowers a larger bank or changes paid balances',
    () {
      final old = legacy()
        ..['researchPointUnits'] = 1000 * GameState.researchPointScale;
      final state = GameState.fromJson(old);
      expect(state.researchPointUnits, old['researchPointUnits']);
      expect(state.moneyUnits, old['moneyUnits']);
      expect(state.claimedRewards, isEmpty);
    },
  );
}
