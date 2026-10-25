import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'title_scene_models.dart';
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
  TitleSceneModels? _models;
  late TitleSceneSnapshot _displayedSnapshot;
  TitleMarsModel? _mars;
  fs.Node? _stars, _earth, _earthGlobe, _rocket, _satellite;
  final _asteroids = <fs.Node>[];
  late final Ticker _ticker;
  Duration? _lastTick;
  double _seconds = 0;
  bool _active = true;
  bool _reduceMotion = false;
  bool _failed = false;
  int _generation = 0;

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
      pending = fs.Scene();
      final models = TitleSceneModels();
      _models = models;
      _displayedSnapshot = widget.snapshot;
      _mars = models.mars(
        greening: widget.snapshot.greenery,
        cloudCover: widget.snapshot.cloudCoverage,
        settlementCount: widget.snapshot.settlementCount,
        infrastructureCount: widget.snapshot.infrastructureCount,
        activity: widget.snapshot.activity,
        atmosphere: widget.snapshot.atmosphere,
      );
      _mars!.root
        ..name = 'title-mars'
        ..position = vm.Vector3(0, -5.0, 0)
        ..scale = vm.Vector3.all(1.9);
      _orientLimb(_mars!);
      _stars = models.stars()..name = 'title-stars';
      _earth = models.earth()
        ..name = 'title-earth'
        ..position = vm.Vector3(12.5, 5.0, -24)
        ..scale = vm.Vector3.all(.42);
      _earthGlobe = _earth!.getChildByName('title-earth-globe');
      _earth!
          .getChildByName('title-earth-limb')
          ?.rotation = vm.Quaternion.fromTwoVectors(
        vm.Vector3(0, 0, 1),
        vm.Vector3(-12.5, -4, 38).normalized(),
      );
      _rocket = models.rocket()
        ..name = 'title-rocket'
        ..scale = vm.Vector3.all(.27);
      _satellite = models.satellite()
        ..name = 'title-satellite'
        ..scale = vm.Vector3.all(.32);
      final sun = models.sun()
        ..position = vm.Vector3(-18, 8, -32)
        ..scale = vm.Vector3.all(.7);
      for (final node in [
        _mars!.root,
        _stars!,
        _earth!,
        sun,
        _rocket!,
        _satellite!,
      ]) {
        pending.add(node);
      }
      for (var i = 0; i < 2; i++) {
        final node = models.asteroid(i + 13)
          ..scale = vm.Vector3.all(.28 + i * .13);
        _asteroids.add(node);
        pending.add(node);
      }
      pending.skybox = fs.Skybox(
        fs.GradientSkySource(
          zenithColor: vm.Vector3(.00035, .0007, .002),
          horizonColor: vm.Vector3(.002, .004, .01),
          groundColor: vm.Vector3(.0003, .0005, .0012),
          sunColor: vm.Vector3.zero(),
        ),
      );
      pending.environmentIntensity = .19;
      pending.directionalLight = fs.DirectionalLight(
        direction: vm.Vector3(.65, -.45, -.65),
        color: vm.Vector3(1, .83, .68),
        intensity: 2.5,
        castsShadow: false,
      );
      pending.postProcess.bloom
        ..enabled = true
        ..threshold = 1.1
        ..intensity = .15
        ..scatter = .65;
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
    final updated = models.mars(
      greening: widget.snapshot.greenery,
      cloudCover: widget.snapshot.cloudCoverage,
      settlementCount: widget.snapshot.settlementCount,
      infrastructureCount: widget.snapshot.infrastructureCount,
      activity: widget.snapshot.activity,
      atmosphere: widget.snapshot.atmosphere,
    );
    updated.root
      ..name = 'title-mars'
      ..position = mars.root.position
      ..scale = mars.root.scale;
    _orientLimb(updated);
    scene.remove(mars.root);
    scene.add(updated.root);
    _mars = updated;
    _displayedSnapshot = widget.snapshot;
    _animate();
  }

  void _orientLimb(TitleMarsModel mars) {
    mars.limb
      ..rotation = vm.Quaternion.fromTwoVectors(
        vm.Vector3(0, 0, 1),
        vm.Vector3(0, 6, 14).normalized(),
      )
      ..scale = vm.Vector3.all(1.085);
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
    _stars?.rotation = vm.Quaternion.axisAngle(
      vm.Vector3(0, 0, 1),
      motion.starAngle,
    );
    _earthGlobe?.rotation = vm.Quaternion.axisAngle(
      vm.Vector3(0, 1, .15),
      motion.earthAngle,
    );
    _mars?.clouds.rotation = vm.Quaternion.axisAngle(
      vm.Vector3(0, 1, 0),
      motion.cloudAngle,
    );
    final orbit = motion.satelliteAngle;
    _satellite
      ?..position = vm.Vector3(
        math.sin(orbit) * 7.8,
        -2.7 + math.cos(orbit) * 2.6,
        math.cos(orbit) * 7.2,
      )
      ..rotation = vm.Quaternion.euler(-orbit, .9, -.2);
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
    _models = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = _scene;
    if (scene == null) {
      return ColoredBox(
        color: const Color(0xff030812),
        child: _failed
            ? const Center(
                child: Text(
                  '宇宙の表示を準備できませんでした。\nタップしてゲームを始められます。',
                  textAlign: TextAlign.center,
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
                position: vm.Vector3(0, 1, 14),
                target: vm.Vector3(0, 1.8, 0),
                fovRadiansY: 43 * math.pi / 180,
                fovFar: 240,
              ),
              autoTick: false,
              pixelRatio: MediaQuery.devicePixelRatioOf(context)
                  .clamp(1, 1.5)
                  .toDouble(),
            ),
          ),
        ),
      ),
    );
  }
}
