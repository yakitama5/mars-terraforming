import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/infrastructure/file_save_store.dart';
import 'package:mars_terraforming/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('bundled score decodes, seeks and pauses on the native player', (
    tester,
  ) async {
    final player = AudioPlayer();
    try {
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setSourceAsset('audio/opening_music.wav');
      expect((await player.getDuration())!.inMilliseconds, closeTo(40000, 50));
      await player.seek(const Duration(seconds: 8));
      await player.resume();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      final playing = (await player.getCurrentPosition())!;
      expect(playing.inMilliseconds, inInclusiveRange(8700, 10500));
      await player.pause();
      final paused = (await player.getCurrentPosition())!;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      expect(
        (await player.getCurrentPosition())!.inMilliseconds,
        closeTo(paused.inMilliseconds, 100),
      );
    } finally {
      await player.dispose();
    }
  });

  testWidgets('Luna guides the first actual district then releases free play', (
    tester,
  ) async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    final previousPolicy = binding.framePolicy;
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    Future<void> settle() async {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 700)),
      );
      await tester.pump();
    }

    final directory = await Directory.systemTemp.createTemp('luna-tutorial-');
    final controller = GameController(FileSaveStore(directory));
    await controller.initialize(startTimer: false);
    await controller.skipOpening();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      binding.framePolicy = previousPolicy;
      await directory.delete(recursive: true);
    });
    await tester.pumpWidget(MarsApp(controller: controller));
    await settle();
    expect(
      controller.state.firstRunTutorial,
      FirstRunTutorialStep.placeHousing,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 5)),
    );
    await tester.pump();
    await binding.takeScreenshot('luna-ios-tutorial-start');
    await tester.tap(find.byKey(const Key('district-option-housing')));
    await settle();
    await tester.tap(find.byKey(const Key('plot-earth_delta-1')));
    await settle();
    await tester.tap(find.byKey(const Key('confirm-district')));
    await settle();
    expect(
      controller.state.firstRunTutorial,
      FirstRunTutorialStep.finishConstruction,
    );
    expect(controller.state.districtCount('housing'), 0);
    await tester.tap(find.byKey(const Key('tutorial-complete-construction')));
    await settle();
    expect(controller.state.districtCount('housing'), 1);
    await binding.takeScreenshot('luna-ios-tutorial-built');
    await tester.tap(find.byKey(const Key('tutorial-continue-income')));
    await settle();
    await binding.takeScreenshot('luna-ios-tutorial-research');
    await tester.tap(find.byKey(const Key('queue-life_support')));
    await settle();
    expect(
      controller.state.firstRunTutorial,
      FirstRunTutorialStep.researchStarted,
    );
    await tester.tap(find.byKey(const Key('tutorial-finish')));
    await settle();
    expect(controller.state.firstRunTutorial, FirstRunTutorialStep.completed);
    expect(controller.state.districtCount('housing'), 1);
    expect(
      controller.state.plans.where((p) => p.taskId == 'life_support').length,
      1,
    );
    expect(tester.takeException(), isNull);
  });
}
