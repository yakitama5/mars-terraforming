import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/contextual_tips.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/onboarding_guide.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 20);

  test(
    'guide research destinations never reveal undiscovered technologies',
    () {
      final state = GameState.initial(epoch);
      final before = jsonEncode(state.toJson());
      final guide = OnboardingGuide.fromState(state);
      for (final step in guide.steps) {
        if (step.destination == OnboardingDestination.research) {
          expect(state.isResearchDiscovered(step.target), isTrue);
        }
      }
      final text = guide.steps
          .map(
            (step) =>
                '${step.title}\n${step.story}\n${step.lesson}\n${step.reason}',
          )
          .join('\n');
      for (final id in [
        'urban_planning',
        'surface_fission',
        'electric_tugs',
        'automated_fabrication',
      ]) {
        if (!state.isResearchDiscovered(id)) {
          expect(text, isNot(contains(GameContent.tasks[id]!.name)));
        }
      }
      expect(text, contains('共通RP'));
      expect(jsonEncode(state.toJson()), before);
    },
  );

  test(
    'second-research lesson accepts another field without forcing a route',
    () {
      final state = GameState.initial(epoch)
        ..research.addAll(['life_support', 'orbital_gardens']);
      final guide = OnboardingGuide.fromState(state);
      final step = guide.steps.firstWhere(
        (step) => step.id == 'urban_planning',
      );
      expect(step.isCompleted, isTrue);
      expect(state.research, isNot(contains('urban_planning')));
      expect(state.isResearchDiscovered(step.target), isTrue);
    },
  );

  test('parallel research tips target only known unfinished technologies', () {
    final engine = GameEngine(GameState.initial(epoch));
    engine.state.research.add('life_support');
    expect(engine.enqueue('factory_contract'), isNull);
    final before = jsonEncode(engine.state.toJson());
    final tips = evaluateContextualTips(engine.state, limit: 20);
    final research = tips.where(
      (tip) => tip.destination == ContextualTipDestination.research,
    );
    expect(research, isNotEmpty);
    for (final tip in research) {
      expect(engine.state.isResearchDiscovered(tip.taskId!), isTrue);
      expect(engine.state.research, isNot(contains(tip.taskId)));
    }
    expect(jsonEncode(engine.state.toJson()), before);
  });

  test(
    'initial guide does not add an unsolicited passive-research warning',
    () {
      final state = GameState.initial(epoch);
      expect(evaluateContextualTips(state), isEmpty);
    },
  );
}
