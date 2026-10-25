import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'title_celestial_models.dart';
import 'title_cosmos_models.dart';
import 'title_spacecraft_models.dart';
import 'title_scene_motion.dart';
import 'title_scene_snapshot.dart';

/// 火星の姿勢とカメラを固定し、その周囲の宇宙だけが動くタイトル。
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
  late TitleSceneSnapshot _displayedSnapshot;
  TitleMarsModel? _mars;
  fs.Node? _earth, _earthGlobe, _rocket, _satellite;
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
  static final _sunPosition = vm.Vector3(11, 5.5, -8);
  static final _sunDirection = (_sunPosition - _marsPosition).normalized();

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
      ]);
      if (!mounted || generation != _generation) return;
      pending = fs.Scene();
      final models = resources[0] as TitleCelestialModels;
      final cosmos = resources[1] as TitleCosmosModels;
      final spacecraft = resources[2] as TitleSpacecraftModels;
      _models = models;
      _cosmos = cosmos;
      _displayedSnapshot = widget.snapshot;
      _mars = models.mars(widget.snapshot);
      _mars!.root
        ..name = 'title-mars'
        ..position = _marsPosition
        ..scale = vm.Vector3.all(2.6);
      _earth = models.earth()
        ..name = 'title-earth'
        ..position = vm.Vector3(-17, 5.8, -22)
        ..scale = vm.Vector3.all(.70);
      _earthGlobe = _earth!.getChildByName('title-earth-globe');
      _rocket = spacecraft.rocket
        ..name = 'title-rocket'
        ..scale = vm.Vector3.all(.30);
      _satellite = spacecraft.satellite
        ..name = 'title-satellite'
        ..scale = vm.Vector3.all(.24);
      final sun = cosmos.sun(radius: .32)
        ..position = _sunPosition
        ..rotation = vm.Quaternion.fromTwoVectors(
          vm.Vector3(0, 0, 1),
          (_cameraPosition - _sunPosition).normalized(),
        );
      for (final node in [_mars!.root, _earth!, sun, _rocket!, _satellite!]) {
        pending.add(node);
      }
      for (var i = 0; i < 2; i++) {
        final node =
            (i == 0 ? spacecraft.asteroid : spacecraft.asteroid.clone())
              ..scale = vm.Vector3.all(.17 + i * .11);
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
        direction: -_sunDirection,
        color: vm.Vector3(1, .94, .85),
        intensity: 4.0,
        castsShadow: true,
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
    _cosmos?.update(_seconds);
    _models?.updateView(
      cameraPosition: _cameraPosition,
      sunDirection: _sunDirection,
      sunPosition: _sunPosition,
      seconds: _seconds,
    );
    _earthGlobe?.rotation = vm.Quaternion.axisAngle(
      vm.Vector3(0, 1, .15),
      motion.earthAngle - 2.1,
    );
    final orbit = motion.satelliteAngle - .6;
    _satellite
      ?..position = vm.Vector3(
        math.sin(orbit) * 11.2,
        -3.2 + math.cos(orbit) * 4,
        math.cos(orbit) * 9.3,
      )
      ..rotation = vm.Quaternion.euler(.9 - orbit, -.35, -.2);
    final rocket = motion.rocket;
    _rocket?.visible = rocket != null;
    if (rocket != null) {
      _rocket
        ?..position = vm.Vector3(
          -11 + rocket * 22,
          -.3 + math.sin(rocket * math.pi) * 1.0,
          3,
        )
        ..rotation = vm.Quaternion.euler(0, .3, -1.35);
    }
    for (var i = 0; i < _asteroids.length; i++) {
      final progress = motion.asteroid(i);
      final asteroid = _asteroids[i]..visible = progress != null;
      if (progress != null) {
        asteroid
          ..position = vm.Vector3(
            14 - progress * 29,
            4.5 - progress * 5.5 + i * .7,
            -1 + i * 3.0,
          )
          ..rotation = vm.Quaternion.euler(_seconds * .2, _seconds * .17, .4);
      }
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
    _models = null;
    _cosmos = null;
    _mars = null;
    _earth = null;
    _earthGlobe = null;
    _rocket = null;
    _satellite = null;
    _asteroids.clear();
    super.dispose();
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
          label: '星空と地球を望む、峡谷と極冠のある火星。探査機と衛星が宇宙を航行する。',
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
