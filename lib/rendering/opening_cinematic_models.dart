import 'dart:math' as math;

import 'package:flutter/material.dart' show Color;
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'opening_cinematic_geometry.dart';
import 'planet_models.dart';

/// 5場面の形状は一度だけ作り、再生位置から姿勢だけを更新する。
/// 科学シミュレーションやゲームの進行・費用は扱わない。
class OpeningCinematicModels {
  OpeningCinematicModels() {
    roots.addAll([_city(), _launch(), _moon(), _exploration(), _settlement()]);
  }

  final p = PlanetModels();
  final roots = <fs.Node>[];
  final _growingBuildings = <fs.Node>[];
  final _cars = <fs.Node>[];
  final _smoke = <fs.Node>[];
  final _wheels = <fs.Node>[];
  final _people = <fs.Node>[];
  late final fs.Node _rocket, _flame, _craneArm, _rover, _mast, _lander, _earth;
  late final _domeGeometry = openingDomeGeometry();
  final _metal = PlanetModels.material(.48, .54, .57, metallic: .55)
    ..roughnessFactor = .4;
  final _ceramic = PlanetModels.material(.73, .70, .62, metallic: .12);
  final _glass = PlanetModels.material(.15, .33, .42, metallic: .22)
    ..baseColorFactor = vm.Vector4(.15, .33, .42, .52)
    ..alphaMode = fs.AlphaMode.blend
    ..roughnessFactor = .14
    ..emissiveFactor = vm.Vector4(.012, .026, .035, 1);
  final _warm = PlanetModels.material(.65, .37, .12)
    ..emissiveFactor = vm.Vector4(1.6, .75, .23, 1);
  final _cool = PlanetModels.material(.13, .40, .55)
    ..emissiveFactor = vm.Vector4(.15, .55, .8, 1);
  final _flameOuter = PlanetModels.material(.95, .36, .05)
    ..emissiveFactor = vm.Vector4(2.7, .9, .12, 1);
  final _flameInner = PlanetModels.material(.7, .8, .9)
    ..emissiveFactor = vm.Vector4(2.5, 2.5, 2.1, 1);
  final _smokeMaterial = PlanetModels.material(.42, .46, .49)
    ..baseColorFactor = vm.Vector4(.42, .46, .49, .65)
    ..alphaMode = fs.AlphaMode.blend;

  static double ease(double value) {
    final t = value.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  fs.Node _part(
    fs.Node root,
    fs.Geometry geometry,
    fs.Material material,
    double x,
    double y,
    double z,
    double sx,
    double sy,
    double sz, {
    vm.Quaternion? rotation,
  }) => p.part(
    root,
    geometry,
    material,
    vm.Vector3(x, y, z),
    vm.Vector3(sx, sy, sz),
    rotation: rotation,
  );

  fs.Node _building(double width, double height, double depth, int index) {
    final root = fs.Node(name: '窓と屋上設備のある建物');
    final shell = OpeningMeshBatch();
    final lights = OpeningMeshBatch();
    final wall = index.isEven
        ? const Color(0xffb3c3c7)
        : const Color(0xffc3beb0);
    shell.box(
      vm.Vector3(0, height / 2, 0),
      vm.Vector3(width, height, depth),
      wall,
    );
    shell.box(
      vm.Vector3(0, height + .05, 0),
      vm.Vector3(width + .1, .1, depth + .1),
      const Color(0xff40535c),
    );
    shell.box(
      vm.Vector3(.13, height + .18, .08),
      vm.Vector3(width * .42, .25, depth * .38),
      const Color(0xff7d8e93),
    );
    final floors = (height / .42).floor();
    for (var floor = 0; floor < floors; floor++) {
      final y = .27 + floor * .42;
      for (var column = 0; column < 3; column++) {
        final x = (column - 1) * width * .27;
        final color = (floor + column + index) % 4 == 0
            ? const Color(0xff3e687d)
            : const Color(0xffefc689);
        for (final sign in [-1.0, 1.0]) {
          lights.box(
            vm.Vector3(x, y, sign * (depth / 2 + .012)),
            vm.Vector3(width * .14, .16, .025),
            color,
          );
        }
      }
      for (final sign in [-1.0, 1.0]) {
        lights.box(
          vm.Vector3(sign * (width / 2 + .012), y, 0),
          vm.Vector3(.025, .15, depth * .56),
          const Color(0xff9fbcd1),
        );
      }
    }
    root.add(shell.node('外壁・パラペット・空調設備'));
    root.add(
      lights.node(
        '暮らしの窓灯',
        material: fs.PhysicallyBasedMaterial()
          ..emissiveFactor = vm.Vector4(.45, .35, .24, 1),
      ),
    );
    return root;
  }

  fs.Node _city() {
    final root = fs.Node(name: '朝日を迎える地球の開発都市');
    root.add(openingTerrain(world: 0));
    final streets = OpeningMeshBatch();
    streets.box(
      vm.Vector3(0, .015, .8),
      vm.Vector3(35, .05, 2.1),
      const Color(0xff303c46),
    );
    streets.box(
      vm.Vector3(2, .018, -2),
      vm.Vector3(1.8, .06, 22),
      const Color(0xff303c46),
    );
    streets.box(
      vm.Vector3(0, -.04, 9),
      vm.Vector3(84, .05, 12),
      const Color(0xff244c65),
    );
    streets.box(
      vm.Vector3(0, .04, 3),
      vm.Vector3(32, .14, .45),
      const Color(0xff8e9f9e),
    );
    for (var i = -15; i <= 15; i++) {
      streets.box(
        vm.Vector3(i.toDouble(), .051, .8),
        vm.Vector3(.45, .015, .045),
        const Color(0xffbec6b9),
      );
    }
    root.add(streets.node('海辺の大通りと埠頭'));
    for (var i = 0; i < 12; i++) {
      final row = i ~/ 4, column = i % 4;
      final height = 1.7 + ((i * 7) % 5) * .65;
      final building = _building(1.2 + (i % 3) * .2, height, 1.4, i)
        ..position = vm.Vector3(-5.7 + column * 3.1, .05, -2.0 - row * 3.3);
      _growingBuildings.add(building);
      root.add(building);
    }
    for (var i = 0; i < 9; i++) {
      root.add(
        _building(1.3, 1.4 + (i % 4) * .7, 1.3, i + 5)
          ..position = vm.Vector3(-13 + i * 3.1, 0, -16),
      );
    }
    for (var i = 0; i < 9; i++) {
      final x = -9 + i * 2.4;
      _part(root, p.cylinder, p.navy, x, .7, 2.7, .05, 1.4, .05);
      _part(root, p.sphere, _warm, x, 1.43, 2.7, .16, .12, .16);
      _tree(root, x, -11.2, .85 + (i % 2) * .2);
    }
    final crane = fs.Node(name: '建設を進めるタワークレーン')
      ..position = vm.Vector3(5.5, 0, -7.7);
    final lattice = OpeningMeshBatch();
    _latticeTower(lattice, 4.9, .55);
    crane.add(lattice.node('クレーンの鉄骨'));
    _craneArm = fs.Node()..position = vm.Vector3(0, 4.8, 0);
    final jib = OpeningMeshBatch();
    jib.beam(
      vm.Vector3(-1.1, 0, 0),
      vm.Vector3(3.7, 0, 0),
      .16,
      const Color(0xffc19e65),
    );
    jib.beam(
      vm.Vector3(0, .8, 0),
      vm.Vector3(3.7, 0, 0),
      .035,
      const Color(0xffd9d8c9),
    );
    jib.beam(
      vm.Vector3(2.9, 0, 0),
      vm.Vector3(2.9, -1.4, 0),
      .025,
      const Color(0xffaebbc0),
    );
    jib.box(
      vm.Vector3(-.85, -.12, 0),
      vm.Vector3(.8, .45, .65),
      const Color(0xff777f7b),
    );
    _craneArm.add(jib.node('旋回するジブと吊り具'));
    crane.add(_craneArm);
    root.add(crane);
    for (var i = 0; i < 3; i++) {
      final car = fs.Node(name: '港へ向かう地上車両');
      _part(car, p.box, i == 1 ? _ceramic : p.blue, 0, .16, 0, .7, .25, .32);
      _part(car, p.box, p.navy, .02, .34, 0, .36, .15, .29);
      _part(car, p.box, _warm, .36, .2, 0, .02, .08, .25);
      _cars.add(car);
      root.add(car);
    }
    return root;
  }

  void _latticeTower(OpeningMeshBatch batch, double height, double width) {
    const steel = Color(0xff9eaaae);
    for (final x in [-width / 2, width / 2]) {
      for (final z in [-width / 2, width / 2]) {
        batch.beam(vm.Vector3(x, 0, z), vm.Vector3(x, height, z), .07, steel);
      }
    }
    for (var i = 0; i < height.floor(); i++) {
      final y = i.toDouble();
      for (final side in [-1.0, 1.0]) {
        batch.beam(
          vm.Vector3(-width / 2, y, side * width / 2),
          vm.Vector3(width / 2, y + 1, side * width / 2),
          .04,
          steel,
        );
        batch.beam(
          vm.Vector3(side * width / 2, y, -width / 2),
          vm.Vector3(side * width / 2, y + 1, width / 2),
          .04,
          steel,
        );
      }
    }
  }

  fs.Node _launch() {
    final root = fs.Node(name: '海岸の発射場から空へ');
    root.add(openingTerrain(world: 0));
    _part(root, p.cylinder, p.concrete, 0, .06, 0, 6, .16, 6);
    _part(root, p.ring, _ceramic, 0, .16, 0, 4.5, 1, 4.5);
    _part(root, p.box, p.navy, 0, .18, 1, 1.1, .1, 4.3);
    final tower = OpeningMeshBatch();
    _latticeTower(tower, 6.2, .8);
    root.add(tower.node('サービス塔と支柱')..position = vm.Vector3(-2.1, .1, -.7));
    _part(root, p.box, _ceramic, -1.2, 4.1, -.7, 1.8, .15, .4);
    for (var i = 0; i < 3; i++) {
      _part(root, p.cylinder, _metal, -5.0 - i * 1.4, .75, -4, 1, 1.5, 1);
      _part(root, p.sphere, _ceramic, -5.0 - i * 1.4, 1.5, -4, 1, .5, 1);
    }
    _rocket = p.rocket()..name = '上昇する多段式ロケット';
    _flame = fs.Node(name: '三基のエンジンの排炎');
    for (final x in [-.245, 0.0, .245]) {
      _part(
        _flame,
        p.cone,
        _flameOuter,
        x,
        -.7,
        0,
        .28,
        1.6,
        .28,
        rotation: vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), math.pi),
      );
      _part(
        _flame,
        p.cone,
        _flameInner,
        x,
        -.35,
        0,
        .17,
        .9,
        .17,
        rotation: vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), math.pi),
      );
    }
    _rocket.add(_flame);
    root.add(_rocket);
    for (var i = 0; i < 12; i++) {
      final smoke = _part(root, p.rock, _smokeMaterial, 0, .2, 0, 1, 1, 1);
      smoke.shadowCastingMode = fs.ShadowCastingMode.off;
      _smoke.add(smoke);
    }
    return root;
  }

  void _solar(fs.Node root, double x, double z, {double scale = 1}) {
    final array = fs.Node(name: 'セル列と支持脚を持つ太陽電池')
      ..position = vm.Vector3(x, 0, z)
      ..scale = vm.Vector3.all(scale);
    _part(array, p.cylinder, _metal, 0, .35, 0, .065, .7, .065);
    final panel = fs.Node()
      ..position = vm.Vector3(0, .72, 0)
      ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -.24);
    _part(panel, p.box, p.blue, 0, 0, 0, 2, .045, 1.1);
    final frame = OpeningMeshBatch();
    for (var i = -3; i <= 3; i++) {
      frame.box(
        vm.Vector3(i * .32, .027, 0),
        vm.Vector3(.018, .018, 1.1),
        const Color(0xffa0bbc8),
      );
    }
    for (final z in [-.55, 0.0, .55]) {
      frame.box(
        vm.Vector3(0, .027, z),
        vm.Vector3(2, .018, .018),
        const Color(0xffa0bbc8),
      );
    }
    panel.add(frame.node('太陽電池のフレーム'));
    array.add(panel);
    root.add(array);
  }

  void _module(fs.Node root, double x, double z) {
    final module = fs.Node(name: '気密区画とエアロック')..position = vm.Vector3(x, .2, z);
    _part(
      module,
      p.cylinder,
      _ceramic,
      0,
      .55,
      0,
      1.2,
      2.6,
      1.2,
      rotation: vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), math.pi / 2),
    );
    for (final sign in [-1.0, 1.0]) {
      _part(module, p.sphere, _metal, sign * 1.3, .55, 0, .45, 1.2, 1.2);
      _part(module, p.box, p.navy, sign * 1.56, .45, 0, .06, .65, .45);
      _part(module, p.box, _warm, sign * .6, .7, .604, .45, .20, .025);
      _part(module, p.box, _metal, sign * .85, 0, 0, .14, .5, 1.3);
    }
    root.add(module);
  }

  fs.Node _dish() {
    final root = fs.Node(name: '地球を向く通信アンテナ');
    _part(root, p.cylinder, _metal, 0, .65, 0, .09, 1.3, .09);
    final head = fs.Node()
      ..position = vm.Vector3(0, 1.35, 0)
      ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -.6);
    _part(head, p.sphere, _ceramic, 0, 0, 0, 1.2, .16, 1.2);
    _part(head, p.cylinder, _metal, 0, .28, 0, .035, .6, .035);
    _part(head, p.sphere, _cool, 0, .59, 0, .08, .08, .08);
    root.add(head);
    return root;
  }

  void _rocks(fs.Node root, {required bool moon}) {
    for (var i = 0; i < 24; i++) {
      final angle = i * 2.399963;
      final radius = 7.5 + (i % 5) * 2.5;
      final scale = .35 + (i % 4) * .23;
      _part(
        root,
        p.rock,
        moon ? _metal : p.darkDust,
        math.cos(angle) * radius,
        scale * .18,
        math.sin(angle) * radius - 3,
        scale * 1.4,
        scale * .65,
        scale,
      );
    }
  }

  void _stars(fs.Node root) {
    final stars = OpeningMeshBatch();
    for (var i = 0; i < 46; i++) {
      final x = math.sin(i * 32.41) * 43;
      final y = 9 + (i % 11) * 2.8;
      final size = i % 7 == 0 ? .09 : .045;
      stars.box(
        vm.Vector3(x, y, -48 + (i % 3) * 3),
        vm.Vector3.all(size),
        const Color(0xffcbdbe9),
      );
    }
    root.add(
      stars.node('遠方の星々', material: fs.UnlitMaterial())
        ..shadowCastingMode = fs.ShadowCastingMode.off,
    );
  }

  fs.Node _moon() {
    final root = fs.Node(name: '月の稜線と地球を望む基地');
    root.add(
      openingTerrain(world: 1)
        // 広い遠景地形の自己シャドウを除く。基地や岩の影は引き続き受ける。
        ..shadowCastingMode = fs.ShadowCastingMode.off,
    );
    _rocks(root, moon: true);
    _stars(root);
    _earth = p.globe(true)
      ..position = vm.Vector3(-12, 10.5, -25)
      ..scale = vm.Vector3.all(.85);
    // 遠方の地球は背景天体。設定は子へ継承されないため全メッシュへ適用する。
    void omitDistantShadow(fs.Node node) {
      node.shadowCastingMode = fs.ShadowCastingMode.off;
      for (final child in node.children) {
        omitDistantShadow(child);
      }
    }

    omitDistantShadow(_earth);
    root.add(_earth);
    _module(root, -1.6, -.9);
    _module(root, 1.4, -3.1);
    _part(root, p.box, _ceramic, -.1, .5, -2.0, .55, .6, 2.4);
    for (var i = 0; i < 3; i++) {
      _solar(root, -3.6 + i * 2.4, 2.4, scale: .82);
    }
    root.add(_dish()..position = vm.Vector3(3.5, 0, -1.2));
    root.add(
      _landingCraft()
        ..position = vm.Vector3(5.8, 0, -6.5)
        ..scale = vm.Vector3.all(.7),
    );
    for (var i = 0; i < 5; i++) {
      _part(root, p.sphere, _cool, -3.8 + i * 1.8, .12, .8, .10, .09, .10);
    }
    return root;
  }

  fs.Node _makeRover() {
    final root = fs.Node(name: '六輪ローバーと科学観測機器');
    _part(root, p.box, _ceramic, 0, .67, 0, 1.8, .36, 1.1);
    _part(root, p.box, _metal, -.4, .91, 0, .75, .15, .8);
    _part(root, p.box, p.navy, .56, .92, 0, .42, .14, .72);
    final structure = OpeningMeshBatch();
    for (final sign in [-1.0, 1.0]) {
      structure.beam(
        vm.Vector3(-.8, .37, sign * .7),
        vm.Vector3(.7, .55, sign * .7),
        .055,
        const Color(0xffb5b6ac),
      );
      for (final x in [-.7, 0.0, .7]) {
        final axle = fs.Node()
          ..position = vm.Vector3(x, .31, sign * .69)
          ..rotation = vm.Quaternion.axisAngle(
            vm.Vector3(1, 0, 0),
            math.pi / 2,
          );
        final wheel = fs.Node();
        _part(wheel, p.cylinder, p.navy, 0, 0, 0, .59, .29, .59);
        _part(wheel, p.cylinder, _metal, 0, sign * .15, 0, .25, .025, .25);
        final treads = OpeningMeshBatch();
        for (var j = 0; j < 10; j++) {
          final angle = j / 10 * math.pi * 2;
          treads.box(
            vm.Vector3(math.sin(angle) * .29, 0, math.cos(angle) * .29),
            vm.Vector3(.045, .30, .045),
            const Color(0xff647073),
          );
        }
        wheel.add(treads.node('回転するタイヤの踏面'));
        axle.add(wheel);
        root.add(axle);
        _wheels.add(wheel);
      }
    }
    structure.beam(
      vm.Vector3(.7, .75, -.25),
      vm.Vector3(1.17, .4, -.35),
      .065,
      const Color(0xffb5b6ac),
    );
    structure.beam(
      vm.Vector3(1.17, .4, -.35),
      vm.Vector3(1.4, .18, -.35),
      .055,
      const Color(0xffb5b6ac),
    );
    root.add(structure.node('ロッカーボギー懸架と採取アーム'));
    _mast = fs.Node(name: '左右を調べる観測マスト')..position = vm.Vector3(.45, .85, 0);
    _part(_mast, p.cylinder, _metal, 0, .45, 0, .065, .9, .065);
    _part(_mast, p.box, _ceramic, .06, .9, 0, .29, .18, .46);
    for (final z in [-.14, .14]) {
      _part(_mast, p.sphere, p.navy, .21, .91, z, .08, .08, .08);
    }
    root.add(_mast);
    return root;
  }

  fs.Node _exploration() {
    final root = fs.Node(name: '赤い山稜を進む火星ローバー');
    root.add(openingTerrain(world: 2));
    _rocks(root, moon: false);
    final tracks = OpeningMeshBatch();
    for (var i = 0; i < 42; i++) {
      final x = -14 + i * .3;
      for (final z in [-.69, .69]) {
        tracks.box(
          vm.Vector3(x, -.035, z),
          vm.Vector3(.13, .015, .27),
          const Color(0xff694539),
        );
      }
    }
    root.add(tracks.node('地表に残る二筋の轍'));
    _rover = _makeRover();
    root.add(_rover);
    return root;
  }

  void _dome(
    fs.Node root,
    double x,
    double z,
    double radius, {
    bool garden = false,
  }) {
    final dome = fs.Node(name: garden ? '作物の育つ温室ドーム' : '暖かな明かりの居住ドーム')
      ..position = vm.Vector3(x, .08, z);
    final height = radius * .76;
    _part(dome, p.cylinder, _ceramic, 0, .05, 0, radius * 2, .1, radius * 2);
    _part(dome, p.ring, _warm, 0, .12, 0, radius * 2, 1, radius * 2);
    final frames = OpeningMeshBatch();
    for (var spoke = 0; spoke < 10; spoke++) {
      final angle = spoke / 10 * math.pi * 2;
      for (var arc = 0; arc < 12; arc++) {
        vm.Vector3 point(int index) {
          final elevation = index / 12 * math.pi / 2;
          return vm.Vector3(
            math.cos(angle) * math.cos(elevation) * radius,
            .12 + math.sin(elevation) * height,
            math.sin(angle) * math.cos(elevation) * radius,
          );
        }

        frames.beam(point(arc), point(arc + 1), .052, const Color(0xffbdcdd0));
      }
    }
    for (final elevation in [math.pi / 6, math.pi / 3]) {
      for (var segment = 0; segment < 32; segment++) {
        vm.Vector3 point(int index) {
          final angle = index / 32 * math.pi * 2;
          return vm.Vector3(
            math.cos(angle) * math.cos(elevation) * radius,
            .12 + math.sin(elevation) * height,
            math.sin(angle) * math.cos(elevation) * radius,
          );
        }

        frames.beam(
          point(segment),
          point(segment + 1),
          .04,
          const Color(0xffbdcdd0),
        );
      }
    }
    dome.add(
      frames.node(
        '連続したアーチと周方向リング',
        material: fs.PhysicallyBasedMaterial()
          ..metallicFactor = .25
          ..roughnessFactor = .45
          ..emissiveFactor = vm.Vector4(.035, .045, .05, 1),
      ),
    );
    for (var i = 0; i < 5; i++) {
      final row = i - 2;
      if (garden) {
        _part(
          dome,
          p.box,
          p.concrete,
          row * radius * .27,
          .2,
          0,
          radius * .19,
          .18,
          radius * 1.25,
        );
        for (var plant = 0; plant < 4; plant++) {
          _part(
            dome,
            p.rock,
            _leaf,
            row * radius * .27,
            .36,
            (plant - 1.5) * radius * .28,
            .2,
            .3,
            .2,
          );
        }
      } else {
        final angle = i * math.pi * 2 / 5;
        _part(
          dome,
          p.box,
          _ceramic,
          math.cos(angle) * radius * .48,
          .35,
          math.sin(angle) * radius * .48,
          radius * .38,
          .48,
          radius * .3,
        );
        _part(
          dome,
          p.box,
          _warm,
          math.cos(angle) * radius * .48,
          .45,
          math.sin(angle) * radius * .48 + radius * .155,
          radius * .22,
          .12,
          .02,
        );
      }
    }
    _part(
      dome,
      _domeGeometry,
      _glass,
      0,
      .12,
      0,
      radius * .99,
      height * .99,
      radius * .99,
    ).shadowCastingMode = fs.ShadowCastingMode.off;
    _part(dome, p.box, _ceramic, 0, .38, radius, .62, .6, .65);
    _part(dome, p.box, p.navy, 0, .37, radius + .335, .39, .49, .02);
    _part(dome, p.box, _warm, 0, .72, radius + .2, .48, .06, .08);
    root.add(dome);
  }

  final _leaf = PlanetModels.material(.055, .21, .11);
  void _tree(fs.Node root, double x, double z, double scale) {
    _part(root, p.cylinder, p.darkDust, x, .32 * scale, z, .1, .64 * scale, .1);
    _part(
      root,
      p.rock,
      _leaf,
      x,
      .9 * scale,
      z,
      .8 * scale,
      1.2 * scale,
      .8 * scale,
    );
  }

  fs.Node _landingCraft() {
    final root = fs.Node(name: '脚を開いた居住用着陸船');
    _part(root, p.cylinder, _ceramic, 0, 1.3, 0, 1.5, 1.6, 1.5);
    _part(root, p.sphere, _ceramic, 0, 2.1, 0, 1.5, .7, 1.5);
    _part(root, p.cylinder, _metal, 0, .65, 0, 1.55, .2, 1.55);
    _part(root, p.nozzle, p.navy, 0, .35, 0, .8, .45, .8);
    _part(root, p.box, p.navy, 0, 1.6, .76, .7, .28, .05);
    _part(root, p.box, _warm, 0, 1.2, .77, .34, .06, .03);
    final legs = OpeningMeshBatch();
    for (var i = 0; i < 4; i++) {
      final angle = math.pi / 4 + i * math.pi / 2;
      final x = math.cos(angle), z = math.sin(angle);
      legs.beam(
        vm.Vector3(x * .65, 1.1, z * .65),
        vm.Vector3(x * 1.35, .12, z * 1.35),
        .09,
        const Color(0xff9ea7a8),
      );
      legs.beam(
        vm.Vector3(x * .65, .6, z * .65),
        vm.Vector3(x * 1.35, .12, z * 1.35),
        .06,
        const Color(0xff697c85),
      );
      legs.box(
        vm.Vector3(x * 1.35, .06, z * 1.35),
        vm.Vector3(.45, .08, .45),
        const Color(0xff66777c),
      );
    }
    root.add(legs.node('展開した着陸脚'));
    return root;
  }

  fs.Node _person() {
    final root = fs.Node(name: '基地へ歩く宇宙服の入植者');
    _part(root, p.box, _ceramic, 0, .34, 0, .19, .25, .13);
    _part(root, p.sphere, _ceramic, 0, .54, 0, .23, .23, .23);
    _part(root, p.sphere, p.navy, 0, .55, .09, .17, .12, .1);
    _part(root, p.box, p.navy, 0, .35, -.1, .15, .18, .1);
    for (final sign in [-1.0, 1.0]) {
      _part(root, p.box, _ceramic, sign * .06, .13, 0, .07, .23, .08);
      _part(root, p.box, _ceramic, sign * .14, .32, 0, .06, .2, .07);
    }
    return root;
  }

  fs.Node _settlement() {
    final root = fs.Node(name: '火星で始まる人の暮らし');
    root.add(openingTerrain(world: 2));
    _rocks(root, moon: false);
    _stars(root);
    _dome(root, -2.6, -.9, 2.0);
    _dome(root, 2.1, -3.1, 1.65);
    _dome(root, -4.5, -5.7, 1.55, garden: true);
    _module(root, 1.2, -7.0);
    _part(
      root,
      p.box,
      _ceramic,
      -.1,
      .3,
      -2.1,
      3.9,
      .43,
      .6,
      rotation: vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), .45),
    );
    for (var i = 0; i < 3; i++) {
      _solar(root, -6.2 + i * 2.0, -9.2, scale: .75);
    }
    root.add(_dish()..position = vm.Vector3(4.9, 0, -5.5));
    _lander = _landingCraft();
    root.add(_lander);
    for (var i = 0; i < 3; i++) {
      final person = _person();
      root.add(person);
      _people.add(person);
    }
    for (var i = 0; i < 12; i++) {
      _part(root, p.sphere, _warm, -3 + i * .8, .09, 2.0, .1, .09, .1);
    }
    return root;
  }

  void update(int chapter, double progress) {
    for (var i = 0; i < roots.length; i++) {
      roots[i].visible = i == chapter;
    }
    final t = progress.clamp(0.0, 1.0);
    switch (chapter) {
      case 0:
        for (var i = 0; i < _growingBuildings.length; i++) {
          final growth = .18 + .82 * ease((t - (i % 4) * .075) / .7);
          _growingBuildings[i].scale = vm.Vector3(1, growth, 1);
        }
        _craneArm.rotation = vm.Quaternion.axisAngle(
          vm.Vector3(0, 1, 0),
          -.4 + t * .8,
        );
        for (var i = 0; i < _cars.length; i++) {
          _cars[i].position = vm.Vector3(
            -10 + ((t * 15 + i * 7) % 23),
            0,
            .35 + (i % 2) * .75,
          );
        }
      case 1:
        final lift = math.pow(ease((t - .13) / .87), 1.5).toDouble() * 15;
        _rocket.position = vm.Vector3(.7 * t * t, .2 + lift, 0);
        _rocket.scale = vm.Vector3.all(2.0);
        _rocket.rotation = vm.Quaternion.axisAngle(
          vm.Vector3(0, 0, 1),
          -.045 * t,
        );
        _flame.visible = t > .04;
        _flame.scale = vm.Vector3(1, .85 + .18 * math.sin(t * 180), 1);
        for (var i = 0; i < _smoke.length; i++) {
          final spread = ease((t - .035) * 3) * (1.2 + i * .28);
          final angle = i * 2.399963;
          _smoke[i].visible = t > .04;
          _smoke[i].position = vm.Vector3(
            math.cos(angle) * spread,
            .25 + (i % 3) * .18,
            math.sin(angle) * spread,
          );
          _smoke[i].scale = vm.Vector3(
            1.4 + spread * .38,
            .7 + spread * .25,
            1.2 + spread * .35,
          );
        }
      case 2:
        _earth.rotation = vm.Quaternion.axisAngle(
          vm.Vector3(0, 1, 0),
          .25 + t * .09,
        );
      case 3:
        _rover.position = vm.Vector3(
          -3.3 + t * 6.6,
          .015 + .012 * math.sin(t * 60),
          0,
        );
        _mast.rotation = vm.Quaternion.axisAngle(
          vm.Vector3(0, 1, 0),
          -.4 + .7 * math.sin(t * math.pi),
        );
        for (final wheel in _wheels) {
          wheel.rotation = vm.Quaternion.axisAngle(
            vm.Vector3(0, 1, 0),
            -t * 22,
          );
        }
      case 4:
        _lander.position = vm.Vector3(5.0, (1 - ease(t * 2.2)) * 2.2, .3);
        for (var i = 0; i < _people.length; i++) {
          final walking = ease((t - .35 - i * .04) / .6);
          _people[i].position = vm.Vector3(
            3.7 - walking * (4.6 - i * .6),
            .015 + math.sin(walking * 42).abs() * .025,
            1.45 + i * .35,
          );
          _people[i].rotation = vm.Quaternion.axisAngle(
            vm.Vector3(0, 1, 0),
            -math.pi / 2,
          );
          _people[i].visible = t >= .38;
        }
    }
  }

  fs.PerspectiveCamera camera(int chapter, double progress) {
    final t = ease(progress);
    final (position, target) = switch (chapter) {
      0 => (
        vm.Vector3(13 - t * 5, 7.1 - t * 1.5, 17 - t * 3),
        vm.Vector3(0, 1.6, -3),
      ),
      1 => (
        vm.Vector3(10 - t * 3, 5.8 + _rocket.position.y * .85, 14 - t * 2),
        vm.Vector3(.2, _rocket.position.y + .55, 0),
      ),
      2 => (
        vm.Vector3(10 - t * 4, 5.1 - t * .7, 13 + t),
        vm.Vector3(-.5, 1.7, -2.7),
      ),
      3 => (
        vm.Vector3(_rover.position.x + 4.5 - t, 2.8 + t * .25, 6.5),
        vm.Vector3(_rover.position.x, .65, -.4),
      ),
      _ => (
        vm.Vector3(10 - t * 3, 4.7 - t * .8, 12.5 - t),
        vm.Vector3(-.7, .4, -2.4),
      ),
    };
    return fs.PerspectiveCamera(
      position: position,
      target: target,
      fovRadiansY: chapter == 1 ? .8 : .76,
      fovNear: .12,
      fovFar: 450,
    );
  }
}
