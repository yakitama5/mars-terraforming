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
      expect(find.textContaining('建設・製造には別途投資'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('staff allocation previews RP and retains industrial tradeoff', (
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
    final before = controller.state.researchers;
    await tester.ensureVisible(find.byKey(const Key('staff-research-more')));
    await tester.tap(find.byKey(const Key('staff-research-more')));
    await tester.pump();
    expect(find.textContaining('RP/分'), findsWidgets);
    expect(
      find.text(
        '研究 ${before + 1}人 / 工業 ${controller.state.specialistCount - controller.state.developmentWorkers - before - 1}人',
      ),
      findsOneWidget,
    );
    expect(controller.state.researchers, before);
    expect(tester.takeException(), isNull);
  });
}
