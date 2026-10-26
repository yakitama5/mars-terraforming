import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/presentation/agency_management.dart';
import 'package:mars_terraforming/presentation/early_development_guide.dart';
import 'package:mars_terraforming/presentation/resource_overview_dialog.dart';

class _ResearchGuideSave implements SaveRepository {
  @override
  Future<SaveLoadResult> load() async =>
      const SaveLoadResult(data: null, recovered: false, generation: 1);

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {}
}

void main() {
  final epoch = DateTime.utc(2026, 10, 20);

  Future<GameController> initialize() async {
    final controller = GameController(_ResearchGuideSave(), now: () => epoch);
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    return controller;
  }

  testWidgets(
    'first research guide shows RP rather than an extra research bill',
    (tester) async {
      final controller = await initialize();
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 360,
                child: EarlyDevelopmentGuide(
                  controller: controller,
                  compact: true,
                  onResearch: opened.add,
                  onCity: (_) {},
                  onOperations: (_, {String? facilityId}) {},
                  onAgency: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.textContaining(
          '必要 ${GameContent.researchPointCost('life_support')} RP',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('RP/分'), findsOneWidget);
      expect(find.textContaining('研究費'), findsNothing);
      await tester.tap(find.byKey(const Key('next-goal')));
      expect(opened, ['life_support']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'resource overview explains common RP and separate construction',
    (tester) async {
      final controller = await initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResourceOverviewDialog(
              controller: controller,
              onOpenAgency: () {},
            ),
          ),
        ),
      );
      expect(find.text('共通研究ポイント'), findsOneWidget);
      expect(find.text('研究ポイントの生産'), findsOneWidget);
      expect(find.textContaining('都市条件がそろう'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('city foundation explains storage and fixed research capacity', (
    tester,
  ) async {
    final controller = await initialize();
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgencyManagement(
            controller: controller,
            section: 0,
            onSectionChanged: (_) {},
            onOpenOperations: () {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('agency-foundation')), findsOneWidget);
    expect(find.byKey(const Key('staff-research-more')), findsNothing);
    expect(find.textContaining('RP/時'), findsWidgets);
    expect(find.textContaining('保有上限が広がります'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
