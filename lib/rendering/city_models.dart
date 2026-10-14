import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'city_geometry.dart';
import 'city_snapshot.dart';
import 'planet_models.dart';

/// Districts grow across the terrain instead of standing on display plinths.
/// The numerous low-poly houses, trees and roads share one baked mesh; domes,
/// tanks and rockets reuse the globe's primitive buffers.
class CityModels {
  final p = PlanetModels();
  final glass = PlanetModels.material(.055, .21, .24, metallic: .18);
  final greenhouseGlass = PlanetModels.material(.12, .26, .13, metallic: .1);
  final tank = PlanetModels.material(.43, .50, .45, metallic: .2);
  static const walls = Color(0xffd4cdb5);
  static const warmWalls = Color(0xffbcb496);
  static const roof = Color(0xff557478);
  static const windows = Color(0xff315963);
  static const paving = Color(0xff948d74);
  static const asphalt = Color(0xff5d6058);
  static const stripe = Color(0xffbab696);
  static const orange = Color(0xffcf833d);
  static const steel = Color(0xff889491);

  fs.Node landscape(CityTerrain terrain, {String? cityId}) {
    final root = fs.Node(name: '連続した地域の地形');
    root.add(
      fs.Node(mesh: fs.Mesh(terrain.mesh(), PlanetModels.material(1, 1, 1))),
    );
    final surroundings = _CityMesh();
    _surroundings(
      surroundings,
      terrain,
      hasHeadquarters: cityId == 'earth_delta',
    );
    if (cityId == 'earth_delta') _headquarters(root, surroundings, terrain);
    surroundings.attach(root, '周辺景観と区画外の既存市街');
    return root;
  }

  fs.Node developments(CityTerrain terrain, List<ScenePlot> plots) {
    final root = fs.Node(name: '地域の集落・植生・建設現場');
    final mesh = _CityMesh();
    final developed = plots.where((plot) => plot.isDeveloped).toList();
    for (var i = 0; i < developed.length; i++) {
      for (var j = i + 1; j < developed.length; j++) {
        final a = terrain.center(developed[i].index);
        final b = terrain.center(developed[j].index);
        final length = math.sqrt(
          math.pow(a.x - b.x, 2) + math.pow(a.z - b.z, 2),
        );
        if (length < 1.8) {
          _road(mesh, terrain, a.x, a.z, b.x, b.z, width: .085);
        }
      }
    }
    for (final plot in plots) {
      final center = terrain.center(plot.index);
      if (!plot.isDeveloped && plot.workState != SceneWorkState.building) {
        _nature(mesh, terrain, plot, center);
      }
      if (plot.isDeveloped) _district(root, mesh, terrain, plot, center);
      if (plot.workState == SceneWorkState.queued) {
        _reservation(mesh, terrain, center);
      } else if (plot.workState == SceneWorkState.building) {
        _construction(mesh, terrain, center, upgrade: plot.isDeveloped);
      }
    }
    // Updating a completed/paid district also updates its ground cover. Trees
    // are retained on a reservation, and cleared only when construction starts.
    mesh.attach(root, '街区・道路・自然物の共通メッシュ');
    return root;
  }

  void _nature(
    _CityMesh mesh,
    CityTerrain terrain,
    ScenePlot plot,
    vm.Vector3 center,
  ) {
    final forest =
        terrain.earth && (plot.terrain == 'plain' || plot.terrain == 'ridge');
    if (forest) {
      // A world-space density field makes groves continue across cell borders.
      // Their centers and clearings no longer repeat the shape of every hex.
      for (var row = 0; row < 5; row++) {
        for (var col = 0; col < 5; col++) {
          final seed = plot.index * 97 + row * 7 + col;
          final dx = (col - 2) * .27 + (_noise(seed) - .5) * .13;
          final dz = (row - 2) * .27 + (_noise(seed + 19) - .5) * .13;
          if (dx * dx + dz * dz > .52) continue;
          final x = center.x + dx, z = center.z + dz;
          final density = _forestDensity(x, z);
          if (density < (plot.terrain == 'ridge' ? .60 : -.15)) continue;
          _tree(
            mesh,
            terrain,
            x,
            z,
            scale: .65 + _noise(seed + 37) * .61,
            color: seed.isEven
                ? const Color(0xff426c3c)
                : const Color(0xff5b7d3f),
          );
        }
      }
      if (plot.terrain == 'plain') return;
    }
    final seed = plot.index * 2.399963;
    final count = switch (plot.terrain) {
      'mineral' => 8 + plot.index % 3,
      'ice' => 6 + plot.index % 3,
      'coast' => 3,
      'ridge' => 4,
      'crater' => 4 + plot.index % 3,
      _ => 2 + plot.index % 4,
    };
    for (var i = 0; i < count; i++) {
      final variation = _noise(plot.index * 23 + i * 7);
      // An irregular vein or shoreline patch, rather than a radial counter.
      final along = (i / count - .45) * .98;
      final across = (variation - .5) * .34;
      final x =
          center.x +
          math.cos(seed) * along -
          math.sin(seed) * across +
          .12 * math.sin(seed);
      final z =
          center.z +
          math.sin(seed) * along +
          math.cos(seed) * across +
          .15 * math.cos(seed);
      final y = terrain.height(x, z);
      if (terrain.earth && plot.terrain == 'coast' && y < .025) continue;
      final ice = plot.terrain == 'ice';
      final color = ice
          ? const Color(0xffbfdbda)
          : plot.terrain == 'mineral'
          ? (i.isEven ? const Color(0xff887655) : const Color(0xffaca27c))
          : terrain.earth
          ? const Color(0xff777c69)
          : const Color(0xff9a6748);
      final width = .13 + variation * .16;
      mesh.rock(
        vm.Vector3(x, y + (ice ? .025 : .06), z),
        vm.Vector3(
          width,
          ice ? .045 + variation * .035 : .10 + variation * .11,
          width * .78,
        ),
        color,
      );
    }
  }

  double _noise(int seed) {
    final raw = math.sin(seed * 12.9898 + 78.233) * 43758.5453;
    return raw - raw.floor();
  }

  double _forestDensity(double x, double z) =>
      math.sin(x * 1.57 + z * .34) +
      math.cos(z * 1.63 - x * .21) +
      .40 * math.sin(x * 3.17 - z * 2.6);

  void _surroundings(
    _CityMesh mesh,
    CityTerrain terrain, {
    required bool hasHeadquarters,
  }) {
    var trees = 0, rocks = 0;
    // Sparse nearby context; no decorative building or resource enters the
    // playable hexagons. All props are included in this one static batch.
    for (var row = -14; row <= 14; row++) {
      for (var col = -16; col <= 16; col++) {
        final seed = (row + 14) * 37 + col + 16;
        final x = col * .49 + (_noise(seed) - .5) * .21;
        final z = row * .49 + (_noise(seed + 31) - .5) * .21;
        var nearest = double.infinity;
        for (final center in terrain.centers) {
          final d =
              (x - center.x) * (x - center.x) + (z - center.z) * (z - center.z);
          nearest = math.min(nearest, d);
        }
        if (nearest < 1.40 || nearest > 7.5) continue;
        if (hasHeadquarters && z > 4.05 && z < 5.90 && x > -2.45 && x < 2.40) {
          continue;
        }
        final y = terrain.height(x, z);
        if (terrain.earth && y < .025) continue;
        final density = _forestDensity(x, z);
        if (terrain.earth && density > .65 && trees < 85) {
          _tree(
            mesh,
            terrain,
            x,
            z,
            scale: .68 + _noise(seed + 47) * .46,
            color: seed.isEven
                ? const Color(0xff426c3c)
                : const Color(0xff5b7d3f),
          );
          trees++;
        } else if (_noise(seed + 71) > .80 && rocks < 36) {
          final size = .16 + _noise(seed + 23) * .19;
          mesh.rock(
            vm.Vector3(x, y + .055, z),
            vm.Vector3(size, .12, size * .80),
            terrain.earth ? const Color(0xff7f836a) : const Color(0xffa37250),
          );
          rocks++;
        }
      }
    }
  }

  void _tree(
    _CityMesh mesh,
    CityTerrain terrain,
    double x,
    double z, {
    double scale = 1,
    Color color = const Color(0xff4d783e),
  }) {
    final y = terrain.height(x, z);
    mesh.box(
      vm.Vector3(x, y + .10 * scale, z),
      vm.Vector3(.033 * scale, .20 * scale, .033 * scale),
      const Color(0xff786348),
    );
    mesh.cone(
      vm.Vector3(x, y + .055 * scale, z),
      .115 * scale,
      .32 * scale,
      color,
    );
    mesh.cone(
      vm.Vector3(x, y + .21 * scale, z),
      .079 * scale,
      .23 * scale,
      color,
    );
  }

  void _road(
    _CityMesh mesh,
    CityTerrain terrain,
    double ax,
    double az,
    double bx,
    double bz, {
    double width = .075,
    Color color = asphalt,
  }) {
    final dx = bx - ax, dz = bz - az;
    final length = math.sqrt(dx * dx + dz * dz);
    if (length < .001) return;
    final sx = -dz / length * width / 2, sz = dx / length * width / 2;
    final steps = (length / .20).ceil();
    for (var i = 0; i < steps; i++) {
      final x0 = ax + dx * i / steps, z0 = az + dz * i / steps;
      final x1 = ax + dx * (i + 1) / steps, z1 = az + dz * (i + 1) / steps;
      mesh.quad(
        terrain.surfacePoint(x0 - sx, z0 - sz, offset: .021),
        terrain.surfacePoint(x0 + sx, z0 + sz, offset: .021),
        terrain.surfacePoint(x1 + sx, z1 + sz, offset: .021),
        terrain.surfacePoint(x1 - sx, z1 - sz, offset: .021),
        color,
      );
    }
  }

  void _building(
    _CityMesh mesh,
    CityTerrain terrain,
    double x,
    double z, {
    double width = .23,
    double depth = .21,
    double height = .23,
    Color color = walls,
    Color roofColor = roof,
    bool pitched = false,
  }) {
    final y = terrain.height(x, z);
    mesh.box(
      vm.Vector3(x, y + height / 2, z),
      vm.Vector3(width, height, depth),
      color,
    );
    if (pitched) {
      final e = depth / 2 + .012, w = width / 2 + .016;
      mesh.quad(
        vm.Vector3(x - w, y + height, z - e),
        vm.Vector3(x - w, y + height + .08, z),
        vm.Vector3(x + w, y + height + .08, z),
        vm.Vector3(x + w, y + height, z - e),
        roofColor,
      );
      mesh.quad(
        vm.Vector3(x - w, y + height + .08, z),
        vm.Vector3(x - w, y + height, z + e),
        vm.Vector3(x + w, y + height, z + e),
        vm.Vector3(x + w, y + height + .08, z),
        roofColor,
      );
    } else {
      mesh.box(
        vm.Vector3(x, y + height + .018, z),
        vm.Vector3(width + .022, .036, depth + .022),
        roofColor,
      );
      mesh.box(
        vm.Vector3(x + width * .22, y + height + .052, z - depth * .18),
        vm.Vector3(width * .27, .055, depth * .27),
        steel,
      );
    }
    for (var floor = 0; floor < (height > .32 ? 2 : 1); floor++) {
      final elevation = y + .10 + floor * .13;
      mesh.box(
        vm.Vector3(x, elevation, z + depth / 2 + .004),
        vm.Vector3(width * .72, .035, .008),
        windows,
      );
      mesh.box(
        vm.Vector3(x + width / 2 + .004, elevation, z),
        vm.Vector3(.008, .035, depth * .68),
        windows,
      );
    }
  }

  void _district(
    fs.Node root,
    _CityMesh mesh,
    CityTerrain terrain,
    ScenePlot plot,
    vm.Vector3 c,
  ) {
    final level = plot.level.clamp(1, 3);
    switch (plot.districtId) {
      case 'housing':
        _housing(mesh, terrain, c, level);
        break;
      case 'campus':
      case 'mars_lab':
        _campus(
          root,
          mesh,
          terrain,
          c,
          level,
          mars: plot.districtId == 'mars_lab',
        );
        break;
      case 'industry':
        _industry(root, mesh, terrain, c, level);
        break;
      case 'solar':
        _solar(mesh, terrain, c, level);
        break;
      case 'spaceport':
        _spaceport(root, mesh, terrain, c, level);
        break;
      case 'mars_habitat':
        if (plot.habitatStyle == 'underground') {
          _underground(root, mesh, terrain, c, level);
        } else {
          _habitat(root, mesh, terrain, c, level);
        }
        break;
      case 'greenhouse':
        _greenhouse(root, mesh, terrain, c, level);
        break;
      case 'extractor':
        _extractor(root, mesh, terrain, c, level);
        break;
    }
  }

  void _housing(_CityMesh mesh, CityTerrain terrain, vm.Vector3 c, int level) {
    _road(mesh, terrain, c.x - .67, c.z, c.x + .67, c.z, width: .11);
    _road(mesh, terrain, c.x, c.z - .70, c.x, c.z + .70, width: .10);
    const lots = [
      (-.23, -.23),
      (.23, -.22),
      (-.23, .24),
      (.23, .25),
      (-.52, -.17),
      (.52, .13),
      (-.20, -.56),
      (.17, .57),
      (.49, -.38),
      (-.49, .38),
      (.20, -.55),
      (-.22, .56),
      (-.51, .10),
      (.52, -.13),
    ];
    final count = [0, 8, 11, 14][level];
    for (var i = 0; i < count; i++) {
      final (x, z) = lots[i];
      _building(
        mesh,
        terrain,
        c.x + x,
        c.z + z,
        width: i < 4 ? .27 : .20,
        depth: i < 4 ? .23 : .18,
        height: .17 + (i % 3) * .045 + (level - 1) * .055,
        color: i.isEven ? walls : warmWalls,
        roofColor: i % 3 == 0 ? const Color(0xff946e49) : roof,
        pitched: i >= 4 && level < 3,
      );
    }
    // Small plazas, trees and lanes make the district read as inhabited land.
    _road(
      mesh,
      terrain,
      c.x - .51,
      c.z + .52,
      c.x - .36,
      c.z + .59,
      width: .16,
      color: paving,
    );
    _tree(mesh, terrain, c.x - .42, c.z + .58, scale: .65);
    _tree(mesh, terrain, c.x + .39, c.z - .58, scale: .60);
  }

  void _campus(
    fs.Node root,
    _CityMesh mesh,
    CityTerrain terrain,
    vm.Vector3 c,
    int level, {
    required bool mars,
  }) {
    _road(
      mesh,
      terrain,
      c.x - .64,
      c.z + .10,
      c.x + .62,
      c.z + .10,
      width: .14,
      color: paving,
    );
    _road(
      mesh,
      terrain,
      c.x - .02,
      c.z - .63,
      c.x - .02,
      c.z + .61,
      width: .09,
    );
    _building(
      mesh,
      terrain,
      c.x - .24,
      c.z - .25,
      width: .40,
      depth: .28,
      height: .29 + level * .065,
    );
    _building(
      mesh,
      terrain,
      c.x + .26,
      c.z + .36,
      width: .44,
      depth: .23,
      height: .19 + level * .025,
    );
    for (var i = 0; i < level; i++) {
      _building(
        mesh,
        terrain,
        c.x - .37 + i * .24,
        c.z + .37,
        width: .18,
        depth: .22,
        height: .15,
        roofColor: const Color(0xff6f9597),
      );
    }
    final x = c.x + .35,
        z = c.z - .30,
        y = terrain.height(c.x + .35, c.z - .30);
    mesh.box(vm.Vector3(x, y + .21, z), vm.Vector3(.06, .42, .06), steel);
    p.part(
      root,
      p.sphere,
      tank,
      vm.Vector3(x, y + .46, z),
      vm.Vector3(.37, .065, .32),
      rotation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), .58),
    );
    p.part(
      root,
      p.sphere,
      glass,
      vm.Vector3(
        c.x - .24,
        terrain.height(c.x - .24, c.z - .25) + .35 + level * .065,
        c.z - .25,
      ),
      vm.Vector3(.28, .17, .24),
    );
    if (!mars) {
      _tree(mesh, terrain, c.x - .59, c.z + .15, scale: .65);
      _tree(mesh, terrain, c.x + .55, c.z + .08, scale: .75);
    }
  }

  void _industry(
    fs.Node root,
    _CityMesh mesh,
    CityTerrain terrain,
    vm.Vector3 c,
    int level,
  ) {
    _road(
      mesh,
      terrain,
      c.x - .64,
      c.z + .28,
      c.x + .64,
      c.z + .28,
      width: .19,
    );
    for (var i = 0; i < level + 1; i++) {
      final x = c.x - .45 + i * .27;
      _building(
        mesh,
        terrain,
        x,
        c.z - .23,
        width: .23,
        depth: .53,
        height: .20 + level * .035,
        color: const Color(0xffaea997),
        roofColor: const Color(0xff6c7a77),
        pitched: true,
      );
      final y = terrain.height(x, c.z - .47);
      mesh.box(
        vm.Vector3(x, y + .36, c.z - .47),
        vm.Vector3(.065, .72, .065),
        i.isEven ? orange : steel,
      );
      mesh.box(
        vm.Vector3(x, y + .61, c.z - .47),
        vm.Vector3(.068, .055, .068),
        walls,
      );
    }
    for (var i = 0; i < level + 2; i++) {
      final x = c.x - .38 + i * .22, z = c.z + .47;
      final y = terrain.height(x, z);
      mesh.box(
        vm.Vector3(x, y + .065, z),
        vm.Vector3(.16, .13, .13),
        i.isEven ? orange : roof,
      );
    }
    final y = terrain.height(c.x + .52, c.z + .05);
    for (final z in [c.z - .13, c.z + .09]) {
      p.part(
        root,
        p.cylinder,
        tank,
        vm.Vector3(c.x + .56, y + .16, z),
        vm.Vector3(.14, .30, .14),
      );
    }
    _pipe(
      root,
      terrain.surfacePoint(c.x + .42, c.z - .23, offset: .25),
      terrain.surfacePoint(c.x + .56, c.z + .09, offset: .25),
      .027,
    );
  }

  void _solar(_CityMesh mesh, CityTerrain terrain, vm.Vector3 c, int level) {
    final rows = level + 3;
    for (var row = 0; row < rows; row++) {
      final z = c.z - .56 + row * (1.10 / (rows - 1));
      for (var col = 0; col < 3; col++) {
        final x = c.x + (col - 1) * .34;
        final y = terrain.height(x, z);
        mesh.box(
          vm.Vector3(x, y + .055, z),
          vm.Vector3(.025, .11, .025),
          steel,
        );
        mesh.tiltedPanel(
          vm.Vector3(x, y + .12, z),
          .29,
          .16,
          const Color(0xff234c66),
          .035,
        );
        mesh.tiltedPanel(
          vm.Vector3(x, y + .123, z),
          .008,
          .16,
          const Color(0xff8eb0ad),
          .035,
        );
      }
    }
    _road(
      mesh,
      terrain,
      c.x - .65,
      c.z,
      c.x + .63,
      c.z,
      width: .052,
      color: paving,
    );
    _building(
      mesh,
      terrain,
      c.x + .56,
      c.z + .03,
      width: .14,
      depth: .22,
      height: .13,
    );
  }

  void _spaceport(
    fs.Node root,
    _CityMesh mesh,
    CityTerrain terrain,
    vm.Vector3 c,
    int level,
  ) {
    _road(
      mesh,
      terrain,
      c.x - .30,
      c.z - .49,
      c.x - .30,
      c.z + .40,
      width: .57,
    );
    _road(
      mesh,
      terrain,
      c.x - .57,
      c.z + .51,
      c.x + .59,
      c.z + .51,
      width: .13,
    );
    for (final x in [-.52, -.09]) {
      _road(
        mesh,
        terrain,
        c.x + x,
        c.z - .36,
        c.x + x,
        c.z + .28,
        width: .013,
        color: stripe,
      );
    }
    final launcher = terrain.surfacePoint(c.x - .30, c.z - .12, offset: .035);
    root.add(
      p.rocket()
        ..position = launcher
        ..scale = vm.Vector3.all(.39),
    );
    _building(
      mesh,
      terrain,
      c.x + .30,
      c.z + .18,
      width: .38,
      depth: .41,
      height: .19,
      pitched: true,
    );
    _building(
      mesh,
      terrain,
      c.x + .31,
      c.z - .36,
      width: .18,
      depth: .20,
      height: .40 + level * .07,
      roofColor: windows,
    );
    for (var i = 0; i < level + 1; i++) {
      final x = c.x + .18 + (i % 2) * .24, z = c.z + .51 - (i ~/ 2) * .13;
      mesh.box(
        terrain.surfacePoint(x, z, offset: .065),
        vm.Vector3(.16, .13, .10),
        orange,
      );
    }
  }

  void _habitat(
    fs.Node root,
    _CityMesh mesh,
    CityTerrain terrain,
    vm.Vector3 c,
    int level,
  ) {
    const lots = [
      (-.35, -.25),
      (.28, -.31),
      (-.22, .35),
      (.41, .25),
      (-.52, .13),
      (.04, -.02),
    ];
    final count = level + 2;
    final doors = <vm.Vector3>[];
    for (var i = 0; i < count; i++) {
      final (dx, dz) = lots[i];
      final x = c.x + dx, z = c.z + dz, y = terrain.height(c.x + dx, c.z + dz);
      final size = i == 0 ? .48 : .38;
      mesh.box(
        vm.Vector3(x, y + .085, z),
        vm.Vector3(size * .82, .17, size * .75),
        walls,
      );
      p.part(
        root,
        p.sphere,
        glass,
        vm.Vector3(x, y + .19, z),
        vm.Vector3(size, .30, size),
      );
      mesh.box(
        vm.Vector3(x, y + .06, z + size * .40),
        vm.Vector3(.13, .12, .16),
        orange,
      );
      doors.add(vm.Vector3(x, y + .09, z));
      if (i > 0) _pipe(root, doors[i - 1], doors[i], .07);
    }
    _road(
      mesh,
      terrain,
      c.x - .61,
      c.z + .57,
      c.x + .41,
      c.z + .58,
      width: .08,
      color: paving,
    );
    final y = terrain.height(c.x + .48, c.z - .02);
    for (var i = 0; i < 2; i++) {
      p.part(
        root,
        p.cylinder,
        tank,
        vm.Vector3(c.x + .52, y + .14, c.z - .07 + i * .17),
        vm.Vector3(.10, .26, .10),
      );
    }
    for (var i = 0; i < 3; i++) {
      final x = c.x - .38 + i * .25, z = c.z - .66;
      mesh.tiltedPanel(
        terrain.surfacePoint(x, z, offset: .085),
        .19,
        .12,
        const Color(0xff234c66),
        .024,
      );
    }
  }

  void _underground(
    fs.Node root,
    _CityMesh mesh,
    CityTerrain terrain,
    vm.Vector3 c,
    int level,
  ) {
    for (var i = 0; i < level + 1; i++) {
      final x = c.x - .38 + i * .27, z = c.z + .28;
      final y = terrain.height(x, z);
      mesh.rock(
        vm.Vector3(x, y + .035, z - .18),
        vm.Vector3(.34, .20, .43),
        const Color(0xffb47a52),
      );
      mesh.box(vm.Vector3(x, y + .13, z), vm.Vector3(.23, .26, .32), walls);
      mesh.box(
        vm.Vector3(x, y + .10, z + .165),
        vm.Vector3(.14, .19, .012),
        windows,
      );
      mesh.box(
        vm.Vector3(x, y + .27, z + .02),
        vm.Vector3(.28, .04, .38),
        orange,
      );
    }
    _road(
      mesh,
      terrain,
      c.x - .59,
      c.z + .51,
      c.x + .55,
      c.z + .51,
      width: .14,
      color: paving,
    );
    for (final x in [-.44, .42]) {
      final y = terrain.height(c.x + x, c.z - .35);
      p.part(
        root,
        p.cylinder,
        tank,
        vm.Vector3(c.x + x, y + .25, c.z - .35),
        vm.Vector3(.09, .50, .09),
      );
      mesh.box(
        vm.Vector3(c.x + x, y + .52, c.z - .35),
        vm.Vector3(.15, .065, .14),
        orange,
      );
    }
    _building(
      mesh,
      terrain,
      c.x + .18,
      c.z - .28,
      width: .31,
      depth: .24,
      height: .18,
    );
  }

  void _greenhouse(
    fs.Node root,
    _CityMesh mesh,
    CityTerrain terrain,
    vm.Vector3 c,
    int level,
  ) {
    final count = level + 2;
    for (var i = 0; i < count; i++) {
      final x = c.x - .48 + i * (1.0 / (count - 1)), z = c.z - .08;
      final y = terrain.height(x, z);
      mesh.box(vm.Vector3(x, y + .06, z), vm.Vector3(.19, .12, .83), walls);
      p.part(
        root,
        p.sphere,
        greenhouseGlass,
        vm.Vector3(x, y + .15, z),
        vm.Vector3(.22, .27, .86),
      );
      for (final dz in [-.28, 0.0, .28]) {
        mesh.box(
          vm.Vector3(x, y + .24, z + dz),
          vm.Vector3(.18, .025, .018),
          walls,
        );
      }
    }
    _road(
      mesh,
      terrain,
      c.x - .60,
      c.z + .47,
      c.x + .59,
      c.z + .47,
      width: .12,
      color: paving,
    );
    _building(
      mesh,
      terrain,
      c.x + .06,
      c.z + .62,
      width: .37,
      depth: .17,
      height: .15,
    );
  }

  void _extractor(
    fs.Node root,
    _CityMesh mesh,
    CityTerrain terrain,
    vm.Vector3 c,
    int level,
  ) {
    final x = c.x - .20,
        z = c.z - .17,
        y = terrain.height(c.x - .20, c.z - .17);
    for (final dx in [-.20, .20]) {
      for (final dz in [-.19, .19]) {
        mesh.beam(
          vm.Vector3(x + dx, y, z + dz),
          vm.Vector3(x, y + .76, z),
          .045,
          orange,
        );
      }
    }
    mesh.beam(
      vm.Vector3(x, y + .11, z),
      vm.Vector3(x, y + .83, z),
      .038,
      steel,
    );
    _building(
      mesh,
      terrain,
      c.x - .21,
      c.z + .43,
      width: .44,
      depth: .23,
      height: .21,
    );
    _road(
      mesh,
      terrain,
      c.x - .61,
      c.z + .19,
      c.x + .53,
      c.z + .19,
      width: .10,
      color: paving,
    );
    for (var i = 0; i < level + 1; i++) {
      final tx = c.x + .39, tz = c.z - .40 + i * .25;
      final ty = terrain.height(tx, tz);
      p.part(
        root,
        p.cylinder,
        tank,
        vm.Vector3(tx, ty + .22, tz),
        vm.Vector3(.19, .44, .19),
      );
      _pipe(
        root,
        vm.Vector3(x, y + .11, z),
        vm.Vector3(tx, ty + .11, tz),
        .038,
      );
    }
  }

  void _pipe(fs.Node root, vm.Vector3 a, vm.Vector3 b, double diameter) {
    final direction = b - a;
    p.part(
      root,
      p.cylinder,
      tank,
      (a + b) * .5,
      vm.Vector3(diameter, direction.length, diameter),
      rotation: vm.Quaternion.fromTwoVectors(
        vm.Vector3(0, 1, 0),
        direction.normalized(),
      ),
    );
  }

  void _reservation(_CityMesh mesh, CityTerrain terrain, vm.Vector3 c) {
    for (final dx in [-.62, .62]) {
      for (final dz in [-.43, .43]) {
        final y = terrain.height(c.x + dx, c.z + dz);
        mesh.box(
          vm.Vector3(c.x + dx, y + .11, c.z + dz),
          vm.Vector3(.025, .22, .025),
          orange,
        );
        mesh.box(
          vm.Vector3(c.x + dx + .047, y + .19, c.z + dz),
          vm.Vector3(.09, .055, .014),
          orange,
        );
      }
    }
  }

  void _construction(
    _CityMesh mesh,
    CityTerrain terrain,
    vm.Vector3 c, {
    required bool upgrade,
  }) {
    _reservation(mesh, terrain, c);
    if (!upgrade) {
      _road(
        mesh,
        terrain,
        c.x - .42,
        c.z - .34,
        c.x - .42,
        c.z + .29,
        width: .23,
        color: paving,
      );
      _road(
        mesh,
        terrain,
        c.x + .19,
        c.z - .29,
        c.x + .19,
        c.z + .34,
        width: .39,
        color: paving,
      );
      final y = terrain.height(c.x, c.z);
      for (final dx in [-.42, .42]) {
        for (final dz in [-.33, .33]) {
          mesh.beam(
            vm.Vector3(c.x + dx, y, c.z + dz),
            vm.Vector3(c.x + dx, y + .42, c.z + dz),
            .029,
            steel,
          );
        }
        mesh.beam(
          vm.Vector3(c.x + dx, y + .42, c.z - .33),
          vm.Vector3(c.x + dx, y + .42, c.z + .33),
          .029,
          steel,
        );
      }
      mesh.beam(
        vm.Vector3(c.x - .42, y + .42, c.z - .33),
        vm.Vector3(c.x + .42, y + .42, c.z - .33),
        .029,
        steel,
      );
    }
    final x = c.x + .56,
        z = c.z - .50,
        y = terrain.height(c.x + .56, c.z - .50);
    mesh.beam(vm.Vector3(x, y, z), vm.Vector3(x, y + .91, z), .045, orange);
    mesh.beam(
      vm.Vector3(x - .79, y + .89, z),
      vm.Vector3(x + .14, y + .89, z),
      .042,
      orange,
    );
    mesh.beam(
      vm.Vector3(x - .72, y + .89, z),
      vm.Vector3(x - .72, y + .47, z),
      .009,
      steel,
    );
    mesh.box(
      vm.Vector3(x + .10, y + .81, z),
      vm.Vector3(.16, .13, .13),
      warmWalls,
    );
    for (var i = 0; i < 3; i++) {
      mesh.box(
        terrain.surfacePoint(c.x - .39 + i * .17, c.z + .58, offset: .045),
        vm.Vector3(.13, .09, .15),
        i.isEven ? orange : steel,
      );
    }
  }

  void _headquarters(fs.Node root, _CityMesh mesh, CityTerrain terrain) {
    // Three irregular blocks occupy the existing strip south of the city.
    // Even roofs and road shoulders stay beyond the southern hex limit z=4.
    const mainStreet = [
      (-2.10, 4.72),
      (-1.12, 4.58),
      (-.22, 4.65),
      (.53, 4.87),
      (1.23, 4.83),
      (1.87, 4.72),
    ];
    for (var i = 1; i < mainStreet.length; i++) {
      _road(
        mesh,
        terrain,
        mainStreet[i - 1].$1,
        mainStreet[i - 1].$2,
        mainStreet[i].$1,
        mainStreet[i].$2,
        width: .12,
      );
    }
    _road(mesh, terrain, -1.04, 4.16, -1.12, 5.44, width: .078);
    _road(mesh, terrain, -.21, 4.19, -.38, 5.40, width: .083);
    _road(mesh, terrain, -1.95, 5.12, .92, 5.29, width: .075);
    const lots = [
      (-1.89, 4.37, .24, .30),
      (-1.47, 4.29, .32, .28),
      (-1.61, 4.87, .21, .31),
      (-1.86, 5.36, .19, .23),
      (-1.28, 5.29, .37, .29),
      (-.76, 4.31, .29, .25),
      (-.70, 4.85, .19, .32),
      (-.57, 5.31, .23, .25),
      (.08, 4.37, .30, .28),
      (.16, 4.98, .22, .35),
      (.54, 5.46, .17, .24),
      (1.01, 5.27, .24, .31),
    ];
    for (var i = 0; i < lots.length; i++) {
      final (x, z, height, width) = lots[i];
      _building(
        mesh,
        terrain,
        x,
        z,
        width: width,
        depth: .23 + (i % 3) * .04,
        height: height,
        color: i.isEven ? walls : warmWalls,
        roofColor: i % 4 == 0 ? const Color(0xff946e49) : roof,
        pitched: i % 3 != 0,
      );
    }
    // The civic/research building is the landmark of the older settlement.
    _building(mesh, terrain, .87, 4.39, width: .50, depth: .38, height: .57);
    _building(mesh, terrain, .49, 4.39, width: .21, depth: .26, height: .22);
    final mast = terrain.surfacePoint(.87, 4.39, offset: .86);
    mesh.box(mast, vm.Vector3(.027, .42, .027), steel);
    p.part(
      root,
      p.sphere,
      tank,
      mast + vm.Vector3(0, .21, 0),
      vm.Vector3(.25, .06, .21),
    );
    _road(mesh, terrain, 1.82, 4.24, 1.82, 5.05, width: .63);
    root.add(
      p.rocket()
        ..position = terrain.surfacePoint(1.82, 4.66, offset: .03)
        ..scale = vm.Vector3.all(.33),
    );
    _tree(mesh, terrain, -2.06, 4.92, scale: .70);
    _tree(mesh, terrain, -.88, 5.54, scale: .77);
    _tree(mesh, terrain, .48, 4.68, scale: .60);
    _tree(mesh, terrain, 1.28, 5.11, scale: .81);
  }
}

/// Static vertex-color geometry keeps hundreds of repeated small structures
/// inexpensive. All colors arrive as sRGB and are converted for linear PBR.
class _CityMesh {
  final _positions = <double>[];
  final _colors = <double>[];
  final _palette = <Color, List<double>>{};

  void triangle(vm.Vector3 a, vm.Vector3 b, vm.Vector3 c, Color color) {
    final linear = _palette.putIfAbsent(
      color,
      () => [_linear(color.r), _linear(color.g), _linear(color.b), 1],
    );
    for (final point in [a, b, c]) {
      _positions.addAll([point.x, point.y, point.z]);
      _colors.addAll(linear);
    }
  }

  double _linear(double value) => value <= .04045
      ? value / 12.92
      : math.pow((value + .055) / 1.055, 2.4).toDouble();

  void quad(
    vm.Vector3 a,
    vm.Vector3 b,
    vm.Vector3 c,
    vm.Vector3 d,
    Color color,
  ) {
    triangle(a, b, c, color);
    triangle(a, c, d, color);
  }

  void box(vm.Vector3 center, vm.Vector3 size, Color color) {
    _orientedBox(
      center,
      vm.Vector3(size.x / 2, 0, 0),
      vm.Vector3(0, size.y / 2, 0),
      vm.Vector3(0, 0, size.z / 2),
      color,
    );
  }

  void _orientedBox(
    vm.Vector3 center,
    vm.Vector3 x,
    vm.Vector3 y,
    vm.Vector3 z,
    Color color,
  ) {
    final v = [
      center - x - y - z,
      center + x - y - z,
      center + x + y - z,
      center - x + y - z,
      center - x - y + z,
      center + x - y + z,
      center + x + y + z,
      center - x + y + z,
    ];
    for (final f in const [
      [0, 3, 2, 1],
      [4, 5, 6, 7],
      [0, 4, 7, 3],
      [1, 2, 6, 5],
      [3, 7, 6, 2],
      [0, 1, 5, 4],
    ]) {
      quad(v[f[0]], v[f[1]], v[f[2]], v[f[3]], color);
    }
  }

  void beam(vm.Vector3 a, vm.Vector3 b, double width, Color color) {
    final axis = b - a;
    if (axis.length < .0001) return;
    final side = axis.cross(
      axis.y.abs() > axis.length * .9
          ? vm.Vector3(0, 0, 1)
          : vm.Vector3(0, 1, 0),
    )..normalize();
    final front = side.cross(axis)..normalize();
    _orientedBox(
      (a + b) * .5,
      side * (width / 2),
      axis * .5,
      front * (width / 2),
      color,
    );
  }

  void cone(vm.Vector3 base, double radius, double height, Color color) {
    final top = base + vm.Vector3(0, height, 0);
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3, b = (i + 1) * math.pi / 3;
      triangle(
        base + vm.Vector3(math.cos(b) * radius, 0, math.sin(b) * radius),
        base + vm.Vector3(math.cos(a) * radius, 0, math.sin(a) * radius),
        top,
        color,
      );
    }
  }

  void rock(vm.Vector3 center, vm.Vector3 size, Color color) {
    final top = center + vm.Vector3(size.x * .10, size.y * .60, -size.z * .13);
    final bottom = center - vm.Vector3(0, size.y * .45, 0);
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3, b = (i + 1) * math.pi / 3;
      final va =
          center +
          vm.Vector3(math.cos(a) * size.x / 2, 0, math.sin(a) * size.z / 2);
      final vb =
          center +
          vm.Vector3(math.cos(b) * size.x / 2, 0, math.sin(b) * size.z / 2);
      triangle(vb, va, top, color);
      triangle(va, vb, bottom, color);
    }
  }

  void tiltedPanel(
    vm.Vector3 center,
    double width,
    double depth,
    Color color,
    double tilt,
  ) {
    quad(
      center + vm.Vector3(-width / 2, -tilt, -depth / 2),
      center + vm.Vector3(-width / 2, tilt, depth / 2),
      center + vm.Vector3(width / 2, tilt, depth / 2),
      center + vm.Vector3(width / 2, -tilt, -depth / 2),
      color,
    );
  }

  void attach(fs.Node root, String name) {
    if (_positions.isEmpty) return;
    root.add(
      fs.Node(
        name: name,
        mesh: fs.Mesh(
          fs.MeshGeometry.fromArrays(
            positions: Float32List.fromList(_positions),
            colors: Float32List.fromList(_colors),
            retainCpuData: false,
          ),
          PlanetModels.material(1, 1, 1),
        ),
      ),
    );
  }
}
