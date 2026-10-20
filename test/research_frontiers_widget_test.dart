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
    expect(
      tester
          .widget<InteractiveViewer>(
            find.byKey(const Key('research-tree-canvas')),
          )
          .transformationController!
          .value
          .storage[0],
      greaterThanOrEqualTo(.85),
      reason: 'new sibling branches must not shrink the cards automatically',
    );
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

  testWidgets('narrow tree pans right into a child without fitting everything', (
    tester,
  ) async {
    final engine = initial();
    engine.state.research.add('orbital_gardens');
    await tester.pumpWidget(
      tree(engine, selected: 'orbital_gardens', size: const Size(320, 310)),
    );
    await tester.pumpAndSettle();
    final canvas = find.byKey(const Key('research-tree-canvas'));
    final child = find.byKey(const Key('research-node-regolith_substrate'));
    final parent = find.byKey(const Key('research-node-orbital_gardens'));
    expect(parent.hitTestable(), findsOneWidget);
    expect(child.hitTestable(), findsNothing);
    expect(
      tester.getCenter(child).dx,
      greaterThan(tester.getRect(canvas).right),
    );
    final gesture = await tester.startGesture(tester.getCenter(canvas));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(tester.getCenter(canvas) - tester.getCenter(child));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      child.hitTestable(),
      findsOneWidget,
      reason:
          'canvas=${tester.getRect(canvas)}, child=${tester.getRect(child)}, parent=${tester.getRect(parent)}',
    );
    expect(
      tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!
          .value
          .storage[0],
      greaterThanOrEqualTo(.85),
    );
    await tester.tap(find.byKey(const Key('research-fit')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<InteractiveViewer>(canvas)
          .transformationController!
          .value
          .storage[0],
      lessThan(.85),
      reason:
          'only the explicit overview operation may shrink the whole forest',
    );
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

  testWidgets(
    'field changes focus the entrance even when restored research starts midway',
    (tester) async {
      final original = initial();
      original.state.research.addAll(['oxygen_pilot', 'life_support']);
      final restored = GameEngine(GameState.fromJson(original.state.toJson()));
      expect(restored.state.research.first, 'oxygen_pilot');
      expect(restored.state.discoveredResearchIds.first, 'oxygen_pilot');
      await tester.pumpWidget(tree(restored));
      await tester.pumpAndSettle();

      final materials = find.byKey(const Key('research-filter-materials'));
      await tester.ensureVisible(materials);
      await tester.tap(materials);
      await tester.pumpAndSettle();
      final entranceId = ResearchCatalog.idForCatalog('R01');
      final entrance = find.byKey(Key('research-node-$entranceId'));
      final canvas = find.byKey(const Key('research-tree-canvas'));
      expect(entrance.hitTestable(), findsOneWidget);
      final entranceCenter = tester.getRect(entrance).center;
      final viewportCenter = tester.getRect(canvas).center;
      expect(entranceCenter.dx, closeTo(viewportCenter.dx, 1));
      expect(entranceCenter.dy, closeTo(viewportCenter.dy, 1));
      expect(
        (tester
                    .getRect(
                      find.byKey(const Key('research-node-oxygen_pilot')),
                    )
                    .center -
                viewportCenter)
            .distance,
        greaterThan(50),
        reason: 'the saved insertion order must not choose the camera target',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
