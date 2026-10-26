import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/main.dart';
import 'package:mars_terraforming/presentation/agency_management.dart';

class _MemorySave implements SaveRepository {
  @override
  Future<SaveLoadResult> load() async =>
      const SaveLoadResult(data: null, recovered: false, generation: 0);

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {}
}

void main() {
  for (final size in [const Size(568, 320), const Size(844, 390)]) {
    testWidgets(
      'full game exposes city foundation actions with enlarged text at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final controller = GameController(
          _MemorySave(),
          now: () => DateTime.utc(2026, 10, 15),
        );
        await controller.initialize(startTimer: false);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MarsApp(
            showTitle: false,
            showIntroduction: false,
            controller: controller,
            renderScene: false,
          ),
        );
        await tester.tap(find.byKey(const Key('navigation-4')));
        await tester.pumpAndSettle();

        final unchanged = jsonEncode(controller.state.toJson());
        final foundation = find.byKey(const Key('agency-foundation'));
        final scrollable = find
            .descendant(of: foundation, matching: find.byType(Scrollable))
            .first;
        final target = find.byKey(const Key('foundation-open-operations'));
        await tester.scrollUntilVisible(target, 80, scrollable: scrollable);
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
        expect(find.byKey(const Key('staff-research-more')), findsNothing);
        expect(jsonEncode(controller.state.toJson()), unchanged);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('operations-list-0')), findsOneWidget);
        expect(jsonEncode(controller.state.toJson()), unchanged);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('agency explanations remain optional and readable at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = GameController(
        _MemorySave(),
        now: () => DateTime.utc(2026, 10, 15),
      );
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      final before = jsonEncode(controller.state.toJson());
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
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
      expect(
        find.text(GameContent.agencyMetricDescriptions['fame']!),
        findsNothing,
      );
      expect(find.textContaining('無期限の反復中は'), findsNothing);
      expect(find.byKey(const Key('staff-research-more')), findsNothing);
      Future<void> open(String key, String panel) async {
        final target = find.byKey(Key(key));
        await tester.scrollUntilVisible(
          target,
          150,
          scrollable: find
              .descendant(
                of: find.byKey(Key(panel)),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await open('agency-metric-explanations', 'agency-metrics');
      expect(
        find.text(GameContent.agencyMetricDescriptions['fame']!),
        findsOneWidget,
      );
      expect(find.byKey(const Key('agency-foundation')), findsOneWidget);
      expect(find.textContaining('施設への投資で生産能力を伸ばせます。'), findsOneWidget);
      expect(jsonEncode(controller.state.toJson()), before);
      expect(tester.takeException(), isNull);
    });
  }
}
