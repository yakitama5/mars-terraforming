import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/presentation/research_tree.dart';

void main() {
  testWidgets(
    'filter keeps prerequisites and external selection follows its route',
    (tester) async {
      tester.view.physicalSize = const Size(700, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = GameEngine(GameState.initial(DateTime.utc(2026, 10, 16)));
      var selected = 'life_support';
      Future<void> draw() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResearchTree(
              game: engine.state,
              selectedId: selected,
              onSelected: (_) {},
              requirementReasons: engine.researchRequirementReasons,
            ),
          ),
        ),
      );
      await draw();
      await tester.tap(find.byKey(const Key('research-filter-輸送')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('research-node-electric_tugs')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('research-node-urban_planning')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('research-node-oxygen_pilot')), findsNothing);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final cameraBefore = viewer.transformationController!.value.clone();
      // A visible cross-discipline prerequisite is still part of this route.
      selected = 'urban_planning';
      await draw();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('research-node-electric_tugs')),
        findsOneWidget,
      );
      expect(viewer.transformationController!.value, cameraBefore);
      selected = 'oxygen_pilot';
      await draw();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('research-node-oxygen_pilot')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('research-node-life_support')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('research-node-electric_tugs')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'future previews remain readable with large text on a small landscape screen',
    (tester) async {
      tester.view.physicalSize = const Size(700, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = GameEngine(GameState.initial(DateTime.utc(2026, 10, 16)));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(
            body: ResearchTree(
              game: engine.state,
              selectedId: 'life_support',
              onSelected: (_) {},
              requirementReasons: engine.researchRequirementReasons,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('research-futures')));
      await tester.pumpAndSettle();
      expect(find.text('居住編のその先'), findsOneWidget);
      expect(find.textContaining('到達判定・報酬はまだありません'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('research-future-harbor_of_two_worlds')),
      );
      await tester.tap(
        find.byKey(const Key('research-future-harbor_of_two_worlds')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('関連する研究：青い光の電気推進'), findsOneWidget);
      await tester.tap(find.text('研究に戻る'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
