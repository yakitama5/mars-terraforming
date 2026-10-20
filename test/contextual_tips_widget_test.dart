import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/contextual_tips.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/presentation/contextual_tips.dart';
import 'package:mars_terraforming/presentation/mission_dialogue.dart';

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
    expect(engine.state.research, contains('life_support'));
    expect(engine.state.currentPlanFor('lab'), isNull);
  });

  testWidgets('a narrow panel with larger text retains the full explanation', (
    tester,
  ) async {
    final engine = GameEngine(GameState.initial(DateTime.utc(2026, 1, 1)));
    engine.state.researchPointUnits = 0;
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
    expect(tester.widget<Text>(find.text(tip.detail)).maxLines, isNull);
    expect(
      find.byKey(const Key('toggle-contextual-tip-detail')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ordinary tips open a readable dialogue without taking an action',
    (tester) async {
      final engine = GameEngine(GameState.initial(DateTime.utc(2026, 1, 1)));
      engine.enqueue('life_support');
      final tip = evaluateContextualTips(engine.state).first;
      final before = jsonEncode(engine.state.toJson());
      var opened = 0;
      tester.view.physicalSize = const Size(568, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: SingleChildScrollView(
                child: SizedBox(
                  width: 220,
                  child: ContextualTipsPanel(
                    game: engine.state,
                    compact: true,
                    onOpen: (_) => opened++,
                    onDismiss: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text(tip.detail), findsNothing);
      await tester.tap(find.byKey(const Key('toggle-contextual-tip-detail')));
      await tester.pumpAndSettle();
      final dialogue = tester.widget<MissionDialogue>(
        find.byType(MissionDialogue),
      );
      expect(dialogue.text, tip.detail);
      expect(dialogue.title, tip.title);
      expect(
        tester
            .getSize(find.byKey(const Key('mission-dialogue-portrait')))
            .width,
        greaterThanOrEqualTo(120),
      );
      expect(
        find.byKey(const Key('open-contextual-tip-dialogue')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('close-contextual-tip-dialogue')).hitTestable(),
        findsOneWidget,
      );
      expect(opened, 0);
      expect(engine.state.research, contains('life_support'));
      expect(engine.state.currentPlanFor('lab'), isNull);
      await tester.tap(find.byKey(const Key('close-contextual-tip-dialogue')));
      await tester.pumpAndSettle();
      expect(find.byType(MissionDialogue), findsNothing);
      expect(find.text(tip.detail), findsNothing);
      expect(jsonEncode(engine.state.toJson()), before);
      await tester.tap(find.byKey(const Key('toggle-contextual-tip-detail')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-contextual-tip-dialogue')));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.byType(MissionDialogue), findsNothing);
      expect(jsonEncode(engine.state.toJson()), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a dialogue action closes both the explanation and its guide host',
    (tester) async {
      final engine = GameEngine(GameState.initial(DateTime.utc(2026, 1, 1)));
      engine.enqueue('life_support');
      ContextualTip? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (guideContext) => AlertDialog(
                    content: ContextualTipsPanel(
                      game: engine.state,
                      onOpen: (tip) {
                        opened = tip;
                        Navigator.of(guideContext).pop();
                      },
                      onDismiss: (_) {},
                    ),
                  ),
                ),
                child: const Text('ガイド'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ガイド'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('toggle-contextual-tip-detail')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-contextual-tip-dialogue')));
      await tester.pumpAndSettle();
      expect(opened?.destination, ContextualTipDestination.city);
      expect(opened?.cityId, 'earth_delta');
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('ガイド').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
