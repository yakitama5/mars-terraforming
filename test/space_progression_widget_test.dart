import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/presentation/game_screen.dart';

import 'widget_test.dart' show MemorySave;

void main() {
  for (final size in [const Size(844, 390), const Size(1280, 800)]) {
    testWidgets('planet and city selectors follow exploration at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = GameController(MemorySave());
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            showTitle: false,
            controller: controller,
            showIntroduction: false,
            renderScene: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('select-planet-earth')), findsOneWidget);
      expect(find.byKey(const Key('select-planet-moon')), findsNothing);
      expect(find.byKey(const Key('select-planet-mars')), findsNothing);
      await tester.tap(find.byKey(const Key('navigation-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('city-selector')));
      await tester.pumpAndSettle();
      expect(find.text('南極月面拠点'), findsNothing);
      expect(find.text('アルカディア'), findsNothing);
      await tester.tapAt(const Offset(10, 100));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('navigation-0')));
      await tester.pumpAndSettle();
      await controller.command((engine) {
        engine.state.moneyUnits = 10000 * GameState.moneyScale;
        engine.enqueue('launch_contract');
        engine.advanceBy(const Duration(minutes: 3));
        return null;
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('select-planet-moon')), findsOneWidget);
      expect(find.byKey(const Key('select-planet-mars')), findsNothing);
      await tester.tap(find.byKey(const Key('select-planet-moon')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('select-city-moon_south_pole')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('open-city')),
        160,
        scrollable: find.descendant(
          of: find.byKey(const Key('planet-detail')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byKey(const Key('open-city')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('district-option-moon_outpost')),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('district-option-moon_spaceport')),
        120,
        scrollable: find.descendant(
          of: find.byKey(const Key('city-facility-palette')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        find.byKey(const Key('district-option-moon_spaceport')),
        findsOneWidget,
      );
      await controller.command(
        (engine) => engine.unlockResearch('life_support'),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('city-facility-palette')),
        const Offset(0, 600),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('district-option-moon_outpost')),
        findsOneWidget,
      );
      await controller.command((engine) {
        engine.state.earthKits = 2;
        engine.enqueue('moon_delivery', repeats: 2);
        engine.advanceBy(const Duration(minutes: 5));
        engine.enqueueDistrict('moon_south_pole', 12, 'moon_outpost');
        engine.advanceBy(const Duration(minutes: 4));
        engine.enqueueDistrict('moon_south_pole', 13, 'moon_spaceport');
        engine.advanceBy(const Duration(minutes: 6));
        engine.enqueue('mars_probe');
        engine.advanceBy(const Duration(minutes: 4));
        return null;
      });
      await tester.tap(find.byKey(const Key('navigation-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('select-planet-earth')), findsOneWidget);
      expect(find.byKey(const Key('select-planet-moon')), findsOneWidget);
      expect(find.byKey(const Key('select-planet-mars')), findsOneWidget);
      await tester.tap(find.byKey(const Key('select-planet-mars')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('select-city-mars_arcadia')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
