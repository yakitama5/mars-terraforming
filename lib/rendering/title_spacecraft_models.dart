import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

typedef SpacecraftSceneLoader = Future<fs.Node> Function(String sourcePath);

/// NASAの詳細モデルをタイトルの座標へ整える。
/// 取得・変換は開発時だけ行い、実行時はビルド済みの端末内素材を読む。
class TitleSpacecraftModels {
  const TitleSpacecraftModels({
    required this.satellite,
    required this.rocket,
    required this.asteroid,
  });

  static const satelliteAsset = 'assets/title/spacecraft/nasa_mro.glb';
  static const rocketAsset = 'assets/title/spacecraft/nasa_saturn_v.glb';
  static const asteroidAsset = 'assets/title/spacecraft/nasa_bennu.glb';

  /// 軌道・回転は呼出側がこの根へ適用する。内部の中心補正は独立させる。
  final fs.Node satellite;
  final fs.Node rocket;
  final fs.Node asteroid;

  static Future<TitleSpacecraftModels> load({
    SpacecraftSceneLoader? loader,
  }) async {
    final loadScene = loader ?? fs.loadScene;
    final loaded = await Future.wait([
      loadScene(satelliteAsset),
      loadScene(rocketAsset),
      loadScene(asteroidAsset),
    ]);
    // 低い宇宙の拡散光と別に、曲がった断熱箔やセルへ広い反射光を与える。
    // 元の色画像・UV・形状は保ち、タイトルの美術照明だけを調整する。
    final reflections = fs.EnvironmentMap.studio();
    for (final source in loaded.take(2)) {
      for (final node in source.meshNodes) {
        for (final primitive in node.mesh!.primitives) {
          final material = primitive.material;
          if (material is fs.PhysicallyBasedMaterial) {
            material.environment = reflections;
            material.specular = math.max(.55, material.specular);
          }
        }
      }
    }
    return TitleSpacecraftModels(
      satellite: _normalize(
        loaded[0],
        name: 'nasa-mro',
        extent: 6,
        // 原素材は太陽電池の長手がZ。翼を横へ開いた姿勢で見せる。
        orientation: vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), math.pi / 2),
      ),
      rocket: _normalize(loaded[1], name: 'nasa-saturn-v', extent: 8),
      asteroid: _normalize(loaded[2], name: 'nasa-bennu', extent: 2),
    );
  }

  static fs.Node _normalize(
    fs.Node source, {
    required String name,
    required double extent,
    vm.Quaternion? orientation,
  }) {
    // 読込直後の根に変換が残っていても、その姿勢を含めて中心化する。
    final bounds = source.combinedWorldBounds;
    if (bounds == null) {
      throw StateError('$nameの造形範囲を確認できませんでした');
    }
    final size = bounds.max - bounds.min;
    final longest = math.max(size.x, math.max(size.y, size.z));
    if (!longest.isFinite || longest <= 0) {
      throw StateError('$nameの造形範囲が不正です');
    }
    final center = (bounds.min + bounds.max) * .5;
    if (!center.x.isFinite || !center.y.isFinite || !center.z.isFinite) {
      throw StateError('$nameの中心が不正です');
    }
    final centered = fs.Node(name: '$name-centering')
      ..position = -center
      ..add(source);
    final normalized = fs.Node(name: '$name-scale')
      ..scale = vm.Vector3.all(extent / longest)
      ..add(centered);
    final facing = fs.Node(name: '$name-orientation')
      ..rotation = orientation ?? vm.Quaternion.identity()
      ..add(normalized);
    return fs.Node(name: '$name-pivot')..add(facing);
  }
}
