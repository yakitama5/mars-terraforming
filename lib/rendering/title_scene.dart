import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'title_celestial_models.dart';
import 'title_cosmos_models.dart';
import 'title_gas_giant_models.dart';
import 'title_spacecraft_models.dart';
import 'title_scene_motion.dart';
import 'title_scene_snapshot.dart';

/// 火星の地形の自転と、その周囲を巡る宇宙を固定した構図で望むタイトル。
class TitleScene extends StatefulWidget {
  const TitleScene({
    super.key,
    required this.snapshot,
    this.onReady,
    this.onError,
  });

  final TitleSceneSnapshot snapshot;
  final VoidCallback? onReady;
  final ValueChanged<Object>? onError;

  @override
  State<TitleScene> createState() => _TitleSceneState();
}

class _TitleSceneState extends State<TitleScene>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  fs.Scene? _scene;
  TitleCelestialModels? _models;
  TitleCosmosModels? _cosmos;
  TitleGasGiantModels? _giants;
  late TitleSceneSnapshot _displayedSnapshot;
  TitleMarsModel? _mars;
  vm.Quaternion _marsOrientation = vm.Quaternion.identity();
  fs.Node? _earth, _earthGlobe, _sun, _sunGlobe, _rocket, _satellite;
  fs.Node? _jupiter, _saturn;
  final _asteroids = <fs.Node>[];
  late final Ticker _ticker;
  Duration? _lastTick;
  double _seconds = 0;
  bool _active = true;
  bool _reduceMotion = false;
  bool _failed = false;
  int _generation = 0;
  static final _cameraPosition = vm.Vector3(0, 1, 14);
  static final _marsPosition = vm.Vector3(0, -7.4, 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_tick);
    _initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncTicker();
  }

  void _syncTicker() {
    final shouldTick =
        _active &&
        !_reduceMotion &&
        _scene != null &&
        TickerMode.valuesOf(context).enabled;
    if (shouldTick && !_ticker.isActive) {
      _lastTick = null;
      _ticker.start();
    } else if (!shouldTick && _ticker.isActive) {
      _ticker.stop();
      _lastTick = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _syncTicker();
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    fs.Scene? pending;
    try {
      await fs.Scene.initializeStaticResources();
      if (!mounted || generation != _generation) return;
      final resources = await Future.wait<Object>([
        TitleCelestialModels.load(),
        TitleCosmosModels.load(),
        TitleSpacecraftModels.load(),
        TitleGasGiantModels.load(),
      ]);
      if (!mounted || generation != _generation) return;
      pending = fs.Scene();
      final models = resources[0] as TitleCelestialModels;
      final cosmos = resources[1] as TitleCosmosModels;
      final spacecraft = resources[2] as TitleSpacecraftModels;
      final giants = resources[3] as TitleGasGiantModels;
      _models = models;
      _cosmos = cosmos;
      _giants = giants;
      _displayedSnapshot = widget.snapshot;
      _mars = models.mars(widget.snapshot);
      _marsOrientation = _mars!.root.rotation.clone();
      _mars!.root
        ..name = 'title-mars'
        ..position = _marsPosition
        ..scale = vm.Vector3.all(2.6);
      _earth = models.earth()
        ..name = 'title-earth'
        ..position = vm.Vector3(-17, 5.8, -22)
        ..scale = vm.Vector3.all(1.05);
      _earthGlobe = _earth!.getChildByName('title-earth-globe');
      _rocket = spacecraft.rocket
        ..name = 'title-rocket'
        ..scale = vm.Vector3.all(.035);
      _satellite = spacecraft.satellite
        ..name = 'title-satellite'
        ..scale = vm.Vector3.all(.045);
      _sun = cosmos.sun(radius: 1.1)..name = 'title-sun';
      _sunGlobe = _sun!.getChildByName('白熱した太陽光球');
      _jupiter = giants.jupiter()..scale = vm.Vector3.all(5.2);
      _saturn = giants.saturn()..scale = vm.Vector3.all(3.8);
      for (final node in [
        _mars!.root,
        _earth!,
        _sun!,
        _jupiter!,
        _saturn!,
        _rocket!,
        _satellite!,
      ]) {
        pending.add(node);
      }
      for (var i = 0; i < 2; i++) {
        final node =
            (i == 0 ? spacecraft.asteroid : spacecraft.asteroid.clone())
              ..scale = vm.Vector3.all(.045 + i * .015);
        _asteroids.add(node);
        pending.add(node);
      }
      pending.environmentSettings = fs.EnvironmentSettings(
        environment: cosmos.environment,
        skybox: cosmos.skybox,
        environmentIntensity: .30,
        toneMapping: fs.ToneMappingMode.aces,
        exposure: .95,
        bloomEnabled: true,
        bloomThreshold: 1.05,
        bloomIntensity: .25,
        bloomScatter: .82,
        lensFlareEnabled: true,
        lensFlareIntensity: .15,
        lensFlareGhostCount: 3,
        lensFlareHaloIntensity: .12,
        vignetteEnabled: true,
        vignetteIntensity: .19,
        vignetteRadius: .9,
        colorGradingEnabled: true,
        contrast: 1.05,
        saturation: 1.03,
        ambientOcclusionEnabled: true,
        ambientOcclusionMethod: fs.AmbientOcclusionMethod.groundTruth,
        ambientOcclusionRadius: .15,
        ambientOcclusionIntensity: .6,
        ambientOcclusionHalfResolution: true,
      );
      pending.antiAliasingMode = fs.AntiAliasingMode.smaa;
      pending.directionalLight = fs.DirectionalLight(
        color: vm.Vector3(1, .94, .85),
        intensity: 4.0,
        castsShadow: true,
        cacheStaticShadows: false,
        shadowCascadeCount: 1,
        shadowMapResolution: 2048,
        shadowMaxDistance: 70,
        shadowDepthBias: .003,
        shadowNormalBias: .01,
        shadowSoftness: .05,
      );
      final fill = fs.Node(name: '地球照を思わせる淡い機体の補助光')
        ..addComponent(
          fs.DirectionalLightComponent.aimed(
            fs.DirectionalLight(color: vm.Vector3(.45, .66, 1), intensity: .35),
            vm.Vector3(-.2, -.3, -1),
          ),
        );
      pending.add(fill);
      _scene = pending;
      _animate();
      setState(() => _failed = false);
      _syncTicker();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation) widget.onReady?.call();
      });
    } catch (error, stack) {
      pending?.removeAll();
      pending?.dispose();
      _scene = null;
      _clearModelReferences();
      debugPrint('Title scene initialization: $error\n$stack');
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onError?.call(error);
    }
  }

  @override
  void didUpdateWidget(covariant TitleScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    final scene = _scene, models = _models, mars = _mars;
    if (scene == null ||
        models == null ||
        mars == null ||
        _displayedSnapshot.hasSameModel(widget.snapshot)) {
      return;
    }
    // 施設完成など外観の変化があったときだけメッシュを差し替える。
    final updated = models.mars(widget.snapshot);
    _marsOrientation = updated.root.rotation.clone();
    updated.root
      ..name = 'title-mars'
      ..position = mars.root.position
      ..scale = mars.root.scale;
    scene.remove(mars.root);
    scene.add(updated.root);
    _mars = updated;
    _displayedSnapshot = widget.snapshot;
    _animate();
  }

  void _tick(Duration elapsed) {
    final previous = _lastTick;
    if (previous == null) {
      _lastTick = elapsed;
      return;
    }
    final delta = elapsed - previous;
    // 30fpsに制限し、OS復帰直後の巨大な差分を宇宙へ適用しない。
    if (delta.inMicroseconds < 33333) return;
    _lastTick = elapsed;
    _seconds += math.min(delta.inMicroseconds / 1000000, .1);
    _animate();
    setState(() {});
  }

  void _animate() {
    final motion = TitleSceneMotion(_seconds);
    _mars?.root.rotation = motion.marsRotation(_marsOrientation);
    final sunPosition = _marsPosition + motion.sunOffset;
    final sunFacing = vm.Quaternion.fromTwoVectors(
      vm.Vector3(0, 0, 1),
      (_cameraPosition - sunPosition).normalized(),
    );
    _cosmos?.update(
      _seconds,
      skyYaw: motion.starAngle,
      bodyTilt: -TitleSceneMotion.cameraFrameTilt,
    );
    _sun
      ?..position = sunPosition
      ..rotation = sunFacing;
    _sunGlobe?.rotation = sunFacing.conjugated() * motion.sunRotation;
    // 遠景の位置と地表の明暗を同じ太陽方向で動かす。
    // 既存のlightを更新し、毎フレームcomponentや影atlasを作り直さない。
    _scene?.directionalLight?.direction = -motion.sunDirection;
    _earth?.position = _marsPosition + motion.earthOffset;
    _models?.updateView(
      cameraPosition: _cameraPosition,
      sunDirection: motion.sunDirection,
      sunPosition: sunPosition,
      seconds: _seconds,
      inertialToView: motion.inertialToCamera,
    );
    _earthGlobe?.rotation = motion.earthRotation;
    _jupiter
      ?..position = _marsPosition + motion.jupiterOffset
      ..rotation = motion.jupiterRotation;
    _saturn
      ?..position = _marsPosition + motion.saturnOffset
      ..rotation = motion.saturnRotation;
    _giants?.updateView(
      sunPosition: sunPosition,
      cameraPosition: _cameraPosition,
    );
    final satellite = motion.satellite;
    _satellite
      ?..position = _marsPosition + satellite.position
      ..rotation = satellite.orientation;
    final rocket = motion.rocket;
    _rocket
      ?..position = _marsPosition + rocket.position
      ..rotation = rocket.orientation;
    for (var i = 0; i < _asteroids.length; i++) {
      final orbit = motion.asteroid(i);
      _asteroids[i]
        ..position = _marsPosition + orbit.position
        ..rotation =
            orbit.orientation *
            vm.Quaternion.euler(_seconds * .2, _seconds * .17, .4);
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _scene?.removeAll();
    _scene?.dispose();
    _scene = null;
    _clearModelReferences();
    super.dispose();
  }

  void _clearModelReferences() {
    _models = null;
    _cosmos = null;
    _giants = null;
    _mars = null;
    _earth = null;
    _earthGlobe = null;
    _sun = null;
    _sunGlobe = null;
    _jupiter = null;
    _saturn = null;
    _rocket = null;
    _satellite = null;
    _asteroids.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scene = _scene;
    if (scene == null) {
      return ColoredBox(
        color: const Color(0xff030812),
        child: _failed
            ? const Align(
                alignment: Alignment(0, .55),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '宇宙の表示を準備できませんでした。\nタップしてゲームを始められます。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xffb3b9bf)),
                  ),
                ),
              )
            : null,
      );
    }
    return RepaintBoundary(
      child: ClipRect(
        child: Semantics(
          image: true,
          label: '星空と地球・木星・土星を望む、自転する峡谷と極冠のある火星。探査機と衛星が宇宙を航行する。',
          child: ExcludeSemantics(
            child: fs.SceneView(
              scene,
              camera: fs.PerspectiveCamera(
                position: _cameraPosition,
                target: vm.Vector3(0, 1.8, 0),
                fovRadiansY: 43 * math.pi / 180,
                fovNear: .25,
                fovFar: 240,
              ),
              autoTick: false,
              pixelRatio: MediaQuery.devicePixelRatioOf(context)
                  .clamp(1, 2.0)
                  .toDouble(),
            ),
          ),
        ),
      ),
    );
  }
}
