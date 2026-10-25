import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/main.dart';
import 'package:mars_terraforming/presentation/game_screen.dart';
import 'package:mars_terraforming/presentation/research_tree.dart';

/// Review captures use actual product widgets and the theme built by MarsApp.
/// The bundled Web font is loaded explicitly so Linux CI renders Japanese,
/// rather than the Ahem font installed by the widget-test binding.
class _ReviewSave implements SaveRepository {
  Map<String, dynamic>? snapshot;

  @override
  Future<SaveLoadResult> load() async =>
      SaveLoadResult(data: snapshot, recovered: false, generation: 1);

  @override
  Future<void> save(Map<String, dynamic> value) async {
    snapshot = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  }
}

Future<GameController> _controller() async {
  final controller = GameController(
    _ReviewSave(),
    devTools: true,
    now: () => DateTime.utc(2026, 10, 20, 1, 30),
  );
  await controller.initialize(startTimer: false);
  controller.state
    ..openingSeen = true
    ..firstRunTutorial = FirstRunTutorialStep.completed;
  return controller;
}

Widget _reviewApp({
  required GameController controller,
  required GlobalKey boundaryKey,
  required Widget child,
  double textScale = 1,
}) => Builder(
  builder: (context) {
    final product = MarsApp(
      showTitle: false,
      controller: controller,
      renderScene: false,
      showIntroduction: false,
    ).build(context) as MaterialApp;
    final theme = product.theme!;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: product.locale,
      supportedLocales: product.supportedLocales,
      localizationsDelegates: product.localizationsDelegates,
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'NotoSansJP'),
        primaryTextTheme: theme.primaryTextTheme.apply(
          fontFamily: 'NotoSansJP',
        ),
      ),
      builder: (context, home) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: home!,
      ),
      home: RepaintBoundary(key: boundaryKey, child: child),
    );
  },
);

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  // Paint post-frame camera/selection updates before asking the raster thread.
  await tester.pump();
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('PNGを生成できませんでした');
      final directory = Directory('build/research-review');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(data.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  });
  // Saving first makes the failed frame available for visual diagnosis too.
  expect(tester.takeException(), isNull, reason: '$name にレイアウト・描画例外がありません');
}

void _surface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _fundResearch(GameController controller, String id) {
  controller.state.researchPointUnits =
      GameContent.researchPointCost(id) * GameState.researchPointScale;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('NotoSansJP')
      ..addFont(rootBundle.load('assets/fonts/NotoSansJP.ttf'));
    await loader.load();
  });

  for (final field in ResearchField.values) {
    testWidgets('capture initial ${field.name} without unexplored branches', (
      tester,
    ) async {
      _surface(tester, const Size(884, 402));
      final controller = await _controller();
      addTearDown(controller.dispose);
      final key = GlobalKey();
      final starter = controller.state.discoveredResearchIds
          .map((id) => ResearchCatalog.technologies[id]!)
          .firstWhere((technology) => technology.field == field);
      await tester.pumpWidget(
        _reviewApp(
          controller: controller,
          boundaryKey: key,
          child: Scaffold(
            body: ResearchTree(
              game: controller.state,
              selectedId: starter.id,
              onSelected: (_) {},
              requirementReasons: controller.engine!.researchRequirementReasons,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, key, 'tree_initial_${field.name}_884x402');
      expect(find.byKey(Key('research-node-${starter.id}')), findsOneWidget);
      final hidden = ResearchCatalog.purchasableTechnologies.firstWhere(
        (technology) =>
            technology.field == field &&
            !controller.state.isResearchDiscovered(technology.id),
      );
      expect(find.byKey(Key('research-node-${hidden.id}')), findsNothing);
      expect(find.byKey(Key('research-semantics-${hidden.id}')), findsNothing);
      expect(find.textContaining('/99'), findsNothing);
      expect(find.textContaining('/98'), findsNothing);
    });
  }

  testWidgets('capture actual growing branches and their settled frontier', (
    tester,
  ) async {
    _surface(tester, const Size(884, 402));
    final controller = await _controller();
    addTearDown(controller.dispose);
    final key = GlobalKey();
    Widget screen() => _reviewApp(
      controller: controller,
      boundaryKey: key,
      child: Scaffold(
        body: ResearchTree(
          game: controller.state,
          selectedId: 'orbital_gardens',
          onSelected: (_) {},
          requirementReasons: controller.engine!.researchRequirementReasons,
        ),
      ),
    );
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    _fundResearch(controller, 'orbital_gardens');
    expect(controller.engine!.unlockResearch('orbital_gardens'), isNull);
    await tester.pumpWidget(screen());
    await tester.pump(const Duration(milliseconds: 650));
    await _capture(tester, key, 'tree_growth_bio_884x402');
    expect(find.text('水耕栽培を解放'), findsOneWidget);
    await tester.pumpAndSettle();
    await _capture(tester, key, 'tree_grown_bio_884x402');
    expect(
      find.byKey(Key('research-node-${ResearchCatalog.idForCatalog('B02')}')),
      findsOneWidget,
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  for (final size in [const Size(884, 402), const Size(1280, 800)]) {
    final suffix = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets('capture product research detail and applications $suffix', (
      tester,
    ) async {
      _surface(tester, size);
      final controller = await _controller();
      addTearDown(controller.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        _reviewApp(
          controller: controller,
          boundaryKey: key,
          child: GameScreen(
            showTitle: false,
            controller: controller,
            renderScene: false,
            showIntroduction: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('navigation-2')));
      await tester.pumpAndSettle();
      await _capture(tester, key, 'product_research_overview_$suffix');
      expect(find.byKey(const Key('research-detail')), findsNothing);
      await tester.tap(find.byKey(const Key('research-node-life_support')));
      await tester.pumpAndSettle();
      await _capture(tester, key, 'product_research_detail_$suffix');
      expect(find.byKey(const Key('research-unlocks')), findsOneWidget);
      expect(find.textContaining('/99'), findsNothing);
      final hidden = ResearchCatalog.byCatalogId('M12')!;
      expect(find.text(hidden.name), findsNothing);

      // Use the product route: knowledge unlock, map position and explicit
      // confirmation, then normal simulated time to finish the construction.
      controller.state.moneyUnits = 100000 * GameState.moneyScale;
      await controller.command((engine) {
        _fundResearch(controller, 'orbital_gardens');
        return engine.unlockResearch('orbital_gardens');
      });
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('navigation-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('operations-4')));
      await tester.pumpAndSettle();
      await _capture(tester, key, 'product_applications_$suffix');
      final map = find.byKey(const Key('open-building-map-orbital_gardens'));
      await tester.ensureVisible(map);
      await tester.pumpAndSettle();
      await tester.tap(map);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('building-title-orbital_gardens')),
        findsOneWidget,
      );
      expect(controller.state.developments, isEmpty);
      await tester.tap(find.byKey(const Key('plot-earth_delta-12')));
      await tester.pumpAndSettle();
      final slot = find.byKey(const Key('building-slot-0'));
      await tester.ensureVisible(slot);
      await tester.pumpAndSettle();
      await tester.tap(slot);
      await tester.pumpAndSettle();
      await _capture(tester, key, 'product_application_investment_$suffix');
      await tester.tap(find.byKey(const Key('confirm-map-building')));
      await tester.pumpAndSettle();
      final building = controller.state
          .cityBuildings('earth_delta')
          .singleWhere(
            (building) => building.technologyId == 'orbital_gardens',
          );
      expect(building.plotIndex, 12);
      expect(building.slotIndex, 0);
      await controller.command((engine) {
        engine.advanceBy(const Duration(minutes: 6));
        return null;
      });
      await tester.pumpAndSettle();
      expect(controller.state.developments, contains(building.id));
      final operation = find.byKey(Key('enable-map-building-${building.id}'));
      await tester.ensureVisible(operation);
      await tester.pumpAndSettle();
      await tester.tap(operation);
      await tester.pumpAndSettle();
      expect(controller.state.developmentEnabled[building.id], isTrue);
      await _capture(tester, key, 'product_application_operating_$suffix');
    });
  }

  testWidgets(
    'capture large Japanese text in the mobile product research view',
    (tester) async {
      _surface(tester, const Size(884, 402));
      final controller = await _controller();
      addTearDown(controller.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        _reviewApp(
          controller: controller,
          boundaryKey: key,
          textScale: 1.4,
          child: GameScreen(
            showTitle: false,
            controller: controller,
            renderScene: false,
            showIntroduction: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('navigation-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('research-node-life_support')));
      await tester.pumpAndSettle();
      await _capture(tester, key, 'product_research_large_text_884x402');
    },
  );
}
