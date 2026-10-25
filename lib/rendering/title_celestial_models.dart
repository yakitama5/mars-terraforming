import 'dart:math' as math;

import 'package:flutter/material.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'opening_cinematic_geometry.dart';
import 'planet_geometry.dart';
import 'title_planet_geometry.dart';
import 'title_scene_snapshot.dart';

class TitleMarsModel {
  const TitleMarsModel({
    required this.root,
    required this.surface,
    required this.clouds,
    required this.settlements,
    required this.limb,
  });

  final fs.Node root, surface, clouds, settlements, limb;
}

/// NASAのカラー・標高・昼夜・雲を、タイトル専用の材質で描く。
/// 時間進行も保存処理も持たず、開発の見た目だけを受け取る。
class TitleCelestialModels {
  TitleCelestialModels._(this._height, this._textures, this._materials) {
    final textures = _textures;
    _texture(_marsSurface, 'albedo_map', textures[0]);
    _texture(_marsSurface, 'normal_map', textures[1]);
    _texture(_earthSurface, 'day_map', textures[2]);
    _texture(_earthSurface, 'night_map', textures[3]);
    _texture(_earthCloudMaterial, 'cloud_map', textures[4]);
    _texture(_marsCloudMaterial, 'cloud_map', textures[4]);
    _marsAtmosphere.parameters
      ..setVec3('scatter_color', vm.Vector3(.38, .19, .10))
      ..setFloat('density', .43)
      ..setFloat('intensity', 1.05);
    _earthAtmosphere.parameters
      ..setVec3('scatter_color', vm.Vector3(.10, .30, .72))
      ..setFloat('density', .85)
      ..setFloat('intensity', 1.35);
    _earthCloudMaterial.parameters.setFloat('opacity', .9);
  }

  final MeasuredPlanetHeightField _height;
  // GPU画像への参照をシーンの寿命まで保持する。
  final List<fs.Texture2D> _textures;
  int get textureCount => _textures.length;
  final List<fs.PreprocessedMaterial> _materials;
  final _cloudNodes = <(fs.Node, bool)>[];
  fs.Node? _earthRoot;
  fs.PreprocessedMaterial get _marsSurface => _materials[0];
  fs.PreprocessedMaterial get _earthSurface => _materials[1];
  fs.PreprocessedMaterial get _marsAtmosphere => _materials[2];
  fs.PreprocessedMaterial get _earthAtmosphere => _materials[3];
  fs.PreprocessedMaterial get _earthCloudMaterial => _materials[4];
  fs.PreprocessedMaterial get _marsCloudMaterial => _materials[5];

  late final _marsGeometry = measuredPlanetMeshData(heightField: _height)
      .geometry();
  late final _sphereGeometry = measuredPlanetMeshData(
    rows: 96,
    columns: 192,
  ).geometry();

  static const _planetPath = 'assets/title/planets';
  static const _shaderPath = 'assets/title/shaders';

  static Future<TitleCelestialModels> load() async {
    final textures = await Future.wait([
      fs.Texture2D.fromAsset('$_planetPath/mars_viking_albedo_4k.jpg'),
      fs.Texture2D.fromAsset(
        '$_planetPath/mars_mola_normal_2k.png',
        content: fs.TextureContent.normal,
      ),
      fs.Texture2D.fromAsset('$_planetPath/earth_blue_marble_day_2k.jpg'),
      fs.Texture2D.fromAsset('$_planetPath/earth_black_marble_night_2k.jpg'),
      fs.Texture2D.fromAsset('$_planetPath/earth_blue_marble_clouds_2k.png'),
    ]);
    final materials = await Future.wait([
      fs.loadFmatMaterial('$_shaderPath/planet_mars.fmat'),
      fs.loadFmatMaterial('$_shaderPath/planet_earth.fmat'),
      fs.loadFmatMaterial('$_shaderPath/planet_atmosphere.fmat'),
      fs.loadFmatMaterial('$_shaderPath/planet_atmosphere.fmat'),
      fs.loadFmatMaterial('$_shaderPath/planet_clouds.fmat'),
      fs.loadFmatMaterial('$_shaderPath/planet_clouds.fmat'),
    ]);
    final height = MeasuredPlanetHeightField(
      await rootBundle.load('$_planetPath/mars_mola_height_1k.bin'),
    );
    return TitleCelestialModels._(height, textures, materials);
  }

  static void _texture(
    fs.PreprocessedMaterial material,
    String name,
    fs.Texture2D texture,
  ) => material.parameters.setTexture(
    name,
    texture.gpuTexture,
    sampler: texture.sampledSampler,
  );

  TitleMarsModel mars(TitleSceneSnapshot snapshot) {
    _marsSurface.parameters.setFloat('greenery', snapshot.greenery);
    _marsCloudMaterial.parameters.setFloat(
      'opacity',
      (math.sqrt(snapshot.cloudCoverage.clamp(0.0, 1.0)) * 1.1).clamp(0.0, .6),
    );
    final atmosphere = snapshot.atmosphere.clamp(0.0, 1.0);
    _marsAtmosphere.parameters
      ..setVec3(
        'scatter_color',
        vm.Vector3(
          .38 * (1 - atmosphere) + .14 * atmosphere,
          .19 * (1 - atmosphere) + .34 * atmosphere,
          .10 * (1 - atmosphere) + .70 * atmosphere,
        ),
      )
      ..setFloat('density', .43 + atmosphere * .9);
    final root = fs.Node(name: 'title-mars')
      // 実測Valles Marinerisを見える地平線の下へ向ける固定の撮影姿勢。
      ..rotation = vm.Quaternion.fromTwoVectors(
        planetPoint(-12, -64, 1),
        vm.Vector3(
          0,
          math.sin(55 * math.pi / 180),
          math.cos(55 * math.pi / 180),
        ),
      );
    final surface = fs.Node(
      name: 'title-mars-surface',
      mesh: fs.Mesh(_marsGeometry, _marsSurface),
    );
    final clouds =
        fs.Node(
            name: 'title-mars-clouds',
            mesh: fs.Mesh(_sphereGeometry, _marsCloudMaterial),
          )
          ..scale = vm.Vector3.all(1.014)
          ..visible = snapshot.cloudCoverage > 0;
    final limb = fs.Node(
      name: 'title-mars-atmosphere',
      mesh: fs.Mesh(_sphereGeometry, _marsAtmosphere),
    )..scale = vm.Vector3.all(1.024);
    final settlements = _settlementLights(snapshot);
    root.add(surface);
    root.add(clouds);
    root.add(limb);
    root.add(settlements);
    _cloudNodes.removeWhere((entry) => !entry.$2);
    _cloudNodes.add((clouds, false));
    return TitleMarsModel(
      root: root,
      surface: surface,
      clouds: clouds,
      settlements: settlements,
      limb: limb,
    );
  }

  fs.Node earth() {
    final root = fs.Node(name: 'title-earth');
    _earthRoot = root;
    root.add(
      fs.Node(
        name: 'title-earth-globe',
        mesh: fs.Mesh(_sphereGeometry, _earthSurface),
      ),
    );
    final clouds = fs.Node(
      name: 'title-earth-clouds',
      mesh: fs.Mesh(_sphereGeometry, _earthCloudMaterial),
    )..scale = vm.Vector3.all(1.0065);
    root.add(clouds);
    root.add(
      fs.Node(
        name: 'title-earth-limb',
        mesh: fs.Mesh(_sphereGeometry, _earthAtmosphere),
      )..scale = vm.Vector3.all(1.025),
    );
    _cloudNodes.add((clouds, true));
    return root;
  }

  void updateView({
    required vm.Vector3 cameraPosition,
    required vm.Vector3 sunDirection,
    required double seconds,
    vm.Vector3? sunPosition,
  }) {
    final sun = sunDirection.normalized();
    for (final material in _materials.skip(1)) {
      material.parameters.setVec3('sun_direction', sun);
    }
    final earth = _earthRoot;
    if (sunPosition != null && earth != null) {
      final earthSun = (sunPosition - earth.position)..normalize();
      for (final material in [
        _earthSurface,
        _earthAtmosphere,
        _earthCloudMaterial,
      ]) {
        material.parameters.setVec3('sun_direction', earthSun);
      }
    }
    for (final (node, earth) in _cloudNodes) {
      node.rotation = vm.Quaternion.axisAngle(
        vm.Vector3(0, 1, 0),
        seconds * (earth ? .026 : .0015),
      );
    }
  }

  fs.Node _settlementLights(TitleSceneSnapshot snapshot) {
    final root = fs.Node(name: 'title-mars-settlements');
    final count =
        (snapshot.settlementCount * 6 + snapshot.infrastructureCount * 2).clamp(
          0,
          96,
        );
    if (count == 0) return root;
    final batch = OpeningMeshBatch();
    for (var i = 0; i < count; i++) {
      final latitude = -12 + (i * 13 % 32).toDouble();
      final longitude = -84 + (i * 19 % 49).toDouble();
      final point = planetPoint(
        latitude,
        longitude,
        3.1 * (1 + _height.at(latitude, longitude) / 3396000 * 1.5) + .004,
      );
      final n = point.normalized();
      final east = vm.Vector3(n.z, 0, -n.x)..normalize();
      final north = n.cross(east)..normalize();
      final size = .003 + (i % 3) * .001;
      final color = i % 5 == 0
          ? const Color(0xffa7d7d8)
          : const Color(0xffe7be89);
      final a = point + east * size, b = point + north * size;
      final c = point - east * size, d = point - north * size;
      batch.triangle(a, b, c, color);
      batch.triangle(a, c, d, color);
    }
    root.add(
      batch.node(
        '都市と無人設備の遠い灯り',
        material: fs.UnlitMaterial()
          ..baseColorFactor = vm.Vector4(1.8, 1.4, 1, 1),
      ),
    );
    return root;
  }
}
