import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/presentation/research_developments.dart';

class _DevelopmentSave implements SaveRepository {
  Map<String, dynamic>? snapshot;

  @override
  Future<SaveLoadResult> load() async =>
      SaveLoadResult(data: snapshot, recovered: false, generation: 1);

  @override
  Future<void> save(Map<String, dynamic> data) async {
    snapshot = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
  }
}

void main() {
  Future<GameController> initialize(_DevelopmentSave repository) async {
    final controller = GameController(
      repository,
      devTools: true,
      now: () => DateTime.utc(2026, 10, 20),
    );
    await controller.initialize(startTimer: false);
    controller.state
      ..firstRunTutorial = FirstRunTutorialStep.completed
      ..openingSeen = true
      ..moneyUnits = 100000 * GameState.moneyScale;
    addTearDown(controller.dispose);
    return controller;
  }

  Widget panel(GameController controller, List<String> operations) =>
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => SingleChildScrollView(
              child: ResearchDevelopments(
                controller: controller,
                onReserveOperation: operations.add,
              ),
            ),
          ),
        ),
      );

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('only unlocked applications exist in the development view', (
    tester,
  ) async {
    final controller = await initialize(_DevelopmentSave());
    controller.state.research.add('algal_cultivation');
    await tester.pumpWidget(panel(controller, []));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('development-algal_cultivation')),
      findsOneWidget,
    );
    final hidden = ResearchCatalog.byCatalogId('M12')!;
    expect(find.text(hidden.unlockName), findsNothing);
    expect(find.byKey(Key('development-${hidden.id}')), findsNothing);
    expect(controller.state.developments, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'build, preserve city, operate and allocate researchers separately',
    (tester) async {
      final repository = _DevelopmentSave();
      final controller = await initialize(repository);
      controller.state.research.add('algal_cultivation');
      final operations = <String>[];
      await tester.pumpWidget(panel(controller, operations));
      await tester.pumpAndSettle();
      await tap(
        tester,
        find.byKey(const Key('build-development-algal_cultivation')),
      );
      final plan = controller.state.plans.singleWhere(
        (plan) => plan.definition.developmentId == 'algal_cultivation',
      );
      expect(plan.developmentCityId, 'earth_delta');
      expect(controller.state.developments, isEmpty);
      await controller.advanceForDevelopment(
        duration: Duration(milliseconds: plan.remainingMs),
      );
      await tester.pumpAndSettle();
      expect(controller.state.developments, contains('algal_cultivation'));
      expect(controller.state.developmentEnabled['algal_cultivation'], isFalse);
      expect(controller.state.developmentWorkers, 0);
      expect(
        controller.state.developmentCityIds['algal_cultivation'],
        'earth_delta',
      );
      await tap(
        tester,
        find.byKey(const Key('enable-development-algal_cultivation')),
      );
      expect(
        controller.state.isDevelopmentOperational('algal_cultivation'),
        isTrue,
      );
      expect(controller.state.developmentWorkers, 1);
      final researchers = controller.state.researchers;
      await tap(
        tester,
        find.byKey(const Key('development-research-plus-algal_cultivation')),
      );
      expect(controller.state.developmentResearchers['algal_cultivation'], 1);
      expect(controller.state.researchers, researchers);
      expect(controller.state.labResearchers, researchers - 1);
      final saved = GameState.fromJson(repository.snapshot!);
      expect(saved.developmentCityIds['algal_cultivation'], 'earth_delta');
      expect(saved.developmentResearchers['algal_cultivation'], 1);
      await tap(
        tester,
        find.byKey(const Key('operate-development-algal_cultivation')),
      );
      expect(operations, [
        GameContent.developmentOperationTaskId('algal_cultivation'),
      ]);
      // The development shortcut shows an eight-second command notice even
      // when this focused panel omits the product's notice banner.
      await tester.pump(const Duration(seconds: 8));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mapped research routes to placement without purchasing from the list',
    (tester) async {
      final controller = await initialize(_DevelopmentSave());
      controller.state.research.add('orbital_gardens');
      final routes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResearchDevelopments(
                controller: controller,
                onReserveOperation: (_) {},
                onOpenMap: (technologyId, cityId) =>
                    routes.add('$technologyId@$cityId'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('build-development-orbital_gardens')),
        findsNothing,
      );
      await tap(
        tester,
        find.byKey(const Key('open-building-map-orbital_gardens')),
      );
      expect(routes, ['orbital_gardens@earth_delta']);
      expect(controller.state.plans, isEmpty);
      expect(controller.state.developments, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('paused installations release people and cannot run a contract', (
    tester,
  ) async {
    final controller = await initialize(_DevelopmentSave());
    controller.state
      ..research.add('algal_cultivation')
      ..developments.add('algal_cultivation')
      ..developmentCityIds['algal_cultivation'] = 'earth_delta'
      ..developmentEnabled['algal_cultivation'] = true
      ..developmentResearchers['algal_cultivation'] = 2;
    await tester.pumpWidget(panel(controller, []));
    await tester.pumpAndSettle();
    await tap(
      tester,
      find.byKey(const Key('enable-development-algal_cultivation')),
    );
    expect(controller.state.developmentWorkers, 0);
    expect(controller.state.developmentResearchers['algal_cultivation'], 0);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('operate-development-algal_cultivation')),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
