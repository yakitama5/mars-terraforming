import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/contextual_tips.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/presentation/contextual_tips.dart';

void main() {
  testWidgets('opens the suggested destination and dismisses only that tip', (
    tester,
  ) async {
    final engine = GameEngine(GameState.initial(DateTime.utc(2026, 1, 1)));
    engine.enqueue('life_support');
    ContextualTip? opened;
    final dismissed = <String>{};
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: ContextualTipsPanel(
              game: engine.state,
              onOpen: (tip) => opened = tip,
              onDismiss: (id) => setState(() => dismissed.add(id)),
              dismissedIds: dismissed,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-contextual-tip')));
    expect(opened?.destination, ContextualTipDestination.city);
    expect(opened?.cityId, 'earth_delta');
    await tester.tap(find.byKey(const Key('dismiss-contextual-tip')));
    await tester.pump();
    expect(dismissed, {'parallel-city'});
    expect(find.byKey(const Key('contextual-tips-panel')), findsNothing);
    expect(engine.state.currentPlanFor('lab'), isNotNull);
  });

  testWidgets('a narrow panel with larger text retains the full explanation', (
    tester,
  ) async {
    final engine = GameEngine(GameState.initial(DateTime.utc(2026, 1, 1)));
    engine.enqueue('life_support');
    engine.setFacilityEnabled('lab', false);
    final tip = evaluateContextualTips(engine.state).first;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: SingleChildScrollView(
              child: SizedBox(
                width: 220,
                child: ContextualTipsPanel(
                  game: engine.state,
                  compact: true,
                  onOpen: (_) {},
                  onDismiss: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text(tip.detail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
