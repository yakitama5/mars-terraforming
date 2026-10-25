import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'opening_cinematic_geometry.dart';
import 'planet_models.dart';
import 'title_planet_geometry.dart';

/// 地表は固定、雲・航行物・宇宙だけを別の根から動かせる。
class TitleMarsModel {
  const TitleMarsModel({
    required this.root,
    required this.clouds,
    required this.settlements,
    required this.limb,
  });

  final fs.Node root;
  final fs.Node clouds;
  final fs.Node settlements;
  final fs.Node limb;
}

/// タイトル専用の造形。ゲーム進行や保存を持たず、GPU初期化後に生成する。
/// 細かな機体の継目・窓・セル・梁は色付きバッチへまとめる。
class TitleSceneModels {
  final p = PlanetModels();
  final _body = PlanetModels.material(.9, .9, .9)..roughnessFactor = .93;
  late final _marsMaterial = _makeMarsMaterial();
  final _white = PlanetModels.material(.75, .81, .83, metallic: .16);
  final _glass = PlanetModels.material(.075, .21, .28, metallic: .32)
    ..roughnessFactor = .32;
  final _light = fs.UnlitMaterial()
    ..baseColorFactor = vm.Vector4(1.3, 1.05, .63, 1);
  late final _dome = openingDomeGeometry();
  late final _satelliteDish = _dishGeometry();

  fs.PhysicallyBasedMaterial _makeMarsMaterial() {
    final pixels = TitleMarsDetailPixels.generate();
    return fs.PhysicallyBasedMaterial(
        baseColorTexture: fs.Texture2D.fromPixels(
          pixels.albedo,
          pixels.width,
          pixels.height,
        ),
        normalTexture: fs.Texture2D.fromPixels(
          pixels.normal,
          pixels.width,
          pixels.height,
          content: fs.TextureContent.normal,
        ),
      )
      ..baseColorFactor = vm.Vector4(.95, .95, .95, 1)
      ..metallicFactor = 0
      ..roughnessFactor = .97
      ..normalScale = .16;
  }

  fs.Node _batch(
    OpeningMeshBatch batch,
    String name, {
    bool emissive = false,
  }) => batch.node(name, material: emissive ? fs.UnlitMaterial() : _body);

  fs.Node _part(
    fs.Node root,
    fs.Geometry geometry,
    fs.Material material,
    vm.Vector3 position,
    vm.Vector3 scale, {
    vm.Quaternion? rotation,
  }) => p.part(root, geometry, material, position, scale, rotation: rotation);

  TitleMarsModel mars({
    double greening = 0,
    double cloudCover = 0,
    int settlementCount = 0,
    int infrastructureCount = 0,
    double activity = 0,
    double atmosphere = 0,
  }) {
    final root = fs.Node(name: '峡谷とクレーターのあるタイトルの火星');
    root.add(
      fs.Node(
        name: '連続した地層・盾状火山・衝突盆地・極冠',
        mesh: fs.Mesh(
          titleMarsMeshData(greening: greening).geometry(),
          _marsMaterial,
        ),
      ),
    );
    final limb = fs.Node(
      name: '火星の縁へ差す光',
      mesh: fs.Mesh(
        titleLimbGeometry(
          radius: TitleMarsSurface.radius * 1.002,
          width: .085 + atmosphere.clamp(0, 1) * .17,
          color: Color.lerp(
            const Color(0xffd2a28a),
            const Color(0xff8bc3dc),
            atmosphere.clamp(0.0, 1.0),
          )!,
          opacity: .3,
        ),
        fs.UnlitMaterial()..alphaMode = fs.AlphaMode.blend,
      ),
    );
    root.add(limb);
    final clouds = _clouds(cloudCover);
    root.add(clouds);
    final settlements = fs.Node(name: '保存された開発の灯り');
    const sites = [
      (46.0, 190.0),
      (59.0, 159.0),
      (46.0, 222.0),
      (62.0, 205.0),
      (48.0, 149.0),
      (40.0, 174.0),
      (56.0, 239.0),
      (66.0, 173.0),
    ];
    for (var i = 0; i < settlementCount.clamp(0, sites.length); i++) {
      final (lat, lon) = sites[i];
      final surface = _surface(lat, lon, lift: .007);
      surface.add(_settlement(i, green: greening > .15));
      settlements.add(surface);
    }
    for (var i = 0; i < infrastructureCount.clamp(0, 8); i++) {
      final surface = _surface(45 + i % 3 * 9.0, 138 + i * 10.5, lift: .007);
      surface.add(_infrastructure(i, activity: activity));
      settlements.add(surface);
    }
    root.add(settlements);
    return TitleMarsModel(
      root: root,
      clouds: clouds,
      settlements: settlements,
      limb: limb,
    );
  }

  fs.Node _surface(double lat, double lon, {double lift = 0}) {
    final position = TitleMarsSurface.point(lat, lon, lift: lift);
    return fs.Node()
      ..position = position
      ..rotation = vm.Quaternion.fromTwoVectors(
        vm.Vector3(0, 1, 0),
        position.normalized(),
      );
  }

  fs.Node _settlement(int index, {required bool green}) {
    final root = fs.Node(name: 'ドーム・温室・太陽電池・通信塔の入植地')
      ..scale = vm.Vector3.all(.12);
    final shell = OpeningMeshBatch(), lamps = OpeningMeshBatch();
    const concrete = Color(0xff8e7b69);
    const ceramic = Color(0xffbdc6c5);
    const dark = Color(0xff283a43);
    const amber = Color(0xffefc18a);
    shell.box(vm.Vector3(0, .015, 0), vm.Vector3(2.4, .04, 1.8), concrete);
    for (final x in [-.65, .22]) {
      shell.box(vm.Vector3(x, .11, 0), vm.Vector3(.7, .2, .7), ceramic);
      _part(
        root,
        _dome,
        _glass,
        vm.Vector3(x, .21, 0),
        vm.Vector3(.43, .32, .43),
      );
      // 四本の主骨と緯線を薄い梁へまとめる。
      for (var arc = 0; arc < 4; arc++) {
        final angle = arc * math.pi / 4;
        for (var j = 0; j < 12; j++) {
          final a = j * math.pi / 12, b = (j + 1) * math.pi / 12;
          vm.Vector3 point(double t) => vm.Vector3(
            x + math.cos(t) * math.cos(angle) * .435,
            .21 + math.sin(t) * .325,
            math.cos(t) * math.sin(angle) * .435,
          );
          shell.beam(point(a), point(b), .016, ceramic);
        }
      }
      for (final sign in [-1.0, 1.0]) {
        lamps.box(
          vm.Vector3(x, .17, sign * .354),
          vm.Vector3(.5, .04, .012),
          amber,
        );
      }
    }
    shell.box(vm.Vector3(-.2, .14, 0), vm.Vector3(.3, .14, .16), ceramic);
    shell.box(vm.Vector3(.5, .15, -.65), vm.Vector3(.9, .27, .35), ceramic);
    shell.box(vm.Vector3(.5, .29, -.65), vm.Vector3(.92, .03, .39), dark);
    for (var i = 0; i < 4; i++) {
      lamps.box(
        vm.Vector3(.18 + i * .2, .19, -.467),
        vm.Vector3(.09, .07, .008),
        amber,
      );
    }
    for (var i = 0; i < 3; i++) {
      _solar(
        shell,
        vm.Vector3(-.85 + i * .65, .13, .67),
        width: .53,
        depth: .32,
        cellsX: 4,
        cellsZ: 2,
      );
    }
    // 銀色の水タンクとアンテナは、ドームの隣へ接地する。
    for (var i = 0; i < 2; i++) {
      _lathe(
        shell,
        [.0, .0, .15, .13, .39, .13, .43, .0],
        ceramic,
        x: -1.03,
        z: -.49 + i * .3,
        segments: 14,
      );
    }
    shell.beam(vm.Vector3(1, .03, -.3), vm.Vector3(1, .8, -.3), .025, ceramic);
    _part(
      root,
      _satelliteDish,
      _white,
      vm.Vector3(1, .81, -.3),
      vm.Vector3.all(.22),
      rotation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), .5),
    );
    lamps.box(
      vm.Vector3(1, .72, -.3),
      vm.Vector3.all(.05),
      const Color(0xff98d9d6),
    );
    if (green) {
      shell.box(
        vm.Vector3(.9, .06, .36),
        vm.Vector3(.48, .05, .54),
        const Color(0xff527868),
      );
      for (var i = 0; i < 4; i++) {
        shell.box(
          vm.Vector3(.75 + i * .1, .09, .36),
          vm.Vector3(.045, .035, .45),
          const Color(0xff94ad7d),
        );
      }
    }
    for (var i = 0; i < 9; i++) {
      lamps.box(
        vm.Vector3(-1.1 + i * .27, .06, .94),
        vm.Vector3(.045, .026, .035),
        amber,
      );
    }
    root.add(_batch(shell, 'ドーム骨組みと入植設備 $index'));
    root.add(_batch(lamps, '窓と街路の灯り $index', emissive: true));
    return root;
  }

  fs.Node _infrastructure(int index, {required double activity}) {
    final root = fs.Node(name: '無人の資源設備と通信拠点')..scale = vm.Vector3.all(.11);
    final batch = OpeningMeshBatch(), lamps = OpeningMeshBatch();
    const ceramic = Color(0xffb5c2c3), dark = Color(0xff3d464c);
    batch.box(vm.Vector3(0, .02, 0), vm.Vector3(1.3, .04, 1.1), dark);
    for (var i = 0; i < 3; i++) {
      _solar(
        batch,
        vm.Vector3(-.44 + i * .43, .1, .3),
        width: .37,
        depth: .36,
        cellsX: 3,
        cellsZ: 2,
      );
    }
    batch.box(vm.Vector3(-.25, .19, -.21), vm.Vector3(.53, .34, .42), ceramic);
    batch.box(vm.Vector3(-.25, .38, -.21), vm.Vector3(.57, .04, .46), dark);
    _lathe(
      batch,
      [0, .14, .43, .14, .48, 0],
      ceramic,
      x: .36,
      z: -.26,
      segments: 16,
    );
    batch.beam(
      vm.Vector3(.36, .03, -.26),
      vm.Vector3(.36, .78, -.26),
      .025,
      ceramic,
    );
    for (var i = 0; i < 4; i++) {
      batch.beam(
        vm.Vector3(.28, .24 + i * .12, -.26),
        vm.Vector3(.44, .24 + i * .12, -.26),
        .017,
        ceramic,
      );
    }
    final brightness = activity.isFinite ? activity.clamp(0.0, 1.0) : 0.0;
    if (brightness > 0) {
      for (var i = 0; i < 3; i++) {
        lamps.box(
          vm.Vector3(-.42 + i * .17, .23, .007),
          vm.Vector3(.07, .065, .01),
          Color.lerp(
            const Color(0xff675846),
            const Color(0xffe9c693),
            brightness,
          )!,
        );
      }
      root.add(_batch(lamps, '無人設備の稼働灯 $index', emissive: true));
    }
    root.add(_batch(batch, '太陽電池・抽出器・通信マスト $index'));
    return root;
  }

  fs.Node _clouds(double coverage) {
    final root = fs.Node(name: '開発が育む薄い雲');
    final cover = coverage.isFinite ? coverage.clamp(0.0, 1.0) : 0.0;
    if (cover <= 0) return root;
    final positions = <double>[], normals = <double>[], colors = <double>[];
    final indices = <int>[];
    // 透明な全面殻で地表を白くせず、細い渦のある薄片だけを作る。
    for (final patch in const [
      (58.0, 185.0, 21.0, 4.2),
      (43.0, 209.0, 16.0, 3.2),
      (64.0, 151.0, 18.0, 3.7),
      (39.0, 179.0, 24.0, 2.8),
      (61.0, 229.0, 25.0, 3.0),
      (52.0, 119.0, 16.0, 2.8),
    ]) {
      const rows = 10, columns = 32;
      final start = positions.length ~/ 3;
      for (var row = 0; row <= rows; row++) {
        final v = row / rows * 2 - 1;
        for (var column = 0; column <= columns; column++) {
          final u = column / columns * 2 - 1;
          final lat =
              patch.$1 + v * patch.$4 + math.sin(u * 2.8) * patch.$4 * .8;
          final lon = patch.$2 + u * patch.$3;
          final direction = TitleMarsSurface.point(lat, lon).normalized();
          final point = direction * 3.23;
          positions.addAll([point.x, point.y, point.z]);
          normals.addAll([direction.x, direction.y, direction.z]);
          final edge = (1 - u * u) * (1 - v * v);
          final wave = .65 + .35 * math.sin(u * 15 + v * 6);
          final opacity = (math.sqrt(cover) * 1.5).clamp(0.0, .6);
          colors.addAll([.78, .85, .86, edge * wave * opacity]);
          if (row < rows && column < columns) {
            final a = start + row * (columns + 1) + column;
            final b = a + columns + 1;
            indices.addAll([a, b, a + 1, a + 1, b, b + 1]);
          }
        }
      }
    }
    root.add(
      fs.Node(
        name: '透ける六つの雲帯',
        mesh: fs.Mesh(
          fs.MeshGeometry.fromArrays(
            positions: Float32List.fromList(positions),
            normals: Float32List.fromList(normals),
            colors: Float32List.fromList(colors),
            indices: indices,
            retainCpuData: false,
          ),
          fs.PhysicallyBasedMaterial()
            ..alphaMode = fs.AlphaMode.blend
            ..roughnessFactor = 1
            ..metallicFactor = 0,
        ),
      ),
    );
    return root;
  }

  fs.Node earth() {
    final root = fs.Node(name: '遠くの青い地球');
    root.add(p.globe(true)..name = 'title-earth-globe');
    root.add(
      fs.Node(
        name: 'title-earth-limb',
        mesh: fs.Mesh(
          titleLimbGeometry(
            radius: 3.1,
            width: .14,
            color: const Color(0xff79b8e8),
            opacity: .28,
          ),
          fs.UnlitMaterial()..alphaMode = fs.AlphaMode.blend,
        ),
      ),
    );
    return root;
  }

  /// ノーズが+Y、エンジン側が-Y。全長3、中央を原点に揃える。
  fs.Node rocket() {
    final root = fs.Node(name: '火星へ向かう探査輸送船');
    final shell = OpeningMeshBatch(), dark = OpeningMeshBatch();
    final lights = OpeningMeshBatch();
    const ceramic = Color(0xffd9dfdc), navy = Color(0xff273c49);
    const orange = Color(0xffbf7750), metal = Color(0xff829297);
    final hull = fs.Node()..position = vm.Vector3(0, -1.35, 0);
    _lathe(
      shell,
      [0, .2, .12, .23, 1.95, .23, 2.16, .22, 2.45, .17, 2.7, .08, 2.84, 0],
      ceramic,
      segments: 40,
    );
    for (final y in [.18, .85, 1.75, 2.1]) {
      _lathe(dark, [y, .234, y + .035, .234], navy, segments: 40);
    }
    _lathe(shell, [1.91, .237, 2.02, .237], orange, segments: 40);
    // 船腹の放熱器、点検パネル、機体に沿う配管。
    for (final sign in [-1.0, 1.0]) {
      shell.box(
        vm.Vector3(sign * .19, 1.26, -.14),
        vm.Vector3(.035, .67, .11),
        metal,
      );
      shell.beam(
        vm.Vector3(sign * .13, .35, -.192),
        vm.Vector3(sign * .13, 1.65, -.192),
        .018,
        metal,
      );
      for (var i = 0; i < 8; i++) {
        dark.box(
          vm.Vector3(sign * .213, 1 + i * .06, -.14),
          vm.Vector3(.012, .015, .095),
          navy,
        );
      }
    }
    for (var i = 0; i < 3; i++) {
      dark.box(
        vm.Vector3((i - 1) * .105, 2.29, .182),
        vm.Vector3(.063, .09, .018),
        const Color(0xff316879),
      );
    }
    shell.box(vm.Vector3(.01, 1.63, .228), vm.Vector3(.19, .26, .024), metal);
    dark.box(vm.Vector3(.01, 1.63, .243), vm.Vector3(.15, .22, .012), ceramic);
    // 四枚の操舵フィンは板の箱でなく翼形の三角面。
    for (var i = 0; i < 4; i++) {
      final angle = i * math.pi / 2;
      vm.Vector3 v(double radius, double y, double side) => vm.Vector3(
        math.cos(angle) * radius - math.sin(angle) * side,
        y,
        math.sin(angle) * radius + math.cos(angle) * side,
      );
      final a = v(.19, .18, -.025), b = v(.61, .13, -.025);
      final c = v(.22, .89, -.025);
      final d = v(.19, .18, .025), e = v(.61, .13, .025);
      final f = v(.22, .89, .025);
      shell.triangle(a, b, c, ceramic);
      shell.triangle(d, f, e, ceramic);
      shell.triangle(b, e, f, orange);
      shell.triangle(b, f, c, orange);
      shell.triangle(a, d, e, metal);
      shell.triangle(a, e, b, metal);
    }
    // 三つの独立したベルと燃焼室。
    for (final engine in const [(0.0, .09), (-.105, -.09), (.105, -.09)]) {
      _lathe(
        dark,
        [-.22, .105, -.16, .087, -.03, .049, .06, .055],
        navy,
        x: engine.$1,
        z: engine.$2,
        segments: 20,
      );
      _lathe(
        shell,
        [-.23, .111, -.20, .111],
        metal,
        x: engine.$1,
        z: engine.$2,
        segments: 20,
      );
      lights.box(
        vm.Vector3(engine.$1, -.055, engine.$2),
        vm.Vector3(.045, .04, .045),
        const Color(0xffa0d8ef),
      );
    }
    hull.add(_batch(shell, '陶器質の外板・翼・継目・エンジン縁'));
    hull.add(_batch(dark, '船窓・放熱器・三つのエンジンベル'));
    hull.add(_batch(lights, '静かなエンジン光', emissive: true));
    root.add(hull);
    return root;
  }

  /// 太陽電池のセル、金色の断熱材、通信皿、姿勢制御ノズルを持つ周回機。
  fs.Node satellite() {
    final root = fs.Node(name: '二翼の火星観測衛星');
    final foil = OpeningMeshBatch(), steel = OpeningMeshBatch();
    final cells = OpeningMeshBatch(), lights = OpeningMeshBatch();
    const silver = Color(0xffaebdc3), dark = Color(0xff243d4d);
    const gold = Color(0xffc9a76e);
    foil.box(vm.Vector3.zero(), vm.Vector3(.62, .7, .58), gold);
    // 断熱箔の折り目は面を細分し、光に応じて立体の陰影が出る。
    for (final sign in [-1.0, 1.0]) {
      for (var i = 0; i < 6; i++) {
        final y = -.3 + i * .11;
        steel.box(
          vm.Vector3(sign * .316, y, 0),
          vm.Vector3(.02, .018, .6),
          const Color(0xffdfc78e),
        );
      }
      steel.beam(
        vm.Vector3(sign * .28, 0, 0),
        vm.Vector3(sign * 1.95, 0, 0),
        .045,
        silver,
      );
      _solar(
        cells,
        vm.Vector3(sign * 1.28, .035, 0),
        width: 1.48,
        depth: .94,
        cellsX: 10,
        cellsZ: 6,
      );
      steel.box(
        vm.Vector3(sign * .32, -.24, .24),
        vm.Vector3(.08, .08, .08),
        dark,
      );
    }
    steel.box(vm.Vector3(0, -.365, 0), vm.Vector3(.65, .05, .61), silver);
    steel.box(vm.Vector3(0, .375, 0), vm.Vector3(.65, .05, .61), silver);
    steel.beam(vm.Vector3(0, .35, 0), vm.Vector3(0, .67, 0), .045, silver);
    final dish = _part(
      root,
      _satelliteDish,
      _white,
      vm.Vector3(0, .7, 0),
      vm.Vector3.all(.6),
    );
    dish.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -.45);
    steel.beam(
      vm.Vector3(0, .9, -.08),
      vm.Vector3(0, 1.18, -.22),
      .018,
      silver,
    );
    steel.beam(vm.Vector3(.23, .3, 0), vm.Vector3(.28, 1.4, .04), .017, silver);
    steel.box(vm.Vector3(0, .02, .31), vm.Vector3(.25, .25, .045), dark);
    lights.box(
      vm.Vector3(.24, .28, .32),
      vm.Vector3(.035, .035, .015),
      const Color(0xff96d8dc),
    );
    root.add(_batch(foil, '金色の多層断熱材'));
    root.add(_batch(steel, '翼の支持梁・通信器・制御機器'));
    root.add(_batch(cells, '120枚の独立した太陽電池セル'));
    root.add(_batch(lights, '衛星の航行灯', emissive: true));
    return root;
  }

  void _solar(
    OpeningMeshBatch batch,
    vm.Vector3 center, {
    required double width,
    required double depth,
    required int cellsX,
    required int cellsZ,
  }) {
    batch.box(
      center,
      vm.Vector3(width + .035, .033, depth + .035),
      const Color(0xffa9bac5),
    );
    for (var x = 0; x < cellsX; x++) {
      for (var z = 0; z < cellsZ; z++) {
        final position =
            center +
            vm.Vector3(
              (x + .5) / cellsX * width - width / 2,
              .020,
              (z + .5) / cellsZ * depth - depth / 2,
            );
        batch.box(
          position,
          vm.Vector3(width / cellsX * .91, .009, depth / cellsZ * .88),
          (x + z) % 3 == 0 ? const Color(0xff345b7c) : const Color(0xff23465f),
        );
        batch.box(
          position + vm.Vector3(0, .007, 0),
          vm.Vector3(.004, .002, depth / cellsZ * .8),
          const Color(0xff8ba8b8),
        );
      }
    }
  }

  /// [profile] は高さ・半径の交互配列。外板・ベルに共通の回転体。
  void _lathe(
    OpeningMeshBatch batch,
    List<double> profile,
    Color color, {
    double x = 0,
    double z = 0,
    int segments = 28,
  }) {
    for (var row = 0; row < profile.length ~/ 2 - 1; row++) {
      for (var i = 0; i < segments; i++) {
        final a = i / segments * math.pi * 2;
        final b = (i + 1) / segments * math.pi * 2;
        vm.Vector3 point(int r, double angle) => vm.Vector3(
          x + math.cos(angle) * profile[r * 2 + 1],
          profile[r * 2],
          z + math.sin(angle) * profile[r * 2 + 1],
        );
        final p0 = point(row, a), p1 = point(row + 1, a);
        final p2 = point(row + 1, b), p3 = point(row, b);
        if (profile[row * 2 + 1] > 0) batch.triangle(p0, p1, p3, color);
        if (profile[(row + 1) * 2 + 1] > 0) batch.triangle(p1, p2, p3, color);
      }
    }
  }

  fs.MeshGeometry _dishGeometry() {
    final positions = <double>[], normals = <double>[];
    final indices = <int>[];
    const rings = 12, segments = 48;
    for (var row = 0; row <= rings; row++) {
      final r = .5 * row / rings;
      for (var i = 0; i <= segments; i++) {
        final a = i / segments * math.pi * 2;
        final x = r * math.cos(a), z = r * math.sin(a);
        positions.addAll([x, r * r * .8, z]);
        final normal = vm.Vector3(-1.6 * x, 1, -1.6 * z)..normalize();
        normals.addAll([normal.x, normal.y, normal.z]);
        if (row < rings && i < segments) {
          final v = row * (segments + 1) + i, w = v + segments + 1;
          indices.addAll([v, v + 1, w, v + 1, w + 1, w]);
          indices.addAll([v, w, v + 1, v + 1, w, w + 1]);
        }
      }
    }
    return fs.MeshGeometry.fromArrays(
      positions: Float32List.fromList(positions),
      normals: Float32List.fromList(normals),
      indices: indices,
      retainCpuData: false,
    );
  }

  fs.Node asteroid(int seed) {
    final batch = OpeningMeshBatch();
    const rows = 12, columns = 24;
    vm.Vector3 point(int row, int column) {
      final lat = -math.pi / 2 + row / rows * math.pi;
      final lon = column / columns * math.pi * 2;
      final noise =
          1 +
          .16 * math.sin(lon * 3 + seed * 1.7) * math.cos(lat * 4 + seed) +
          .07 * math.sin(lat * 9 - lon * 7);
      return vm.Vector3(
        math.cos(lat) * math.sin(lon) * .59,
        math.sin(lat) * .45,
        math.cos(lat) * math.cos(lon) * .5,
      )..scale(noise);
    }

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final shade = .5 + .5 * math.sin(row * 3.1 + column * 1.7 + seed);
        final color = Color.lerp(
          const Color(0xff524c49),
          const Color(0xff8f7f6e),
          shade * .5,
        )!;
        final a = point(row, column), b = point(row + 1, column);
        final c = point(row + 1, column + 1), d = point(row, column + 1);
        if (row > 0) batch.triangle(a, d, b, color);
        if (row < rows - 1) batch.triangle(d, c, b, color);
      }
    }
    return _batch(batch, '角張った鉱物の小惑星 $seed');
  }

  fs.Node sun() {
    final root = fs.Node(name: '遠い太陽の光球とコロナ');
    _part(root, p.sphere, _light, vm.Vector3.zero(), vm.Vector3.all(2));
    root.add(
      fs.Node(
        name: '淡い太陽の光芒',
        mesh: fs.Mesh(
          titleLimbGeometry(
            radius: .98,
            width: 1.25,
            color: const Color(0xffffd1a3),
            opacity: .25,
          ),
          fs.UnlitMaterial()..alphaMode = fs.AlphaMode.blend,
        ),
      ),
    );
    return root;
  }

  /// 球の内側に置く星々。微小な四面体なので固定平面の裏返りがない。
  fs.Node stars({int count = 1300, double radius = 75}) {
    final batch = OpeningMeshBatch();
    final random = math.Random(81302);
    for (var i = 0; i < count; i++) {
      final u = random.nextDouble() * 2 - 1;
      final angle = random.nextDouble() * math.pi * 2;
      final distance = radius * (.85 + random.nextDouble() * .15);
      final spread = math.sqrt(1 - u * u);
      final center = vm.Vector3(
        spread * math.cos(angle),
        u,
        spread * math.sin(angle),
      )..scale(distance);
      final r = (i % 29 == 0 ? .11 : .035 + random.nextDouble() * .04);
      final color = i % 5 == 0
          ? const Color(0xffd8bb9b)
          : i % 3 == 0
          ? const Color(0xff8eaecb)
          : const Color(0xffb9c7d5);
      final a = center + vm.Vector3(r, r, r);
      final b = center + vm.Vector3(-r, -r, r);
      final c = center + vm.Vector3(-r, r, -r);
      final d = center + vm.Vector3(r, -r, -r);
      batch.triangle(a, c, b, color);
      batch.triangle(a, b, d, color);
      batch.triangle(a, d, c, color);
      batch.triangle(b, c, d, color);
    }
    return _batch(batch, '奥行きのある1300の恒星', emissive: true);
  }
}
