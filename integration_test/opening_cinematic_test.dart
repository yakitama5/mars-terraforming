import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/infrastructure/file_save_store.dart';
import 'package:mars_terraforming/main.dart';
import 'package:mars_terraforming/presentation/mission_adviser.dart';
import 'package:mars_terraforming/presentation/mission_cinematic.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native rendered film leads through animated dialogue into naming',
    (tester) async {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      final previousPolicy = binding.framePolicy;
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final directory = await Directory.systemTemp.createTemp(
        'mars-cinematic-',
      );
      final controller = GameController(FileSaveStore(directory));
      await controller.initialize(startTimer: false);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        binding.framePolicy = previousPolicy;
        await directory.delete(recursive: true);
      });
      await tester.pumpWidget(MarsApp(controller: controller));
      Future<void> wait(Duration duration) =>
          tester.runAsync(() => Future<void>.delayed(duration));
      Future<void> tap(String key) async {
        await tester.tap(find.byKey(Key(key)));
        await tester.pump();
        await wait(const Duration(milliseconds: 350));
      }

      for (
        var i = 0;
        i < 120 && find.byKey(const Key('cinematic-pause')).evaluate().isEmpty;
        i++
      ) {
        await wait(const Duration(milliseconds: 250));
        await tester.pump();
      }
      expect(find.byType(fs.SceneView), findsOneWidget);
      expect(find.textContaining('表示できませんでした'), findsNothing);
      expect(find.byKey(const Key('cinematic-pause')), findsOneWidget);
      await tap('cinematic-pause');
      await tester.runAsync(() async {
        final context = tester.element(find.byType(MissionCinematic));
        for (final asset in [
          ...MinaExpression.values.map((value) => value.assetPath),
          'assets/images/mina_blink.png',
        ]) {
          await precacheImage(AssetImage(asset), context);
        }
      });
      // The external recorder begins only after GPU initialization and orientation.
      // ignore: avoid_print
      print('CINEMATIC_VIDEO_READY');
      await wait(const Duration(seconds: 3));
      await tap('cinematic-pause');
      final initialMoney = controller.state.moneyUnits;
      final initialTime = controller.state.simulatedMs;
      final clock = Stopwatch()..start();
      for (var chapter = 0; chapter < 5; chapter++) {
        final target = Duration(seconds: 4 + 8 * chapter);
        if (clock.elapsed < target) await wait(target - clock.elapsed);
        await tester.pump();
        expect(
          find.text(
            '${chapter + 1}  /  ${MissionCinematic.chapters[chapter].$1}',
          ),
          findsOneWidget,
        );
        await binding.takeScreenshot('cinematic-ios-${chapter + 1}');
        expect(tester.takeException(), isNull);
      }
      for (
        var i = 0;
        i < 40 && find.byKey(const Key('opening-next')).evaluate().isEmpty;
        i++
      ) {
        await wait(const Duration(milliseconds: 250));
        await tester.pump();
      }
      await wait(const Duration(seconds: 4));
      await binding.takeScreenshot('cinematic-ios-dialogue');
      expect(controller.state.moneyUnits, initialMoney);
      expect(controller.state.simulatedMs, initialTime);
      expect(controller.state.openingSeen, isFalse);
      await tap('opening-next');
      await wait(const Duration(seconds: 6));
      await binding.takeScreenshot('cinematic-ios-dialogue-normal');
      await tap('opening-next');
      await wait(const Duration(seconds: 3));
      await tap('opening-next');
      expect(find.byKey(const Key('mission-names-save')), findsOneWidget);
      await wait(const Duration(seconds: 1));
      // ignore: avoid_print
      print('CINEMATIC_VIDEO_DONE');
      await wait(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );
}
