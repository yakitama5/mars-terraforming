import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/presentation/research_tree.dart';

void main() {
  GameEngine initial() =>
      GameEngine(GameState.initial(DateTime.utc(2026, 10, 20)));

  Widget tree(
    GameEngine engine, {
    String selected = 'life_support',
    bool reducedMotion = false,
    double scale = 1,
    Size size = const Size(700, 360),
  }) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reducedMotion,
        textScaler: TextScaler.linear(scale),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox.fromSize(
          size: size,
          child: ResearchTree(
            game: engine.state,
            selectedId: selected,
            onSelected: (_) {},
            requirementReasons: engine.researchRequirementReasons,
          ),
        ),
      ),
    ),
  );

  void fund(GameEngine engine, String id) {
    engine.state.researchPointUnits =
        GameContent.researchPointCost(id) * GameState.researchPointScale;
  }

  testWidgets(
    'unseen names, branches and size never enter canvas or semantics',
    (tester) async {
      final engine = initial();
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(tree(engine));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('research-node-life_support')),
          findsOneWidget,
        );
        final hidden = ResearchCatalog.byCatalogId('M12')!;
        expect(find.byKey(Key('research-node-${hidden.id}')), findsNothing);
        expect(
          find.byKey(Key('research-semantics-${hidden.id}')),
          findsNothing,
        );
        expect(find.text(hidden.name), findsNothing);
        expect(find.text('段階 1'), findsNothing);
        expect(find.textContaining('/99'), findsNothing);
        expect(find.textContaining('/98'), findsNothing);
        final spoken = tester
            .binding
            .renderViews
            .first
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!
            .toStringDeep();
        expect(spoken, isNot(contains(hidden.name)));
        final before =
            tester
                    .widget<InteractiveViewer>(
                      find.byKey(const Key('research-tree-canvas')),
                    )
                    .child
                as SizedBox;
        await tester.tap(find.byKey(const Key('research-fit')));
        await tester.pumpAndSettle();
        final after =
            tester
                    .widget<InteractiveViewer>(
                      find.byKey(const Key('research-tree-canvas')),
                    )
                    .child
                as SizedBox;
        expect(
          Size(before.width!, before.height!),
          Size(after.width!, after.height!),
        );
        expect(before.width, lessThan(500));
        expect(find.byKey(Key('research-node-${hidden.id}')), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('unlock grows new discoveries with a finite animation', (
    tester,
  ) async {
    final engine = initial();
    const selected = 'orbital_gardens';
    final child = ResearchCatalog.byCatalogId('B02')!;
    await tester.pumpWidget(tree(engine, selected: selected));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('research-node-${child.id}')), findsNothing);
    fund(engine, selected);
    expect(engine.unlockResearch(selected), isNull);
    await tester.pumpWidget(tree(engine, selected: selected));
    expect(find.byKey(Key('research-node-${child.id}')), findsOneWidget);
    final entrance = find
        .ancestor(
          of: find.byKey(Key('research-node-${child.id}')),
          matching: find.byType(Opacity),
        )
        .first;
    expect(tester.widget<Opacity>(entrance).opacity, 0);
    await tester.pump(const Duration(milliseconds: 650));
    expect(tester.widget<Opacity>(entrance).opacity, greaterThan(0));
    expect(tester.widget<Opacity>(entrance).opacity, lessThan(1));
    expect(find.text('水耕栽培を解放'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(entrance).opacity, 1);
    expect(find.text('水耕栽培を解放'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    // Leaving the screen during the next burst must dispose both tickers.
    fund(engine, child.id);
    expect(engine.unlockResearch(child.id), isNull);
    await tester.pumpWidget(tree(engine, selected: selected));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'restored knowledge does not replay unlocks; reduced motion settles',
    (tester) async {
      final engine = initial();
      engine.state.research.add('orbital_gardens');
      final child = ResearchCatalog.byCatalogId('B02')!;
      await tester.pumpWidget(
        tree(engine, selected: 'orbital_gardens', reducedMotion: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('水耕栽培を解放'), findsNothing);
      final entrance = find
          .ancestor(
            of: find.byKey(Key('research-node-${child.id}')),
            matching: find.byType(Opacity),
          )
          .first;
      expect(tester.widget<Opacity>(entrance).opacity, 1);
      fund(engine, child.id);
      expect(engine.unlockResearch(child.id), isNull);
      await tester.pumpWidget(
        tree(engine, selected: 'orbital_gardens', reducedMotion: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('${child.name}を解放'), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('all field art works in a narrow large-text landscape panel', (
    tester,
  ) async {
    final engine = initial();
    await tester.pumpWidget(
      tree(engine, size: const Size(320, 310), scale: 1.4),
    );
    await tester.pumpAndSettle();
    for (final field in ResearchField.values) {
      final chip = find.byKey(Key('research-filter-${field.name}'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('research-background-${field.name}')),
        findsOneWidget,
      );
      expect(find.text(field.label), findsWidgets);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byKey(const Key('research-futures')));
    await tester.pumpAndSettle();
    expect(find.text('いまの知見から描く未来'), findsOneWidget);
    expect(
      find.byKey(const Key('research-future-harbor_of_two_worlds')),
      findsNothing,
    );
    expect(find.textContaining('まだ見ぬ未来は'), findsOneWidget);
    await tester.tap(find.text('研究に戻る'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
