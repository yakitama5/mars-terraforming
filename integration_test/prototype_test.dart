import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/infrastructure/file_save_store.dart';
import 'package:mars_terraforming/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as fs;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('iOS: GPU, allocation, habitation, and save/resume', (
    tester,
  ) async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    final directory = await Directory.systemTemp.createTemp(
      'mars-integration-',
    );
    final controller = GameController(FileSaveStore(directory), devTools: true);
    await controller.initialize(startTimer: false);
    await tester.pumpWidget(MarsApp(controller: controller));
    await tester.pump(const Duration(seconds: 6));
    for (
      var i = 0;
      i < 60 && find.byType(fs.SceneView).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pump(const Duration(seconds: 2));
    await binding.takeScreenshot('prototype-initial');
    expect(find.textContaining('3D表示を開始できませんでした'), findsNothing);
    expect(find.byType(fs.SceneView), findsOneWidget);
    expect(tester.takeException(), isNull);

    // UI reserves research; independent orders then exercise the full loop.
    await tester.tap(find.byKey(const Key('queue-life_support')));
    await tester.pump(const Duration(seconds: 1));
    await controller.command((engine) {
      engine.enqueue('factory_contract', repeats: 3);
      engine.enqueue('habitat_kit');
      engine.enqueue('mars_delivery');
      engine.enqueue('build_habitat');
      return null;
    });
    // Reallocate future factory runs through the actual iOS controls. The
    // already-paid contract keeps running while the kit moves ahead of repeats.
    final factoryRun = controller.state.currentPlanFor('factory')!;
    final kit = controller.state.plans.firstWhere(
      (plan) => plan.taskId == 'habitat_kit',
    );
    await tester.tap(find.text('設備・進行'));
    await tester.pump(const Duration(milliseconds: 300));
    final moveKitUp = find.byKey(Key('queue-up-${kit.id}'));
    await tester.scrollUntilVisible(
      moveKitUp,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(moveKitUp);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(moveKitUp);
    await tester.pump(const Duration(milliseconds: 500));
    await controller.save();
    expect(controller.state.currentPlanFor('factory'), factoryRun);
    expect(factoryRun.completedRuns, 0);
    expect(factoryRun.remainingMs, greaterThan(0));
    expect(controller.state.upcomingPlansFor('factory'), [kit, factoryRun]);
    expect(find.byKey(Key('current-${factoryRun.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('prototype-equipment');

    // Closing the full-width list recreates the actual GPU view successfully.
    await tester.tap(find.text('計画をつくる'));
    await tester.pump(const Duration(milliseconds: 500));
    for (
      var i = 0;
      i < 20 && find.byType(fs.SceneView).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(fs.SceneView), findsOneWidget);
    expect(find.textContaining('3D表示を開始できませんでした'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('advance-time')));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('advance-time')));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('advance-time')));
    await tester.pump(const Duration(seconds: 1));
    expect(controller.state.achievements, contains('first_landing'));
    expect(controller.state.marsHabitats, 0);
    await tester.scrollUntilVisible(
      find.byKey(const Key('choose-dome')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.byKey(const Key('choose-dome')));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('choose-dome')));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('advance-time')));
    await tester.pump(const Duration(seconds: 2));
    expect(controller.state.marsHabitats, 1);
    expect(controller.state.marsResidents, 12);
    expect(controller.state.achievements, contains('dome_habitat'));
    await tester.tap(find.text('開発記録'));
    await tester.pump(const Duration(seconds: 2));
    await binding.takeScreenshot('prototype-habitat');
    await tester.tap(find.text('地球'));
    await tester.pump(const Duration(seconds: 2));
    await binding.takeScreenshot('prototype-earth');
    await controller.save();
    final resumed = GameController(FileSaveStore(directory));
    await resumed.initialize(startTimer: false);
    expect(resumed.state.marsResidents, 12);
    expect(resumed.state.claimedRewards, controller.state.claimedRewards);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    resumed.dispose();
    controller.dispose();
    await directory.delete(recursive: true);
  });
}
