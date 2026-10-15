import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/presentation/game_screen.dart';

import 'widget_test.dart' show MemorySave;

void main() {
  for (final size in [
    const Size(568, 320),
    const Size(844, 390),
    const Size(1280, 800),
  ]) {
    testWidgets('resource overview and navigation remain usable at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = GameController(MemorySave(), devTools: true);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: GameScreen(controller: controller, renderScene: false),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-resources')));
      await tester.pumpAndSettle();
      expect(find.text('国力と収支'), findsOneWidget);
      expect(find.textContaining('毎分収支に含みません'), findsOneWidget);
      await tester.tap(find.byKey(const Key('resources-open-agency')));
      await tester.pumpAndSettle();
      expect(find.text('国力と収支'), findsNothing);
      expect(find.byKey(const Key('agency-section-staff')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
