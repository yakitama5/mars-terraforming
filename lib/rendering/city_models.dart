import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'city_geometry.dart';
import 'city_snapshot.dart';
import 'planet_models.dart';

/// Local map models share primitive buffers with the globe's visual language.
class CityModels {
  final p = PlanetModels();
  final grass = PlanetModels.material(.21, .34, .23);
  final trunk = PlanetModels.material(.25, .20, .13);
  final ore = PlanetModels.material(.54, .43, .28);
  final road = PlanetModels.material(.22, .27, .26);
  final glass = PlanetModels.material(.20, .48, .57, metallic: .25);
  final green = PlanetModels.material(.30, .52, .26);

  fs.Node landscape(CityTerrain terrain, {String? cityId}) {
    final root = fs.Node(name: '連続地形と自然地物');
    root.add(
      fs.Node(mesh: fs.Mesh(terrain.mesh(), PlanetModels.material(1, 1, 1))),
    );
    for (final plot in terrain.plots) {
      final center = terrain.center(plot.index);
      for (var i = 0; i < 2; i++) {
        final angle = (plot.index * 37 + i * 157) * math.pi / 180;
        final x = center.x + math.cos(angle) * .76;
        final z = center.z + math.sin(angle) * .76;
        final y = terrain.height(x, z);
        if (plot.terrain == 'ice') {
          p.part(
            root,
            p.rock,
            p.ice,
            vm.Vector3(x, y + .06, z),
            vm.Vector3(.32, .17, .25),
          );
        } else if (plot.terrain == 'mineral') {
          p.part(
            root,
            p.rock,
            ore,
            vm.Vector3(x, y + .12, z),
            vm.Vector3(.32, .30, .25),
          );
        } else if (plot.terrain == 'ridge') {
          p.part(
            root,
            p.rock,
            terrain.earth ? ore : p.dust,
            vm.Vector3(x, y + .08, z),
            vm.Vector3(.30, .20, .35),
          );
        } else if (terrain.earth && plot.terrain == 'plain') {
          p.part(
            root,
            p.cylinder,
            trunk,
            vm.Vector3(x, y + .10, z),
            vm.Vector3(.04, .21, .04),
          );
          p.part(
            root,
            p.cone,
            grass,
            vm.Vector3(x, y + .27, z),
            vm.Vector3(.24, .35, .24),
          );
        }
      }
    }
    if (cityId == 'earth_delta') _headquarters(root, terrain);
    return root;
  }

  fs.Node developments(CityTerrain terrain, List<ScenePlot> plots) {
    final root = fs.Node(name: '区画と同じ座標の都市施設');
    final developed = plots.where((plot) => plot.isDeveloped).toList();
    for (var i = 0; i < developed.length; i++) {
      for (var j = i + 1; j < developed.length; j++) {
        final a = terrain.center(developed[i].index);
        final b = terrain.center(developed[j].index);
        final flatDistance = math.sqrt(
          math.pow(a.x - b.x, 2) + math.pow(a.z - b.z, 2),
        );
        if (flatDistance > 1.8) continue;
        _surfaceRoad(root, terrain, a, b);
      }
    }
    for (final plot in plots) {
      final position = terrain.center(plot.index);
      final district = fs.Node(
        name: '区画${plot.index + 1}:${plot.districtId ?? plot.terrain}',
      )..position = position;
      root.add(district);
      if (plot.isDeveloped) _district(district, plot, terrain.earth);
      if (plot.workState == SceneWorkState.queued) {
        _reservation(district);
      } else if (plot.workState == SceneWorkState.building) {
        _construction(district, upgrade: plot.isDeveloped);
      }
    }
    return root;
  }

  void _surfaceRoad(
    fs.Node root,
    CityTerrain terrain,
    vm.Vector3 a,
    vm.Vector3 b,
  ) {
    for (var i = 0; i < 8; i++) {
      final start = a + (b - a) * (i / 8);
      final end = a + (b - a) * ((i + 1) / 8);
      start.y = terrain.height(start.x, start.z) + .026;
      end.y = terrain.height(end.x, end.z) + .026;
      _beam(root, start, end, .055, road);
    }
  }

  void _beam(
    fs.Node root,
    vm.Vector3 a,
    vm.Vector3 b,
    double width,
    fs.Material material,
  ) {
    final direction = b - a;
    p.part(
      root,
      p.box,
      material,
      (a + b) * .5,
      vm.Vector3(width, direction.length, width),
      rotation: vm.Quaternion.fromTwoVectors(
        vm.Vector3(0, 1, 0),
        direction.normalized(),
      ),
    );
  }

  void _district(fs.Node root, ScenePlot plot, bool earth) {
    final level = plot.level.clamp(1, 3);
    // Stable plot footprint: upgrades add wings, structures and height here.
    p.part(
      root,
      p.cylinder,
      p.concrete,
      vm.Vector3(0, .025, 0),
      vm.Vector3(1.25, .05, 1.25),
    );
    switch (plot.districtId) {
      case 'housing':
        for (var i = 0; i < 2 + level; i++) {
          final x = (i % 2 == 0 ? -.23 : .23);
          final z = (i ~/ 2 - .6) * .36;
          final height = .27 + level * .10 + (i % 2) * .08;
          _tower(root, x, z, height, p.white);
        }
        break;
      case 'campus':
      case 'mars_lab':
        _tower(root, -.12, 0, .23 + level * .11, p.white);
        for (var i = 0; i < level; i++) {
          p.part(
            root,
            p.box,
            glass,
            vm.Vector3(.27, .13, -.28 + i * .24),
            vm.Vector3(.30, .19, .18),
          );
        }
        p.part(
          root,
          p.cylinder,
          p.white,
          vm.Vector3(-.26, .60 + level * .06, 0),
          vm.Vector3(.025, .38, .025),
        );
        p.part(
          root,
          p.sphere,
          p.white,
          vm.Vector3(-.26, .82 + level * .06, 0),
          vm.Vector3(.32, .065, .32),
          rotation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), .5),
        );
        break;
      case 'industry':
        for (var i = 0; i < level + 1; i++) {
          p.part(
            root,
            p.box,
            p.white,
            vm.Vector3(-.24 + i * .17, .17, .06),
            vm.Vector3(.15, .27, .65),
          );
          p.part(
            root,
            p.box,
            p.blue,
            vm.Vector3(-.24 + i * .17, .32, .06),
            vm.Vector3(.17, .055, .69),
          );
        }
        for (var i = 0; i < level; i++) {
          p.part(
            root,
            p.cylinder,
            p.orange,
            vm.Vector3(-.37 + i * .25, .36, -.34),
            vm.Vector3(.08, .61, .08),
          );
          p.part(
            root,
            p.cylinder,
            p.navy,
            vm.Vector3(-.37 + i * .25, .66, -.34),
            vm.Vector3(.085, .045, .085),
          );
        }
        break;
      case 'solar':
        for (var i = 0; i < level + 2; i++) {
          final z = -.37 + i * .24;
          for (final x in [-.23, .23]) {
            p.part(
              root,
              p.box,
              p.blue,
              vm.Vector3(x, .14, z),
              vm.Vector3(.38, .035, .19),
              rotation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -.3),
            );
            p.part(
              root,
              p.box,
              p.white,
              vm.Vector3(x, .155, z),
              vm.Vector3(.012, .035, .19),
              rotation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -.3),
            );
          }
        }
        break;
      case 'spaceport':
        p.part(
          root,
          p.cylinder,
          p.navy,
          vm.Vector3(-.14, .064, -.03),
          vm.Vector3(.83, .07, .83),
        );
        root.add(
          p.rocket()
            ..position = vm.Vector3(-.14, .11, -.03)
            ..scale = vm.Vector3.all(.43 + level * .025),
        );
        _tower(root, .40, .20, .35 + level * .09, p.white);
        for (var i = 0; i < level; i++) {
          p.part(
            root,
            p.box,
            p.orange,
            vm.Vector3(.36, .12, -.40 + i * .14),
            vm.Vector3(.16, .15, .10),
          );
        }
        break;
      case 'mars_habitat':
        if (plot.habitatStyle == 'underground') {
          _underground(root, level);
          break;
        }
        for (var i = 0; i < level + 1; i++) {
          final x = i.isEven ? -.24 : .24;
          final z = i < 2 ? -.18 : .25;
          p.part(
            root,
            p.cylinder,
            p.white,
            vm.Vector3(x, .14, z),
            vm.Vector3(.42, .23, .42),
          );
          p.part(
            root,
            p.sphere,
            glass,
            vm.Vector3(x, .28, z),
            vm.Vector3(.46, .37, .46),
          );
          p.part(
            root,
            p.box,
            p.orange,
            vm.Vector3(x, .12, z + .23),
            vm.Vector3(.10, .12, .15),
          );
        }
        _beam(
          root,
          vm.Vector3(-.24, .12, -.18),
          vm.Vector3(.24, .12, -.18),
          .09,
          p.white,
        );
        break;
      case 'greenhouse':
        for (var i = 0; i < level + 1; i++) {
          final x = -.30 + i * .21;
          p.part(
            root,
            p.box,
            p.white,
            vm.Vector3(x, .12, 0),
            vm.Vector3(.17, .15, .71),
          );
          p.part(
            root,
            p.sphere,
            green,
            vm.Vector3(x, .22, 0),
            vm.Vector3(.19, .27, .74),
          );
          for (final z in [-.23, 0.0, .23]) {
            p.part(
              root,
              p.box,
              p.white,
              vm.Vector3(x, .26, z),
              vm.Vector3(.18, .025, .023),
            );
          }
        }
        break;
      case 'extractor':
        p.part(
          root,
          p.cylinder,
          p.navy,
          vm.Vector3(-.18, .08, -.12),
          vm.Vector3(.59, .11, .59),
        );
        for (final x in [-.36, 0.0]) {
          _beam(
            root,
            vm.Vector3(x, .08, -.32),
            vm.Vector3(-.18, .75 + level * .08, -.12),
            .045,
            p.orange,
          );
          _beam(
            root,
            vm.Vector3(x, .08, .08),
            vm.Vector3(-.18, .75 + level * .08, -.12),
            .045,
            p.orange,
          );
        }
        for (var i = 0; i < level + 1; i++) {
          p.part(
            root,
            p.cylinder,
            p.ice,
            vm.Vector3(.32, .25, -.32 + i * .24),
            vm.Vector3(.16, .40, .16),
          );
        }
        break;
      default:
        _tower(root, 0, 0, .35, earth ? p.white : glass);
    }
  }

  void _headquarters(fs.Node root, CityTerrain terrain) {
    final town = fs.Node(name: '区画外の既存本部と市街')
      ..position = terrain.surfacePoint(-.5, 4.85);
    root.add(town);
    p.part(
      town,
      p.box,
      p.concrete,
      vm.Vector3(0, .035, 0),
      vm.Vector3(3.25, .07, .90),
    );
    p.part(
      town,
      p.box,
      road,
      vm.Vector3(0, .08, .25),
      vm.Vector3(3.10, .025, .11),
    );
    for (var i = 0; i < 4; i++) {
      _tower(town, -1.25 + i * .42, -.14, .22 + (i % 2) * .14, p.white);
    }
    p.part(
      town,
      p.cylinder,
      p.navy,
      vm.Vector3(1.09, .08, 0),
      vm.Vector3(.65, .08, .65),
    );
    town.add(
      p.rocket()
        ..position = vm.Vector3(1.09, .14, 0)
        ..scale = vm.Vector3.all(.27),
    );
  }

  void _underground(fs.Node root, int level) {
    // Only the entrances and life-support plant stand above the regolith.
    p.part(
      root,
      p.rock,
      p.dust,
      vm.Vector3(0, .11, -.13),
      vm.Vector3(.92, .38, .77),
    );
    for (var i = 0; i < level; i++) {
      final x = -.30 + i * .28;
      p.part(
        root,
        p.box,
        p.white,
        vm.Vector3(x, .13, .24),
        vm.Vector3(.23, .24, .29),
      );
      p.part(
        root,
        p.box,
        p.navy,
        vm.Vector3(x, .105, .39),
        vm.Vector3(.15, .18, .025),
      );
      p.part(
        root,
        p.box,
        p.orange,
        vm.Vector3(x, .26, .34),
        vm.Vector3(.25, .035, .20),
      );
    }
    for (final x in [-.32, .32]) {
      p.part(
        root,
        p.cylinder,
        p.white,
        vm.Vector3(x, .34, -.31),
        vm.Vector3(.095, .58, .095),
      );
      p.part(
        root,
        p.cylinder,
        p.orange,
        vm.Vector3(x, .63, -.31),
        vm.Vector3(.14, .07, .14),
      );
    }
  }

  void _tower(
    fs.Node root,
    double x,
    double z,
    double height,
    fs.Material material,
  ) {
    p.part(
      root,
      p.box,
      material,
      vm.Vector3(x, .06 + height / 2, z),
      vm.Vector3(.31, height, .28),
    );
    p.part(
      root,
      p.box,
      p.navy,
      vm.Vector3(x, .07 + height, z),
      vm.Vector3(.34, .035, .31),
    );
    for (var floor = 0; floor < 3; floor++) {
      p.part(
        root,
        p.box,
        glass,
        vm.Vector3(x, .13 + floor * height / 4, z + .143),
        vm.Vector3(.25, .035, .012),
      );
    }
  }

  void _reservation(fs.Node root) {
    for (final x in [-.53, .53]) {
      for (final z in [-.43, .43]) {
        p.part(
          root,
          p.cylinder,
          p.orange,
          vm.Vector3(x, .16, z),
          vm.Vector3(.025, .31, .025),
        );
        p.part(
          root,
          p.box,
          p.orange,
          vm.Vector3(x + .055, .27, z),
          vm.Vector3(.10, .07, .018),
        );
      }
    }
  }

  void _construction(fs.Node root, {required bool upgrade}) {
    _reservation(root);
    if (!upgrade) {
      p.part(
        root,
        p.box,
        p.concrete,
        vm.Vector3(0, .045, 0),
        vm.Vector3(.82, .09, .72),
      );
      for (final x in [-.34, .34]) {
        for (final z in [-.28, .28]) {
          _beam(
            root,
            vm.Vector3(x, .09, z),
            vm.Vector3(x, .50, z),
            .035,
            p.white,
          );
        }
        _beam(
          root,
          vm.Vector3(x, .50, -.28),
          vm.Vector3(x, .50, .28),
          .035,
          p.white,
        );
      }
      _beam(
        root,
        vm.Vector3(-.34, .50, -.28),
        vm.Vector3(.34, .50, -.28),
        .035,
        p.white,
      );
    }
    // A crane sits beside the retained building when an upgrade is underway.
    _beam(
      root,
      vm.Vector3(.48, .04, -.39),
      vm.Vector3(.48, .98, -.39),
      .055,
      p.orange,
    );
    _beam(
      root,
      vm.Vector3(-.28, .96, -.39),
      vm.Vector3(.63, .96, -.39),
      .045,
      p.orange,
    );
    _beam(
      root,
      vm.Vector3(-.24, .94, -.39),
      vm.Vector3(-.24, .54, -.39),
      .012,
      p.navy,
    );
    p.part(
      root,
      p.box,
      p.white,
      vm.Vector3(.59, .89, -.39),
      vm.Vector3(.16, .14, .13),
    );
  }
}
