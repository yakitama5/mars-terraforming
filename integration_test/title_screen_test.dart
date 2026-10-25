import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/infrastructure/file_save_store.dart';
import 'package:mars_terraforming/main.dart';
import 'package:mars_terraforming/presentation/mission_opening.dart';
import 'package:mars_terraforming/presentation/title_scene_data.dart';
import 'package:mars_terraforming/presentation/title_screen.dart';
import 'package:mars_terraforming/rendering/title_scene.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'iOS GPU: saved Mars, fixed title viewpoint, moving space and safe launch',
    (tester) async {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      final previousPolicy = binding.framePolicy;
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final directory = await Directory.systemTemp.createTemp('mars-title-');
      final controllers = <GameController>[];
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        for (final controller in controllers) {
          await controller.save();
          controller.dispose();
        }
        binding.framePolicy = previousPolicy;
        await directory.delete(recursive: true);
      });

      Future<void> wait(Duration duration) async {
        await tester.runAsync(() => Future<void>.delayed(duration));
        await tester.pump();
      }

      Future<GameController> open(
        FileSaveStore repository,
        DateTime Function() now,
      ) async {
        final controller = GameController(repository, now: now);
        controllers.add(controller);
        await controller.initialize(startTimer: false);
        expect(controller.error, isNull);
        await tester.pumpWidget(MarsApp(controller: controller));
        await tester.pump();
        for (var attempt = 0; attempt < 120; attempt++) {
          final views = find.descendant(
            of: find.byType(TitleScene),
            matching: find.byType(fs.SceneView),
          );
          if (views.evaluate().isNotEmpty) break;
          await wait(const Duration(milliseconds: 250));
        }
        expect(find.byType(TitleScreen), findsOneWidget);
        expect(find.byType(fs.SceneView), findsOneWidget);
        expect(find.textContaining('表示を準備できませんでした'), findsNothing);
        await wait(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
        return controller;
      }

      fs.SceneView view() => tester.widget<fs.SceneView>(
        find.descendant(
          of: find.byType(TitleScene),
          matching: find.byType(fs.SceneView),
        ),
      );

      List<double> cameraPose() {
        final camera = view().camera! as fs.PerspectiveCamera;
        return [
          ...camera.position.storage,
          ...camera.target.storage,
          camera.fovRadiansY,
        ];
      }

      List<double> nodePose(String name) {
        final node = view().scene!.root.getChildByName(name)!;
        return [
          ...node.position.storage,
          ...node.rotation.storage,
          ...node.scale.storage,
        ];
      }

      Future<void> capture(String name) async {
        await wait(const Duration(milliseconds: 500));
        await binding.takeScreenshot(name);
      }

      Future<void> start() async {
        await tester.tap(find.byKey(const Key('title-start')));
        await wait(const Duration(seconds: 1));
        expect(find.byType(TitleScreen), findsNothing);
        expect(tester.takeException(), isNull);
      }

      var now = DateTime.utc(2026, 10, 25, 12);
      final pristineStore = FileSaveStore(directory, slot: 'pristine');
      final pristine = await open(pristineStore, () => now);
      final initialMoney = pristine.state.moneyUnits;
      final initialTime = pristine.state.simulatedMs;
      expect(pristine.state.openingStarted, isFalse);
      expect(find.byType(MissionOpening), findsNothing);
      final initialCamera = cameraPose();
      final initialMars = nodePose('title-mars');
      final initialStars = nodePose('title-stars');
      final initialSatellite = nodePose('title-satellite');
      await capture('title-ios-pristine');
      // ignore: avoid_print
      print('TITLE_VIDEO_READY');
      await wait(const Duration(seconds: 7));
      await capture('title-ios-passage');
      await wait(const Duration(seconds: 11));
      await capture('title-ios-pristine-motion');
      expect(cameraPose(), initialCamera, reason: 'タイトルの視点は時間で移動しない');
      expect(nodePose('title-mars'), initialMars, reason: '火星の地表と姿勢は固定する');
      expect(nodePose('title-stars'), isNot(initialStars));
      expect(nodePose('title-satellite'), isNot(initialSatellite));
      now = now.add(const Duration(hours: 8));
      await pristine.resume();
      expect(pristine.state.moneyUnits, initialMoney);
      expect(pristine.state.simulatedMs, initialTime);
      expect(pristine.state.openingStarted, isFalse);
      await start();
      expect(find.byType(MissionOpening), findsOneWidget);
      expect(pristine.state.openingStarted, isTrue);
      expect(pristine.state.openingSeen, isFalse);
      expect(pristine.state.moneyUnits, initialMoney);
      await tester.pumpWidget(const SizedBox.shrink());
      await pristine.save();

      // 撮影用の発展済みセーブ。通常の到達時間・全球居住の実証ではない。
      final developedStore = FileSaveStore(directory, slot: 'developed');
      final developedState = GameState.initial(now)
        ..openingSeen = true
        ..openingStarted = true
        ..firstRunTutorial = FirstRunTutorialStep.completed
        ..completionBannersEnabled = false
        ..tipsEnabled = false
        ..money = 2000000
        ..marsResidents = 360
        ..habitatChoice = 'dome';
      developedState.legacyUnlockedPlanets.addAll(['moon', 'mars']);
      developedState.achievements.add('first_landing');
      developedState.research.addAll(GameContent.researchTechnologies.keys);
      for (final city in GameContent.cities.values.where(
        (city) => city.planet == 'mars',
      )) {
        var greenhouses = 0;
        var habitat = false;
        for (var plot = 0; plot < city.plotCount; plot++) {
          final terrain = city.terrainAt(plot);
          final habitatDefinition = GameContent.districts['mars_habitat']!;
          final greenhouseDefinition = GameContent.districts['greenhouse']!;
          String? district;
          if (!habitat &&
              (habitatDefinition.allowedTerrain.isEmpty ||
                  habitatDefinition.allowedTerrain.contains(terrain))) {
            habitat = true;
            developedState.marsHabitats++;
            district = 'mars_habitat';
          } else if (greenhouses < 4 &&
              (greenhouseDefinition.allowedTerrain.isEmpty ||
                  greenhouseDefinition.allowedTerrain.contains(terrain))) {
            greenhouses++;
            district = 'greenhouse';
          }
          if (district == null) continue;
          developedState.districts['${city.id}:$plot'] = DistrictState(
            cityId: city.id,
            plotIndex: plot,
            districtId: district,
          );
        }
      }
      final completedWork = GameEngine(developedState);
      expect(completedWork.enqueue('factory_contract'), isNull);
      completedWork.advanceBy(const Duration(minutes: 5));
      expect(developedState.plans.single.completedRuns, 1);
      expect(developedState.plans.single.isFinished, isTrue);
      final baseline = jsonDecode(
        jsonEncode(developedState.toJson()),
      ) as Map<String, dynamic>;
      await developedStore.save(baseline);
      final developed = await open(developedStore, () => now);
      final visual = buildTitleSceneSnapshot(developed.state);
      expect(visual.settlementCount, greaterThan(0));
      expect(visual.greenery, greaterThan(0));
      expect(visual.cloudCoverage, greaterThan(0));
      expect(find.byType(MissionOpening), findsNothing);
      final developedCamera = cameraPose();
      final developedMars = nodePose('title-mars');
      final developedEarth = nodePose('title-earth-globe');
      await capture('title-ios-developed');
      await wait(const Duration(seconds: 18));
      await capture('title-ios-developed-motion');
      expect(cameraPose(), developedCamera);
      expect(nodePose('title-mars'), developedMars);
      expect(nodePose('title-earth-globe'), isNot(developedEarth));
      expect(developed.state.toJson(), baseline, reason: '描画待機は進行と報酬を変更しない');

      now = now.add(const Duration(minutes: 10));
      final expected = GameEngine(GameState.fromJson(baseline))..advanceTo(now);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await wait(const Duration(milliseconds: 300));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await wait(const Duration(milliseconds: 700));
      await developed.save();
      expect(developed.state.toJson(), expected.state.toJson());
      expect(developed.state.plans.single.completedRuns, 1);
      expect(find.byType(TitleScreen), findsOneWidget);
      await start();
      expect(find.byType(MissionOpening), findsNothing);
      expect(find.byKey(const Key('navigation-1')), findsOneWidget);
      expect(developed.state.toJson(), expected.state.toJson());

      await tester.pumpWidget(const SizedBox.shrink());
      await developed.save();
      final restarted = await open(developedStore, () => now);
      expect(find.byType(TitleScreen), findsOneWidget);
      expect(restarted.state.toJson(), expected.state.toJson());
      expect(restarted.state.plans.single.completedRuns, 1);
      await start();
      expect(find.byType(MissionOpening), findsNothing);
      expect(find.byKey(const Key('navigation-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
