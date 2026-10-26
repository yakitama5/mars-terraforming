import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
import 'package:mars_terraforming/rendering/title_apparent_planet_scale.dart';
import 'package:mars_terraforming/rendering/title_scene.dart';
import 'package:mars_terraforming/rendering/title_scene_motion.dart';
import 'package:mars_terraforming/rendering/title_spacecraft_models.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _planetAngularMagnification = 128.0;

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
    'GPU: 自転する火星と地表施設・木星・土星を表示し安全に開始する',
    // 実描画・画角・保存を、同じセッションで順に検証する。
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

      fs.Node node(String name) {
        final result = view().scene!.root.getChildByName(name);
        expect(result, isNotNull, reason: 'GPUシーンに$nameが同時に存在する');
        return result!;
      }

      List<double> worldTransform(fs.Node node) =>
          node.globalTransform.storage.toList();

      List<double> worldAxes(fs.Node node) {
        final rotation = node.globalTransform.getRotation();
        return [
          for (final axis in [
            vm.Vector3(1, 0, 0),
            vm.Vector3(0, 1, 0),
            vm.Vector3(0, 0, 1),
          ])
            ...rotation.transformed(axis).normalized().storage,
        ];
      }

      List<double> relativeTransform(fs.Node parent, fs.Node child) {
        final inverse = vm.Matrix4.copy(parent.globalTransform)..invert();
        return (inverse * child.globalTransform).storage.toList();
      }

      double sceneSeconds() =>
          (node('白熱した太陽光球').mesh!.primitives.first.material
                  as fs.PreprocessedMaterial)
              .parameters
              .getFloat('time');

      double equatorialWorldRadius(String name, double modelRadius) =>
          node(name).globalTransform
              .getRotation()
              .transformed(vm.Vector3(1, 0, 0))
              .length *
          modelRadius;

      (double, double) expectDistantSphere({
        required String name,
        required TitleDistantBody body,
        required vm.Vector3 relativeAu,
        required double modelRadius,
        required double renderDistance,
      }) {
        final camera = view().camera!;
        final center = node(name).globalTransform.getTranslation();
        final fromCamera = center - camera.position;
        final distance = fromCamera.length;
        final radius = equatorialWorldRadius(name, modelRadius);
        expect(distance, closeTo(renderDistance, 2e-4));
        expect(radius.isFinite, isTrue);
        expect(radius, greaterThan(0));
        expect(radius, lessThan(distance));
        expect(
          (fromCamera.normalized() - relativeAu.normalized()).length,
          lessThan(2e-6),
          reason: '$nameはカメラからの視線方向を保ち、火星中心起点の偽視差を作らない',
        );
        // 実geometryのworld半径とカメラ実距離を測り、描画scale算出APIを
        // 呼び直さずにAU/kmの角直径と比較する。glowや大気のboundsは含めない。
        final renderedDiameter = 2 * math.asin(radius / distance);
        final physicalDistance =
            relativeAu.length * TitleSolarSystemScale.kilometersPerAu;
        final physicalDiameter =
            2 * math.asin(body.equatorialRadiusKm / physicalDistance);
        final magnification = body == TitleDistantBody.sun
            ? 1.0
            : _planetAngularMagnification;
        final expectedDiameter = physicalDiameter * magnification;
        expect(
          renderedDiameter,
          closeTo(expectedDiameter, math.max(expectedDiameter * 1e-4, 1e-11)),
          reason: '$nameの角直径を$magnification倍で描き、最低pixel数で比率を崩さない',
        );
        return (renderedDiameter, physicalDiameter);
      }

      vm.Vector3 observerOffsetAu() {
        final marsCenter = node('title-mars').globalTransform.getTranslation();
        final marsRadius = equatorialWorldRadius('title-mars-surface', 3.1);
        return (view().camera!.position - marsCenter) *
            (TitleDistantBody.mars.equatorialRadiusKm /
                marsRadius /
                TitleSolarSystemScale.kilometersPerAu);
      }

      void expectDistantSizes() {
        expect(
          equatorialWorldRadius('title-mars-surface', 3.1),
          closeTo(8.06, 2e-5),
          reason: '遠景の大きさ調整で主火星の大きさを変えない',
        );
        final motion = TitleSceneMotion(sceneSeconds());
        final observerAu = observerOffsetAu();
        final diameters = <TitleDistantBody, (double, double)>{};
        for (final (name, body, relativeAu, modelRadius, renderDistance) in [
          (
            '白熱した太陽光球',
            TitleDistantBody.sun,
            motion.sunRelativeAu,
            1.0,
            TitleSceneMotion.sunDistance,
          ),
          (
            'title-earth-globe',
            TitleDistantBody.earth,
            motion.earthRelativeAu,
            3.1,
            TitleSceneMotion.earthDistance,
          ),
          (
            'title-jupiter-globe',
            TitleDistantBody.jupiter,
            motion.jupiterRelativeAu,
            1.0,
            TitleSceneMotion.jupiterDistance,
          ),
          (
            'title-saturn-globe',
            TitleDistantBody.saturn,
            motion.saturnRelativeAu,
            1.0,
            TitleSceneMotion.saturnDistance,
          ),
        ]) {
          diameters[body] = expectDistantSphere(
            name: name,
            body: body,
            relativeAu: relativeAu - observerAu,
            modelRadius: modelRadius,
            renderDistance: renderDistance,
          );
        }
        for (final (first, second) in [
          (TitleDistantBody.earth, TitleDistantBody.jupiter),
          (TitleDistantBody.jupiter, TitleDistantBody.saturn),
        ]) {
          final (firstRendered, firstPhysical) = diameters[first]!;
          final (secondRendered, secondPhysical) = diameters[second]!;
          final expectedRatio = firstPhysical / secondPhysical;
          expect(
            firstRendered / secondRendered,
            closeTo(expectedRatio, expectedRatio * 2e-4),
            reason: '3惑星は共通の角径倍率で見かけの比率を維持する',
          );
        }
        final rings = node('title-saturn-rings');
        final ringBounds = rings.combinedLocalBounds!;
        final outerRadius = (ringBounds.max.x - ringBounds.min.x) / 2;
        final ringWorldScale = rings.globalTransform
            .getRotation()
            .transformed(vm.Vector3(1, 0, 0))
            .length;
        expect(
          outerRadius *
              ringWorldScale /
              equatorialWorldRadius('title-saturn-globe', 1),
          closeTo(2.330901, 2e-5),
          reason: '土星は実球と環を同じ倍率で拡大し、環と本体の比率を維持する',
        );
      }

      void expectTransformUnchanged(
        List<double> actual,
        List<double> expected,
      ) {
        expect(actual.length, expected.length);
        for (var i = 0; i < actual.length; i++) {
          expect(actual[i], closeTo(expected[i], 2e-4));
        }
      }

      void expectOuterPlanetsPresent() {
        for (final name in ['title-jupiter', 'title-saturn']) {
          final planet = node(name);
          expect(planet.visible, isTrue, reason: '惑星の出没は画角と遮蔽で決まる');
          expect(planet.meshNodes, isNotEmpty, reason: '名前だけのノードでなく実モデルを持つ');
          expect(planet.combinedWorldBounds, isNotNull);
          final globe = node('$name-globe');
          expect(globe.visible, isTrue);
          expect(globe.meshNodes, isNotEmpty);
        }
        final rings = node('title-saturn-rings');
        expect(rings.visible, isTrue);
        expect(rings.meshNodes, isNotEmpty);
      }

      bool hasUnoccludedCenterInView(String name) {
        final planet = node(name);
        final camera = view().camera!;
        final viewport = tester.getSize(find.byType(TitleScene));
        final position = planet.globalTransform.getTranslation();
        final point = camera.worldToScreen(position, viewport);
        if (point == null ||
            !(Offset.zero & viewport).deflate(12).contains(point)) {
          return false;
        }
        // 火星中心を原点にした視線segment。画角内でも火星の裏なら撮らない。
        final marsCenter = node('title-mars').globalTransform.getTranslation();
        final cameraFromMars = camera.position - marsCenter;
        final ray = position - camera.position;
        final closest = (-cameraFromMars.dot(ray) / ray.length2)
            .clamp(0.0, 1.0)
            .toDouble();
        return (cameraFromMars + ray * closest).length2 > 8.14 * 8.14;
      }

      void expectPlanetPointState(String planetName) {
        final sceneView = view();
        final planet = node(planetName);
        final point = node('$planetName-glow');
        expect(point.meshNodes, isNotEmpty);
        expect(point.parent, same(sceneView.scene!.root));
        expect(point.parent, same(planet.parent), reason: '実球や環の子に光点を入れない');
        expect(sceneView.scene!.root.getChildByName('title-sun-glow'), isNull);
        expect(sceneView.scene!.root.getChildByName('title-mars-glow'), isNull);

        final camera = sceneView.camera! as fs.PerspectiveCamera;
        final viewport = tester.getSize(
          find.descendant(
            of: find.byType(TitleScene),
            matching: find.byType(fs.SceneView),
          ),
        );
        final pixelRatio = sceneView.pixelRatio ?? tester.view.devicePixelRatio;
        expect(pixelRatio, greaterThan(0));
        final modelRadius = planetName == 'title-earth' ? 3.1 : 1.0;
        final globeRadius = equatorialWorldRadius(
          '$planetName-globe',
          modelRadius,
        );
        final distance =
            (planet.globalTransform.getTranslation() - camera.position).length;
        final angularDiameter = 2 * math.asin(globeRadius / distance);
        final diameterRenderPixels =
            angularDiameter *
            viewport.height *
            pixelRatio /
            (2 * math.tan(camera.fovRadiansY / 2));
        final strength =
            (point.mesh!.primitives.first.material as fs.PreprocessedMaterial)
                .parameters
                .getFloat('strength');
        if (diameterRenderPixels >= 1.5) {
          expect(point.visible, isFalse, reason: '分解できる惑星に光点を重ねない');
          expect(strength, 0, reason: '非表示時は以前の光量を残さない');
          return;
        }
        // <=0.5pxはfull、0.5〜1.5pxはfade中。未分解のときだけ
        // PSFのsupportと自己深度を検査し、球や環を点の幅へ拡大しない。
        expect(point.visible, isTrue);
        expect(strength, greaterThan(0));
        expect(strength, lessThanOrEqualTo(1));
        final forward = (camera.target - camera.position).normalized();
        final outerRadiusRatio = switch (planetName) {
          'title-saturn' => 2.330901,
          'title-earth' => 1.025,
          _ => 1.0,
        };
        expect(
          (planet.globalTransform.getTranslation() -
                  point.globalTransform.getTranslation())
              .dot(forward),
          greaterThan(globeRadius * outerRadiusRatio * 1.01),
          reason: '画面平行な光点の面を実球・環の外接半径より手前へ置き自己遮蔽を防ぐ',
        );
        Offset project(double x, double y) {
          final screen = camera.worldToScreen(
            point.globalTransform.transformed3(vm.Vector3(x, y, 0)),
            viewport,
          );
          expect(screen, isNotNull);
          return screen!;
        }

        final left = project(-1, 0), right = project(1, 0);
        final bottom = project(0, -1), top = project(0, 1);
        // これはGaussianを描くquad全体のsupport幅5 render pxを測る。
        // FWHM 1 render pxや惑星本体の実角直径の検査とは区別する。
        final expectedLogicalSupport = 5 / pixelRatio;
        expect((right - left).distance, closeTo(expectedLogicalSupport, .05));
        expect((top - bottom).distance, closeTo(expectedLogicalSupport, .05));
        expect((right.dy - left.dy).abs(), lessThan(.02));
        expect((top.dx - bottom.dx).abs(), lessThan(.02));
      }

      void expectPlanetPointStates() {
        for (final name in ['title-earth', 'title-jupiter', 'title-saturn']) {
          expectPlanetPointState(name);
        }
      }

      double starAngle() => (view().scene!.skybox!.source as fs.PreprocessedSky)
          .parameters
          .getFloat('sky_yaw');

      Future<void> capture(String name) async {
        await wait(const Duration(milliseconds: 500));
        await binding.takeScreenshot(name);
      }

      Future<void> captureVisibleBodies(
        Map<String, String> captures, {
        int maxAttempts = 240,
      }) async {
        final pending = Map<String, String>.of(captures);
        // 実際のScene位置を見て撮るため、初期位相の微調整で黒背景や火星の
        // 背後だけを証拠画像にしない。両モデルはこの待機中も同時に存在する。
        for (
          var attempt = 0;
          attempt < maxAttempts && pending.isNotEmpty;
          attempt++
        ) {
          expectOuterPlanetsPresent();
          for (final name in pending.keys.toList()) {
            if (!hasUnoccludedCenterInView(name)) continue;
            await wait(const Duration(milliseconds: 100));
            if (!hasUnoccludedCenterInView(name)) continue;
            if (name == 'title-jupiter' || name == 'title-saturn') {
              expectPlanetPointState(name);
            }
            await binding.takeScreenshot(pending.remove(name)!);
          }
          if (pending.isNotEmpty) {
            await wait(const Duration(milliseconds: 250));
          }
        }
        expect(pending, isEmpty, reason: '指定天体の画角内・非遮蔽の時点を各1枚撮影する');
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
      final initialSurface = worldTransform(node('title-mars-surface'));
      final initialJupiter = nodePose('title-jupiter');
      final initialSaturn = nodePose('title-saturn');
      final initialJupiterAxes = worldAxes(node('title-jupiter-globe'));
      final initialSaturnAxes = worldAxes(node('title-saturn-globe'));
      final initialStars = starAngle();
      final initialSatellite = nodePose('title-satellite');
      expectOuterPlanetsPresent();
      expectDistantSizes();
      expectPlanetPointStates();
      await capture('title-ios-pristine');
      // ignore: avoid_print
      print('TITLE_VIDEO_READY');
      await captureVisibleBodies({
        'title-jupiter': 'title-ios-jupiter-visible',
        'title-saturn': 'title-ios-saturn-visible',
      });
      await wait(const Duration(seconds: 7));
      await capture('title-ios-passage');
      await wait(const Duration(seconds: 11));
      await capture('title-ios-pristine-motion');
      expect(cameraPose(), initialCamera, reason: 'タイトルの視点は時間で移動しない');
      expect(
        nodePose('title-mars'),
        isNot(initialMars),
        reason: '固定視点から火星の自転が見える',
      );
      expect(
        worldTransform(node('title-mars-surface')),
        isNot(initialSurface),
        reason: '実際に描画する地表のworld変換が進む',
      );
      expect(node('title-mars').position.storage, initialMars.take(3));
      expect(node('title-mars').scale.storage, initialMars.skip(7));
      expectOuterPlanetsPresent();
      expectDistantSizes();
      expectPlanetPointStates();
      expect(nodePose('title-jupiter'), isNot(initialJupiter));
      expect(nodePose('title-saturn'), isNot(initialSaturn));
      expect(worldAxes(node('title-jupiter-globe')), isNot(initialJupiterAxes));
      expect(worldAxes(node('title-saturn-globe')), isNot(initialSaturnAxes));
      expect(starAngle(), isNot(initialStars));
      expect(nodePose('title-satellite'), isNot(initialSatellite));
      final marsCenter = view().scene!.root
          .getChildByName('title-mars')!
          .position;
      final camera = view().camera!;
      final viewport = tester.getSize(find.byType(TitleScene));
      final observerAu = observerOffsetAu();
      for (final (relativeAuAt, renderDistance) in [
        (
          (TitleSceneMotion motion) => motion.sunRelativeAu,
          TitleSceneMotion.sunDistance,
        ),
        (
          (TitleSceneMotion motion) => motion.earthRelativeAu,
          TitleSceneMotion.earthDistance,
        ),
      ]) {
        var inside = 0;
        var outside = 0;
        for (var seconds = 0.0; seconds < 360; seconds += 5) {
          final relativeAu =
              relativeAuAt(TitleSceneMotion(seconds)) - observerAu;
          final point = camera.worldToScreen(
            camera.position + relativeAu.normalized() * renderDistance,
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
      await captureVisibleBodies({
        'title-sun': 'title-ios-orbital-phase',
      }, maxAttempts: 300);
      expect(nodePose('title-sun'), isNot(initialSun));
      expectDistantSizes();
      expectPlanetPointStates();
      expect(cameraPose(), initialCamera);
      expect(nodePose('title-mars'), isNot(initialMars));
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
      final surface = node('title-mars-surface');
      final settlements = node('title-mars-settlements');
      expect(
        settlements.meshNodes,
        isNotEmpty,
        reason: '発展fixtureの地表に実際の施設描画がある',
      );
      final facility = settlements.meshNodes.first;
      final surfaceBefore = worldTransform(surface);
      final facilityBefore = worldTransform(facility);
      final facilityRelativeToSurface = relativeTransform(surface, facility);
      final bounds = facility.combinedLocalBounds!;
      final facilityProbe = (bounds.min + bounds.max) * .5;
      final facilityWorldBefore = facility.globalTransform.transformed3(
        facilityProbe,
      );
      final developedEarth = nodePose('title-earth-globe');
      expectDistantSizes();
      expectPlanetPointStates();
      await capture('title-ios-developed');
      await wait(const Duration(seconds: 18));
      await capture('title-ios-developed-motion');
      expect(cameraPose(), developedCamera);
      expect(nodePose('title-mars'), isNot(developedMars));
      expect(worldTransform(surface), isNot(surfaceBefore));
      expect(worldTransform(facility), isNot(facilityBefore));
      expect(
        (facility.globalTransform.transformed3(facilityProbe) -
                facilityWorldBefore)
            .length,
        greaterThan(.01),
        reason: '地表の施設を描く実geometryもworld空間で移動する',
      );
      expectTransformUnchanged(
        relativeTransform(surface, facility),
        facilityRelativeToSurface,
      );
      expectOuterPlanetsPresent();
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
      for (final name in [
        'title-earth-glow',
        'title-jupiter-glow',
        'title-saturn-glow',
      ]) {
        expect(
          globe.scene!.root.getChildByName(name),
          isNull,
          reason: '光点はタイトル専用',
        );
      }
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
