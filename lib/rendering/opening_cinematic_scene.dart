import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'opening_cinematic_models.dart';

/// 親の再生位置だけで描画する5章の3Dオープニング。
///
/// 0–.2: 都市、.2–.4: 打上、.4–.6: 月、.6–.8: 探査、.8–1: 移住。
/// 自動再生・保存・画面遷移を持たず、巻き戻しも同じ姿勢を再現する。
class OpeningCinematicScene extends StatefulWidget {
  const OpeningCinematicScene({
    super.key,
    required this.progress,
    this.onReady,
    this.onError,
  });

  final double progress;
  final VoidCallback? onReady;
  final ValueChanged<Object>? onError;

  @override
  State<OpeningCinematicScene> createState() => _OpeningCinematicSceneState();
}

class _OpeningCinematicSceneState extends State<OpeningCinematicScene> {
  fs.Scene? _scene;
  OpeningCinematicModels? _models;
  final _skies = <fs.Skybox>[];
  final _lights = <fs.DirectionalLight>[];

  double get _progress =>
      widget.progress.isFinite ? widget.progress.clamp(0.0, 1.0) : 0;
  int get _chapter => math.min(4, (_progress * 5).floor());
  double get _chapterProgress => (_progress * 5 - _chapter).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    fs.Scene? pending;
    try {
      await fs.Scene.initializeStaticResources();
      if (!mounted) return;
      pending = fs.Scene();
      final models = OpeningCinematicModels();
      for (final root in models.roots) {
        pending.add(root);
      }
      pending.ambientOcclusion
        ..enabled = true
        ..radius = .24
        ..intensity = .65
        ..power = 1.1
        ..halfResolution = true;
      for (var i = 0; i < 5; i++) {
        final moon = i == 2;
        final mars = i >= 3;
        final evening = i == 4;
        _skies.add(
          fs.Skybox(
            fs.GradientSkySource(
              zenithColor: moon
                  ? vm.Vector3(.0005, .001, .003)
                  : mars
                  ? vm.Vector3(.075, .045, .055)
                  : vm.Vector3(.015, .07, .15),
              horizonColor: moon
                  ? vm.Vector3(.002, .003, .006)
                  : evening
                  ? vm.Vector3(.30, .13, .075)
                  : mars
                  ? vm.Vector3(.46, .25, .15)
                  : vm.Vector3(.56, .36, .23),
              groundColor: moon
                  ? vm.Vector3(.025, .03, .04)
                  : mars
                  ? vm.Vector3(.11, .055, .035)
                  : vm.Vector3(.045, .07, .08),
              sunDirection: moon
                  ? vm.Vector3(.45, .45, .8)
                  : vm.Vector3(-.6, .12, -.8),
              sunColor: moon
                  ? vm.Vector3(.8, .9, 1.05)
                  : vm.Vector3(2.1, 1.25, .62),
              sunSharpness: moon ? 1400 : 800,
            ),
          ),
        );
        _lights.add(
          fs.DirectionalLight(
            direction: moon
                ? vm.Vector3(-.45, -.45, -.8)
                : vm.Vector3(.55, -.45, .65),
            color: moon ? vm.Vector3(.83, .9, 1) : vm.Vector3(1, .83, .65),
            intensity: moon
                ? 2.9
                : evening
                ? 1.05
                : 2.1,
            castsShadow: true,
            cacheStaticShadows: false,
            shadowCascadeCount: 1,
            shadowMaxDistance: 65,
            shadowMapResolution: 1024,
            shadowSoftness: .06,
            // 月の強い斜光で曲面の自己シャドウが縞にならないよう補正する。
            shadowDepthBias: moon ? .02 : .006,
            shadowNormalBias: moon ? .04 : .015,
            shadowAmbientStrength: .24,
          ),
        );
      }
      _scene = pending;
      _models = models;
      _synchronize();
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scene != null) widget.onReady?.call();
      });
    } catch (error, stack) {
      pending?.removeAll();
      pending?.dispose();
      debugPrint('Opening cinematic initialization: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _scene = null;
        _models = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onError?.call(error);
      });
    }
  }

  void _synchronize() {
    final scene = _scene, models = _models;
    if (scene == null || models == null) return;
    final chapter = _chapter, progress = _chapterProgress;
    models.update(chapter, progress);
    scene.skybox = _skies[chapter];
    scene.directionalLight = _lights[chapter];
    scene.environmentIntensity = chapter == 2
        ? .45
        : chapter == 4
        ? .44
        : .60;
    final sky = _skies[chapter].source as fs.GradientSkySource;
    // 大気のある場面だけ、遠い地表を空の色へ溶かす。月面は真空を保つ。
    scene.fog
      ..enabled = chapter != 2
      ..mode = fs.FogMode.linear
      ..start = 45
      ..end = 155
      ..color = sky.horizonColor
      ..maxOpacity = 1;
    if (chapter == 0) {
      final dawn = OpeningCinematicModels.ease(progress);
      final sky = _skies[0].source as fs.GradientSkySource;
      sky.sunDirection = vm.Vector3(-.6, .05 + dawn * .13, -.8);
      _lights[0]
        ..direction = vm.Vector3(.6, -.22 - dawn * .28, .8)
        ..intensity = 1.4 + dawn * .9;
    }
  }

  @override
  void didUpdateWidget(covariant OpeningCinematicScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    _synchronize();
  }

  @override
  void dispose() {
    _scene?.removeAll();
    _scene?.dispose();
    _scene = null;
    _models = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = _scene, models = _models;
    if (scene == null || models == null) {
      return const ColoredBox(color: Color(0xff07131f));
    }
    return ClipRect(
      child: Semantics(
        image: true,
        label: const [
          '朝日に照らされた都市の建設',
          '炎を上げて飛び立つロケット',
          '地球を望む月面基地',
          '赤い山稜を進む六輪探査車',
          'ドームと温室に明かりが灯る火星の街',
        ][_chapter],
        child: ExcludeSemantics(
          child: fs.SceneView(
            scene,
            camera: models.camera(_chapter, _chapterProgress),
            // 親のprogress更新でだけ描画。停止中の内部Tickerも作らない。
            autoTick: false,
            pixelRatio: MediaQuery.devicePixelRatioOf(context).clamp(1.0, 1.5),
          ),
        ),
      ),
    );
  }
}
