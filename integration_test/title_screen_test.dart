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
import 'package:mars_terraforming/rendering/base_scene.dart';
import 'package:mars_terraforming/rendering/city_scene.dart';
import 'package:mars_terraforming/rendering/title_scene.dart';
import 'package:mars_terraforming/rendering/title_scene_motion.dart';
import 'package:mars_terraforming/rendering/title_spacecraft_models.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('タイトル機体のロード後は共有templateの所有を残さない', (tester) async {
    await fs.Scene.initializeStaticResources();
    final models = await TitleSpacecraftModels.load();
    for (final node in [models.satellite, models.rocket, models.asteroid]) {
      expect(node.combinedWorldBounds, isNotNull);
    }
    // 他のloadが存在しない独立した最初の試験で、公開APIの所有数を確認。
    for (final asset in [
      TitleSpacecraftModels.satelliteAsset,
      TitleSpacecraftModels.rocketAsset,
      TitleSpacecraftModels.asteroidAsset,
    ]) {
      expect(
        await fs.releaseScene(asset),
        isFalse,
        reason: '返したnodeの素材を保持しつつ、template cacheのclaimは返却済み',
      );
    }
  });

  testWidgets('起動直後の開始操作でOPへ進みGPU初期化と競合しない', (tester) async {
    final previousPolicy = binding.framePolicy;
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final directory = await Directory.systemTemp.createTemp(
      'mars-title-early-',
    );
    final controller = GameController(
      FileSaveStore(directory),
      now: () => DateTime.utc(2026, 10, 26),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.save();
      controller.dispose();
      binding.framePolicy = previousPolicy;
      await directory.delete(recursive: true);
    });
    await controller.initialize(startTimer: false);
    final money = controller.state.moneyUnits;
    await tester.pumpWidget(MarsApp(controller: controller));
    expect(find.byKey(const Key('title-start')), findsOneWidget);
    expect(find.text('TAP TO START'), findsOneWidget);
    await tester.tap(find.byKey(const Key('title-start')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 5)),
    );
    await tester.pump();
    expect(find.byType(TitleScreen), findsNothing);
    expect(find.byType(MissionOpening), findsOneWidget);
    expect(controller.state.openingStarted, isTrue);
    expect(controller.state.moneyUnits, money);
    expect(tester.takeException(), isNull);
    // OPの音声破棄はnative呼出しを伴う。Widget終了直後の検証へ音声の
    // フレームcallbackを持ち越さず、通常の非同期後片付けを待つ。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

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
        expect(find.byKey(const Key('title-start')), findsOneWidget);
        expect(find.text('TAP TO START'), findsOneWidget);
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

      double starAngle() => (view().scene!.skybox!.source as fs.PreprocessedSky)
          .parameters
          .getFloat('sky_yaw');

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
      final initialStars = starAngle();
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
      expect(starAngle(), isNot(initialStars));
      expect(nodePose('title-satellite'), isNot(initialSatellite));
      final marsCenter = view().scene!.root
          .getChildByName('title-mars')!
          .position;
      final camera = view().camera!;
      final viewport = tester.getSize(find.byType(TitleScene));
      for (final offsetAt in [
        (TitleSceneMotion motion) => motion.sunOffset,
        (TitleSceneMotion motion) => motion.earthOffset,
      ]) {
        var inside = 0;
        var outside = 0;
        for (var seconds = 0.0; seconds < 360; seconds += 5) {
          final point = camera.worldToScreen(
            marsCenter + offsetAt(TitleSceneMotion(seconds)),
            viewport,
          );
          if (point != null && (Offset.zero & viewport).contains(point)) {
            inside++;
          } else {
            outside++;
          }
        }
        expect(inside, greaterThan(0), reason: '自転と公転の組合せで遠景が現れる');
        expect(outside, greaterThan(0), reason: '地球と太陽を画面へ固定しない');
      }
      for (final name in ['title-satellite', 'title-rocket']) {
        final node = view().scene!.root.getChildByName(name)!;
        expect(node.scale.x, lessThan(.06), reason: '火星に比べて小さい宇宙機');
        expect((node.position - marsCenter).length, greaterThan(9));
      }
      final initialSun = nodePose('title-sun');
      await wait(const Duration(seconds: 45));
      await capture('title-ios-orbital-phase');
      expect(nodePose('title-sun'), isNot(initialSun));
      expect(cameraPose(), initialCamera);
      expect(nodePose('title-mars'), initialMars);
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

      Future<fs.SceneView> waitForGlobe(String name) async {
        for (var i = 0; i < 160; i++) {
          final views = find.descendant(
            of: find.byType(BaseScene),
            matching: find.byType(fs.SceneView),
          );
          if (views.evaluate().isNotEmpty) {
            final globe = tester.widget<fs.SceneView>(views.first);
            if (globe.scene!.root.getChildByName(name)?.visible == true) {
              await wait(const Duration(seconds: 1));
              expect(tester.takeException(), isNull);
              return globe;
            }
          }
          await wait(const Duration(milliseconds: 250));
        }
        fail('全球モデル $name が表示されなかった');
      }

      var globe = await waitForGlobe('map-earth');
      expect(globe.scene!.root.getChildByName('map-sun'), isNotNull);
      await capture('title-ios-game-earth');
      final marker = find.bySemanticsLabel(RegExp('デルタ湾岸を選択'));
      expect(marker, findsOneWidget);
      await tester.tap(marker);
      await wait(const Duration(milliseconds: 300));
      expect(
        tester.widget<BaseScene>(find.byType(BaseScene)).selectedCityId,
        'earth_delta',
      );
      await tester.tap(find.byTooltip('惑星を拡大'));
      await wait(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('select-planet-mars')));
      await tester.pump();
      globe = await waitForGlobe('map-mars');
      final marsGlobe = globe.scene!.root.getChildByName('map-mars')!;
      expect(
        marsGlobe.rotation.storage,
        orderedEquals([0.0, 0.0, 0.0, 1.0]),
        reason: '都市の緯度経度に地理を合わせる',
      );
      await capture('title-ios-game-mars');
      await tester.tap(find.byKey(const Key('select-planet-moon')));
      await tester.pump();
      globe = await waitForGlobe('月');
      expect(globe.scene!.root.getChildByName('map-sun')!.visible, isFalse);
      await capture('title-ios-game-moon');
      await tester.tap(find.byKey(const Key('select-planet-earth')));
      await tester.pump();
      await waitForGlobe('map-earth');
      await tester.tap(find.byKey(const Key('navigation-1')));
      await tester.pump();
      final cityGpu = find.descendant(
        of: find.byType(CityScene),
        matching: find.byType(fs.SceneView),
      );
      for (var i = 0; i < 160 && cityGpu.evaluate().isEmpty; i++) {
        await wait(const Duration(milliseconds: 250));
      }
      expect(find.byType(CityScene), findsOneWidget);
      expect(cityGpu, findsOneWidget, reason: '簡易地図でなく都市の実GPU描画を確認');
      expect(find.textContaining('3Dを開始できない'), findsNothing);
      await wait(const Duration(seconds: 2));
      expect(tester.widget<CityScene>(find.byType(CityScene)).earth, isTrue);
      await capture('title-ios-game-city-toon');
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
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
