import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'city_geometry.dart';
import 'city_snapshot.dart';
import 'city_surface.dart';
import 'planet_models.dart';

/// Districts grow across the terrain instead of standing on display plinths.
/// The numerous low-poly houses, trees and roads share one baked mesh; domes,
/// tanks and rockets reuse the globe's primitive buffers.
class CityModels {
  final p = PlanetModels();
  final surface = CitySurface();
  final glass = PlanetModels.material(.075, .27, .33, metallic: .32)
    ..roughnessFactor = .28;
  final greenhouseGlass = PlanetModels.material(.12, .28, .18, metallic: .18)
    ..roughnessFactor = .32;
  final tank = PlanetModels.material(.43, .50, .45, metallic: .2);
  static const walls = Color(0xffe6d8b9);
  static const warmWalls = Color(0xffd4bc92);
  static const roof = Color(0xff527780);
  static const windows = Color(0xff284a58);
  static const paving = Color(0xffb7ae95);
  static const asphalt = Color(0xff62645d);
  static const stripe = Color(0xffbab696);
  static const orange = Color(0xffcf833d);
  static const steel = Color(0xff889491);

  fs.Node landscape(CityTerrain terrain, {String? cityId}) {
    final root = fs.Node(name: '円形に切り出した箱庭の地形');
    root.add(fs.Node(mesh: fs.Mesh(terrain.mesh(), surface.ground)));
    root.add(
      fs.Node(
        name: '土と岩が重なる地盤の断面',
        mesh: fs.Mesh(terrain.sideMesh(), surface.soil),
      ),
    );
    if (terrain.earth) {
      root.add(
        fs.Node(
          name: '蛇行する川と入り江の水面',
          mesh: fs.Mesh(surface.waterGeometry(terrain), surface.water),
        )..shadowCastingMode = fs.ShadowCastingMode.off,
      );
    }
    final surroundings = _CityMesh();
    _surroundings(
      surroundings,
      terrain,
      hasHeadquarters: cityId == 'earth_delta',
    );
    if (terrain.hasRiver) _riverbank(surroundings, terrain);
    if (cityId == 'earth_delta') _headquarters(root, surroundings, terrain);
    surroundings.attach(root, '周辺景観と区画外の既存市街');
    _cacheShadows(root);
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
    _cacheShadows(root);
    return root;
  }

  /// This tree never animates or changes mesh while mounted. CityScene removes
  /// and rebuilds it when completion/level changes, invalidating cached shadows.
  /// The flag is per node, so setting it only on the group would do nothing.
  void _cacheShadows(fs.Node node) {
    if (node.mesh != null) node.shadowStatic = true;
    for (final child in node.children) {
      _cacheShadows(child);
    }
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
      if (!terrain.containsLand(x, z, inset: .20) || terrain.isWater(x, z)) {
        continue;
      }
      final y = terrain.height(x, z);
      final ice = plot.terrain == 'ice';
      final color = ice
          ? const Color(0xffbfdbda)
          : terrain.moon
          ? const Color(0xff888b94)
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
    // The countryside is bounded by the cutaway disc. Keep a clean water
    // channel and clear building pads; props share this single static batch.
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
        if (!terrain.containsLand(x, z, inset: .30) ||
            terrain.isWater(x, z) ||
            (terrain.hasRiver && terrain.riverDistance(x, z) < .16)) {
          continue;
        }
        if (hasHeadquarters && z > 5.45 && z < 6.45 && x > -2.45 && x < 2.40) {
          continue;
        }
        final y = terrain.height(x, z);
        if (terrain.earth && y < .025) continue;
        final density = _forestDensity(x, z);
        if (terrain.earth && density > .28 && trees < 100) {
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
            terrain.moon
                ? const Color(0xff878a94)
                : terrain.earth
                ? const Color(0xff7f836a)
                : const Color(0xffa37250),
          );
          rocks++;
        }
      }
    }
  }

  /// Pebbles, reeds and a small timber footbridge explain the watercourse at
  /// both overview and close range. These are scenery, not extra game assets.
  void _riverbank(_CityMesh mesh, CityTerrain terrain) {
    const bridgeX = -.85;
    for (var i = 0; i <= 36; i++) {
      final x = -terrain.landRadius + .35 + i * .36;
      final center = terrain.riverCenterZ(x);
      final halfWidth = terrain.riverHalfWidth(x);
      for (final side in [-1, 1]) {
        final z = center + side * (halfWidth + .13);
        if (!terrain.containsLand(x, z, inset: .24) ||
            terrain.isWater(x, z) ||
            (x - bridgeX).abs() < .30) {
          continue;
        }
        final y = terrain.height(x, z);
        if (i % 3 != 1) {
          for (var pebble = 0; pebble < 3; pebble++) {
            final dx = (pebble - 1) * .060;
            final dz = (_noise(i * 17 + pebble) - .5) * .13;
            final size = .065 + _noise(i * 29 + pebble) * .080;
            mesh.rock(
              terrain.surfacePoint(x + dx, z + dz, offset: .026),
              vm.Vector3(size, size * .55, size * .82),
              pebble.isEven ? const Color(0xffa6aa8a) : const Color(0xff727d68),
            );
          }
        }
        if (i % 3 == 1) {
          for (var stem = 0; stem < 5; stem++) {
            final dx = (stem - 2) * .022;
            final height = .11 + _noise(i * 13 + stem) * .11;
            final base = vm.Vector3(x + dx, y + .012, z);
            final tip = base + vm.Vector3(dx * .3, height, side * .025);
            mesh.beam(base, tip, .012, const Color(0xff718548));
            mesh.beam(
              base + vm.Vector3(0, height * .30, 0),
              base + vm.Vector3(dx * 1.6, height * .75, side * .074),
              .014,
              const Color(0xff89964e),
            );
            if (stem.isEven) {
              mesh.beam(
                tip,
                tip + vm.Vector3(0, .038, 0),
                .024,
                const Color(0xff8d6b43),
              );
            }
          }
        }
      }
      // A narrow bank-side path visually joins the settlement to the bridge.
      if (i > 0) {
        final beforeX = x - .36;
        final beforeZ =
            terrain.riverCenterZ(beforeX) +
            terrain.riverHalfWidth(beforeX) +
            .37;
        final pathZ = center + halfWidth + .37;
        if (terrain.containsLand(x, pathZ, inset: .35) &&
            terrain.containsLand(beforeX, beforeZ, inset: .35)) {
          _road(
            mesh,
            terrain,
            beforeX,
            beforeZ,
            x,
            pathZ,
            width: .065,
            color: const Color(0xffbdac7d),
          );
        }
      }
    }
    _riverBridge(mesh, terrain, bridgeX);
  }

  void _riverBridge(_CityMesh mesh, CityTerrain terrain, double x) {
    final middle = terrain.riverCenterZ(x);
    final halfLength = terrain.riverHalfWidth(x) + .24;
    final northZ = middle - halfLength;
    final southZ = middle + halfLength;
    final deckY =
        math.max(terrain.height(x, northZ), terrain.height(x, southZ)) + .12;
    const timber = Color(0xffa67b4d);
    const rail = Color(0xffd5bd89);
    const stone = Color(0xff8b917b);
    const width = .36;
    // Separate planks leave fine dark seams, and stone abutments meet the bank.
    final planks = (halfLength * 2 / .066).ceil();
    for (var i = 0; i < planks; i++) {
      final z = northZ + (i + .5) * halfLength * 2 / planks;
      mesh.box(
        vm.Vector3(x, deckY, z),
        vm.Vector3(width, .045, halfLength * 2 / planks - .006),
        i.isEven ? timber : const Color(0xffb38b59),
      );
    }
    for (final z in [northZ + .025, southZ - .025]) {
      final ground = terrain.height(x, z);
      mesh.box(
        vm.Vector3(x, (deckY + ground) / 2, z),
        vm.Vector3(width + .055, deckY - ground + .055, .16),
        stone,
      );
    }
    for (final side in [-1, 1]) {
      final rx = x + side * (width / 2 - .012);
      mesh.beam(
        vm.Vector3(rx, deckY - .047, northZ),
        vm.Vector3(rx, deckY - .047, southZ),
        .065,
        timber,
      );
      mesh.beam(
        vm.Vector3(rx, deckY + .19, northZ),
        vm.Vector3(rx, deckY + .19, southZ),
        .026,
        rail,
      );
      for (var post = 0; post < 5; post++) {
        final z = northZ + post * halfLength * .5;
        mesh.beam(
          vm.Vector3(rx, deckY - .02, z),
          vm.Vector3(rx, deckY + .21, z),
          .035,
          timber,
        );
      }
    }
    for (final side in [-1, 1]) {
      final endZ = middle + side * halfLength;
      final rampZ = endZ + side * .25;
      final ramp = [
        vm.Vector3(x - width / 2, deckY + .024, endZ),
        vm.Vector3(x + width / 2, deckY + .024, endZ),
        terrain.surfacePoint(x + width / 2, rampZ, offset: .035),
        terrain.surfacePoint(x - width / 2, rampZ, offset: .035),
      ];
      final top = side > 0 ? ramp.reversed.toList() : ramp;
      mesh.quad(top[0], top[1], top[2], top[3], timber);
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
    if (!terrain.containsLand(x, z, inset: .25) || terrain.isWater(x, z)) {
      return;
    }
    final y = terrain.height(x, z);
    final seed = (x * 171 + z * 293).round();
    mesh.box(
      vm.Vector3(x, y + .14 * scale, z),
      vm.Vector3(.040 * scale, .28 * scale, .040 * scale),
      const Color(0xff766049),
    );
    if (_noise(seed) > .34) {
      // Broadleaf clusters produce an irregular canopy rather than toy cones.
      for (var i = 0; i < 5; i++) {
        final angle = i * 2.4 + _noise(seed) * 2;
        final distance = i == 0 ? 0.0 : .075 * scale;
        final leafColor = Color.lerp(
          color,
          const Color(0xffb1b86a),
          .05 + _noise(seed + i * 13) * .28,
        )!;
        mesh.crown(
          vm.Vector3(
            x + math.cos(angle) * distance,
            y + (.28 + _noise(seed + i * 7) * .11) * scale,
            z + math.sin(angle) * distance,
          ),
          vm.Vector3(
            .22 * scale,
            (.22 + _noise(seed + i) * .07) * scale,
            .21 * scale,
          ),
          leafColor,
          seed + i,
        );
      }
    } else {
      for (var tier = 0; tier < 3; tier++) {
        mesh.cone(
          vm.Vector3(x, y + (.095 + tier * .095) * scale, z),
          (.14 - tier * .031) * scale,
          (.32 - tier * .045) * scale,
          Color.lerp(color, const Color(0xff8b9e52), tier * .10)!,
        );
      }
    }
  }

  void _pavedLot(
    _CityMesh mesh,
    CityTerrain terrain,
    double x,
    double z,
    double width,
    double depth, {
    Color color = paving,
  }) {
    const divisions = 4;
    for (var row = 0; row < divisions; row++) {
      for (var column = 0; column < divisions; column++) {
        final x0 = x - width / 2 + width * column / divisions;
        final z0 = z - depth / 2 + depth * row / divisions;
        final x1 = x0 + width / divisions;
        final z1 = z0 + depth / divisions;
        mesh.quad(
          terrain.surfacePoint(x0, z0, offset: .022),
          terrain.surfacePoint(x0, z1, offset: .022),
          terrain.surfacePoint(x1, z1, offset: .022),
          terrain.surfacePoint(x1, z0, offset: .022),
          Color.lerp(
            color,
            const Color(0xffd8cfb5),
            _noise((x * 37 + z * 79).round() + row * 4 + column) * .13,
          )!,
        );
      }
    }
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
    final steps = (length / .15).ceil();
    void strip(double stripWidth, Color stripColor, double elevation) {
      final sx = -dz / length * stripWidth / 2;
      final sz = dx / length * stripWidth / 2;
      for (var i = 0; i < steps; i++) {
        final x0 = ax + dx * i / steps, z0 = az + dz * i / steps;
        final x1 = ax + dx * (i + 1) / steps;
        final z1 = az + dz * (i + 1) / steps;
        mesh.quad(
          terrain.surfacePoint(x0 - sx, z0 - sz, offset: elevation),
          terrain.surfacePoint(x0 + sx, z0 + sz, offset: elevation),
          terrain.surfacePoint(x1 + sx, z1 + sz, offset: elevation),
          terrain.surfacePoint(x1 - sx, z1 - sz, offset: elevation),
          stripColor,
        );
      }
    }

    if (color == asphalt && width >= .08) {
      strip(width + .056, const Color(0xffbcb49c), .025);
    }
    strip(width, color, .029);
    if (color == asphalt && width >= .105 && width < .30) {
      // Fine broken center lines, with enough spacing to read at close range.
      final sx = -dz / length * .005, sz = dx / length * .005;
      for (var i = 0; i < steps; i += 2) {
        final x0 = ax + dx * (i + .20) / steps;
        final z0 = az + dz * (i + .20) / steps;
        final x1 = ax + dx * (i + .85) / steps;
        final z1 = az + dz * (i + .85) / steps;
        mesh.quad(
          terrain.surfacePoint(x0 - sx, z0 - sz, offset: .033),
          terrain.surfacePoint(x0 + sx, z0 + sz, offset: .033),
          terrain.surfacePoint(x1 + sx, z1 + sz, offset: .033),
          terrain.surfacePoint(x1 - sx, z1 - sz, offset: .033),
          stripe,
        );
      }
    }
  }

  void _streetLamp(_CityMesh mesh, CityTerrain terrain, double x, double z) {
    final y = terrain.height(x, z);
    mesh.box(
      vm.Vector3(x, y + .115, z),
      vm.Vector3(.012, .23, .012),
      const Color(0xff626e67),
    );
    mesh.box(
      vm.Vector3(x + .023, y + .233, z),
      vm.Vector3(.059, .013, .013),
      steel,
    );
    mesh.box(
      vm.Vector3(x + .042, y + .227, z),
      vm.Vector3(.030, .009, .024),
      const Color(0xffefe2ad),
    );
  }

  void _garden(_CityMesh mesh, CityTerrain terrain, double x, double z) {
    final y = terrain.height(x, z);
    _pavedLot(mesh, terrain, x, z, .24, .22);
    mesh.box(
      vm.Vector3(x, y + .035, z),
      vm.Vector3(.185, .055, .15),
      const Color(0xffa89875),
    );
    mesh.box(
      vm.Vector3(x, y + .066, z),
      vm.Vector3(.175, .014, .14),
      const Color(0xff4e6739),
    );
    for (var i = 0; i < 5; i++) {
      mesh.crown(
        vm.Vector3(x - .065 + i * .032, y + .09, z - .022),
        vm.Vector3(.061, .065, .064),
        i.isEven ? const Color(0xff7d9950) : const Color(0xff59773c),
        i,
      );
      mesh.box(
        vm.Vector3(x - .061 + i * .030, y + .087, z + .046),
        vm.Vector3(.016, .018, .017),
        i.isEven ? const Color(0xffd8b557) : const Color(0xffaa6b50),
      );
    }
    // A small park seat makes the courtyard readable at the closest view.
    mesh.box(
      vm.Vector3(x, y + .045, z + .105),
      vm.Vector3(.10, .012, .036),
      const Color(0xff956e49),
    );
    mesh.box(
      vm.Vector3(x, y + .069, z + .123),
      vm.Vector3(.10, .048, .008),
      const Color(0xff956e49),
    );
  }

  void _car(
    _CityMesh mesh,
    CityTerrain terrain,
    double x,
    double z, {
    Color color = const Color(0xffd8d7c5),
  }) {
    final y = terrain.height(x, z) + .036;
    mesh.box(vm.Vector3(x, y + .025, z), vm.Vector3(.115, .034, .055), color);
    mesh.box(
      vm.Vector3(x - .008, y + .047, z),
      vm.Vector3(.064, .024, .049),
      windows,
    );
    mesh.box(
      vm.Vector3(x - .008, y + .061, z),
      vm.Vector3(.048, .007, .049),
      color,
    );
    for (final dx in [-.034, .034]) {
      for (final dz in [-.03, .03]) {
        mesh.box(
          vm.Vector3(x + dx, y + .015, z + dz),
          vm.Vector3(.025, .025, .013),
          const Color(0xff373e39),
        );
      }
    }
    for (final dz in [-.018, .018]) {
      mesh.box(
        vm.Vector3(x + .059, y + .029, z + dz),
        vm.Vector3(.003, .011, .012),
        const Color(0xffece2bc),
      );
    }
  }

  /// Exterior pressure ribs preserve the dome silhouette without transparent
  /// sorting or an extra node per rib. The blue surface stays an opaque proxy.
  void _domeFrame(
    _CityMesh mesh,
    vm.Vector3 center,
    double width,
    double height,
  ) {
    const frameColor = Color(0xffccd9d0);
    for (var rib = 0; rib < 4; rib++) {
      final angle = rib * math.pi / 4;
      vm.Vector3 point(int step) {
        final t = step * math.pi / 10;
        return center +
            vm.Vector3(
              math.cos(angle) * math.cos(t) * width * .51,
              math.sin(t) * height * .51,
              math.sin(angle) * math.cos(t) * width * .51,
            );
      }

      for (var step = 0; step < 10; step++) {
        mesh.beam(point(step), point(step + 1), .012, frameColor);
      }
    }
    for (var i = 0; i < 16; i++) {
      final a = i * math.pi / 8, b = (i + 1) * math.pi / 8;
      mesh.beam(
        center +
            vm.Vector3(math.cos(a) * width * .51, 0, math.sin(a) * width * .51),
        center +
            vm.Vector3(math.cos(b) * width * .51, 0, math.sin(b) * width * .51),
        .022,
        frameColor,
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
    final y = terrain.height(x, z) + .029;
    _pavedLot(mesh, terrain, x, z, width + .075, depth + .065);
    mesh.box(
      vm.Vector3(x, y + .018, z),
      vm.Vector3(width + .028, .070, depth + .028),
      const Color(0xff998f7c),
    );
    mesh.box(
      vm.Vector3(x, y + height / 2, z),
      vm.Vector3(width, height, depth),
      color,
    );
    mesh.box(
      vm.Vector3(x, y + .045, z),
      vm.Vector3(width + .006, .019, depth + .006),
      warmWalls,
    );
    final e = depth / 2 + .026, w = width / 2 + .026;
    if (pitched) {
      final rise = math.min(width, depth) * .40;
      // Full closed gables, fascia and ridge make a roof with thickness.
      mesh.triangle(
        vm.Vector3(x - width / 2, y + height, z + depth / 2),
        vm.Vector3(x - width / 2, y + height + rise, z),
        vm.Vector3(x - width / 2, y + height, z - depth / 2),
        color,
      );
      mesh.triangle(
        vm.Vector3(x + width / 2, y + height, z - depth / 2),
        vm.Vector3(x + width / 2, y + height + rise, z),
        vm.Vector3(x + width / 2, y + height, z + depth / 2),
        color,
      );
      for (final side in [-1.0, 1.0]) {
        for (var course = 0; course < 5; course++) {
          final t0 = course / 5, t1 = (course + 1) / 5;
          final stripColor = Color.lerp(
            roofColor,
            const Color(0xffe2b489),
            course.isEven ? .06 : .0,
          )!;
          final a = vm.Vector3(
            x - w,
            y + height + rise * (1 - t0),
            z + side * e * t0,
          );
          final b = vm.Vector3(
            x - w,
            y + height + rise * (1 - t1),
            z + side * e * t1,
          );
          final c = vm.Vector3(x + w, b.y, b.z);
          final d = vm.Vector3(x + w, a.y, a.z);
          if (side > 0) {
            mesh.quad(a, b, c, d, stripColor);
          } else {
            mesh.quad(d, c, b, a, stripColor);
          }
        }
        mesh.box(
          vm.Vector3(x, y + height - .006, z + side * e),
          vm.Vector3(width + .057, .028, .014),
          roofColor,
        );
      }
      mesh.box(
        vm.Vector3(x, y + height + rise + .006, z),
        vm.Vector3(width + .055, .016, .020),
        roofColor,
      );
      mesh.box(
        vm.Vector3(x + width * .23, y + height + rise * .83, z - depth * .12),
        vm.Vector3(.032, .12, .036),
        warmWalls,
      );
    } else {
      mesh.box(
        vm.Vector3(x, y + height + .015, z),
        vm.Vector3(width + .026, .030, depth + .026),
        roofColor,
      );
      mesh.box(
        vm.Vector3(x, y + height + .030, z),
        vm.Vector3(width - .025, .012, depth - .025),
        Color.lerp(roofColor, const Color(0xff9caca8), .25)!,
      );
      mesh.box(
        vm.Vector3(x + width * .22, y + height + .055, z - depth * .18),
        vm.Vector3(width * .25, .050, depth * .27),
        steel,
      );
    }
    final floors = math.max(1, (height / .13).floor());
    final frontColumns = math.max(2, (width / .083).floor());
    final sideColumns = math.max(2, (depth / .090).floor());
    for (var floor = 0; floor < floors; floor++) {
      final elevation = y + .087 + floor * (height - .06) / floors;
      for (final side in [-1.0, 1.0]) {
        for (var column = 0; column < frontColumns; column++) {
          final wx = x + ((column + .5) / frontColumns - .5) * width * .80;
          mesh.box(
            vm.Vector3(wx, elevation, z + side * (depth / 2 + .002)),
            vm.Vector3(width / frontColumns * .48, .041, .006),
            windows,
          );
          mesh.box(
            vm.Vector3(wx, elevation - .024, z + side * (depth / 2 + .007)),
            vm.Vector3(width / frontColumns * .58, .007, .016),
            const Color(0xffefe4c9),
          );
        }
        for (var column = 0; column < sideColumns; column++) {
          final wz = z + ((column + .5) / sideColumns - .5) * depth * .76;
          mesh.box(
            vm.Vector3(x + side * (width / 2 + .002), elevation, wz),
            vm.Vector3(.006, .039, depth / sideColumns * .46),
            windows,
          );
        }
      }
    }
    // Entry and awning read from the street without adding separate nodes.
    mesh.box(
      vm.Vector3(x, y + .045, z + depth / 2 + .006),
      vm.Vector3(.038, .085, .008),
      const Color(0xff725c46),
    );
    mesh.box(
      vm.Vector3(x, y + .096, z + depth / 2 + .030),
      vm.Vector3(.078, .013, .059),
      roofColor,
    );
    mesh.box(
      vm.Vector3(x, y + .006, z + depth / 2 + .035),
      vm.Vector3(.090, .018, .066),
      paving,
    );
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
      case 'moon_solar':
        _solar(mesh, terrain, c, level);
        break;
      case 'spaceport':
      case 'moon_spaceport':
        _spaceport(root, mesh, terrain, c, level);
        break;
      case 'moon_outpost':
        _moonOutpost(root, mesh, terrain, c, level);
        break;
      case 'space_elevator':
        _spaceElevator(root, mesh, terrain, c, level);
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
      case 'moon_extractor':
        _extractor(root, mesh, terrain, c, level);
        break;
    }
  }

  void _moonOutpost(
    fs.Node root,
    _CityMesh mesh,
    CityTerrain terrain,
    vm.Vector3 c,
    int level,
  ) {
    // Sealed horizontal modules, stores and a dish read as a lunar station,
    // rather than the large glazed habitat domes used for Martian settlements.
    final station = fs.Node(name: '月面基地の気密モジュール');
    root.add(station);
    for (var i = 0; i < level + 1; i++) {
      final x = c.x - .32 + (i % 2) * .60;
      final z = c.z - .25 + (i ~/ 2) * .48;
      final y = terrain.height(x, z);
      p.part(
        station,
        p.cylinder,
        p.white,
        vm.Vector3(x, y + .24, z),
        vm.Vector3(.30, .53, .30),
        rotation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
      );
      mesh.box(vm.Vector3(x, y + .105, z), vm.Vector3(.32, .17, .40), steel);
      mesh.box(
        vm.Vector3(x, y + .24, z + .27),
        vm.Vector3(.11, .09, .014),
        windows,
      );
      if (i > 0) {
        _pipe(
          station,
          terrain.surfacePoint(c.x - .32, c.z, offset: .18),
          vm.Vector3(x, y + .18, z),
          .09,
        );
      }
    }
    final mast = terrain.surfacePoint(c.x + .48, c.z + .40);
    p.part(
      station,
      p.cylinder,
      p.white,
      mast + vm.Vector3(0, .35, 0),
      vm.Vector3(.035, .7, .035),
    );
    p.part(
      station,
      p.sphere,
      p.white,
      mast + vm.Vector3(0, .72, 0),
      vm.Vector3(.29, .05, .29),
      rotation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), .6),
    );
    _road(
      mesh,
      terrain,
      c.x - .65,
      c.z + .55,
      c.x + .65,
      c.z + .55,
      width: .08,
      color: steel,
    );
  }

  void _spaceElevator(
    fs.Node root,
    _CityMesh mesh,
    CityTerrain terrain,
    vm.Vector3 c,
    int level,
  ) {
    final terminal = fs.Node(name: '宇宙エレベーターの地上港とテザー');
    root.add(terminal);
    _building(
      mesh,
      terrain,
      c.x,
      c.z + .27,
      width: .70,
      depth: .46,
      height: .24 + level * .06,
      roofColor: windows,
    );
    final y = terrain.height(c.x, c.z);
    const tower = 1.15;
    for (final dx in [-.25, .25]) {
      mesh.beam(
        vm.Vector3(c.x + dx, y, c.z - .20),
        vm.Vector3(c.x, y + tower, c.z - .20),
        .055,
        steel,
      );
    }
    // The tether continues upward schematically. It deliberately has a fixed
    // visual height, without implying a physical scale or a gameplay effect.
    p.part(
      terminal,
      p.cylinder,
      p.white,
      vm.Vector3(c.x, y + 2.2, c.z - .20),
      vm.Vector3(.019, 4.4, .019),
    );
    p.part(
      terminal,
      p.box,
      p.cyan,
      vm.Vector3(c.x, y + 1.8, c.z - .20),
      vm.Vector3(.15, .25, .13),
    );
    _road(
      mesh,
      terrain,
      c.x - .65,
      c.z + .57,
      c.x + .65,
      c.z + .57,
      width: .14,
    );
  }

  void _housing(_CityMesh mesh, CityTerrain terrain, vm.Vector3 c, int level) {
    _road(mesh, terrain, c.x - .71, c.z, c.x + .71, c.z, width: .13);
    _road(mesh, terrain, c.x, c.z - .75, c.x, c.z + .75, width: .11);
    const lots = [
      (-.25, -.25, .29, .27),
      (.25, -.25, .30, .27),
      (-.25, .25, .30, .27),
      (.25, .25, .29, .27),
      (-.58, -.22, .22, .24),
      (.58, .22, .22, .24),
      (-.20, -.61, .24, .23),
      (.20, .61, .24, .23),
      (.48, -.49, .24, .22),
      (-.48, .49, .24, .22),
      (.20, -.61, .24, .23),
      (-.20, .61, .24, .23),
      (-.59, .14, .20, .22),
      (.59, -.14, .20, .22),
    ];
    final count = [0, 10, 12, 14][level];
    const roofColors = [
      Color(0xffac6441),
      Color(0xffbd7b4d),
      Color(0xff695f52),
      Color(0xff527780),
      Color(0xff995333),
    ];
    const wallColors = [walls, warmWalls, Color(0xffddc69e), Color(0xffece0c4)];
    for (var i = 0; i < count; i++) {
      final (x, z, width, depth) = lots[i];
      _building(
        mesh,
        terrain,
        c.x + x,
        c.z + z,
        width: width,
        depth: depth,
        height: .21 + (i % 3) * .043 + (level - 1) * .072,
        color: wallColors[i % wallColors.length],
        roofColor: roofColors[i % roofColors.length],
        pitched: i % 4 != 3 || level == 1,
      );
    }
    _garden(mesh, terrain, c.x - .51, c.z - .51);
    _garden(mesh, terrain, c.x + .51, c.z + .51);
    _car(mesh, terrain, c.x - .45, c.z - .027);
    if (level > 1) {
      _car(
        mesh,
        terrain,
        c.x + .44,
        c.z + .027,
        color: const Color(0xffb66843),
      );
    }
    // Street corners remain gardens at every level, rather than spare empty ground.
    for (final corner in [(-.72, .24), (.71, -.26), (-.43, -.58), (.43, .58)]) {
      _tree(
        mesh,
        terrain,
        c.x + corner.$1,
        c.z + corner.$2,
        scale: .63,
        color: const Color(0xff638447),
      );
    }
    for (final lamp in [(-.10, -.50), (.10, .50), (-.48, .10), (.48, -.10)]) {
      _streetLamp(mesh, terrain, c.x + lamp.$1, c.z + lamp.$2);
    }
  }

  void _campus(
    fs.Node root,
    _CityMesh mesh,
    CityTerrain terrain,
    vm.Vector3 c,
    int level, {
    required bool mars,
  }) {
    _pavedLot(
      mesh,
      terrain,
      c.x,
      c.z,
      1.18,
      1.12,
      color: const Color(0xffc5bba0),
    );
    for (var i = 0; i < 5; i++) {
      _road(
        mesh,
        terrain,
        c.x - .54 + i * .27,
        c.z - .54,
        c.x - .54 + i * .27,
        c.z + .54,
        width: .013,
        color: const Color(0xffa89c83),
      );
    }
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
    final frontY = terrain.height(c.x - .24, c.z - .25);
    mesh.box(
      vm.Vector3(c.x - .24, frontY + .18, c.z - .101),
      vm.Vector3(.33, .24, .015),
      const Color(0xff4f8a9a),
    );
    for (var i = 0; i < 5; i++) {
      mesh.box(
        vm.Vector3(c.x - .39 + i * .075, frontY + .18, c.z - .086),
        vm.Vector3(.008, .26, .012),
        walls,
      );
    }
    _streetLamp(mesh, terrain, c.x - .53, c.z + .04);
    _streetLamp(mesh, terrain, c.x + .49, c.z + .47);
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
    _domeFrame(
      mesh,
      vm.Vector3(
        c.x - .24,
        terrain.height(c.x - .24, c.z - .25) + .35 + level * .065,
        c.z - .25,
      ),
      .28,
      .17,
    );
    if (!mars) {
      _garden(mesh, terrain, c.x + .31, c.z + .11);
      _car(mesh, terrain, c.x - .30, c.z + .11, color: const Color(0xff527b8b));
    }
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
    _pavedLot(
      mesh,
      terrain,
      c.x,
      c.z,
      1.30,
      1.12,
      color: const Color(0xffaaa18a),
    );
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
    for (var container = 0; container < level + 2; container++) {
      final x = c.x - .38 + container * .22, z = c.z + .47;
      final y = terrain.height(x, z);
      for (var rib = 0; rib < 4; rib++) {
        mesh.box(
          vm.Vector3(x - .059 + rib * .039, y + .065, z + .068),
          vm.Vector3(.008, .115, .008),
          container.isEven ? const Color(0xffeab56f) : const Color(0xff829ea0),
        );
      }
    }
    _streetLamp(mesh, terrain, c.x - .58, c.z + .38);
    _streetLamp(mesh, terrain, c.x + .58, c.z + .38);
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
    _pavedLot(
      mesh,
      terrain,
      c.x,
      c.z,
      1.24,
      1.29,
      color: const Color(0xffada781),
    );
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
          const Color(0xff245771),
          .035,
        );
        for (final offset in [-.096, -.048, .048, .096]) {
          mesh.tiltedPanel(
            vm.Vector3(x + offset, y + .124, z),
            .004,
            .16,
            const Color(0xff799daa),
            .035,
          );
        }
        mesh.tiltedPanel(
          vm.Vector3(x, y + .125, z),
          .29,
          .004,
          const Color(0xff799daa),
          .001,
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
      _domeFrame(mesh, vm.Vector3(x, y + .19, z), size, .30);
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
        for (var segment = 0; segment < 8; segment++) {
          final a = segment * math.pi / 8, b = (segment + 1) * math.pi / 8;
          // Ellipsoidal cross sections narrow towards either end of the tunnel.
          final width = .113 * math.sqrt(1 - dz * dz / (.43 * .43));
          final rise = .139 * math.sqrt(1 - dz * dz / (.43 * .43));
          mesh.beam(
            vm.Vector3(
              x + math.cos(a) * width,
              y + .15 + math.sin(a) * rise,
              z + dz,
            ),
            vm.Vector3(
              x + math.cos(b) * width,
              y + .15 + math.sin(b) * rise,
              z + dz,
            ),
            .011,
            walls,
          );
        }
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
    // The older settlement sits on the southern bank inside the circular cut.
    // Its compact curved street leaves the whole river and 25 building plots
    // visible; the footbridge joins it to the development area.
    const mainStreet = [
      (-1.96, 6.03),
      (-1.24, 6.09),
      (-.50, 6.13),
      (.20, 6.13),
      (.90, 6.06),
      (1.83, 6.02),
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
    const bridgeX = -.85;
    _road(
      mesh,
      terrain,
      bridgeX,
      terrain.riverCenterZ(bridgeX) + terrain.riverHalfWidth(bridgeX) + .48,
      bridgeX,
      6.10,
      width: .078,
      color: const Color(0xffbdac7d),
    );
    const lots = [
      (-1.82, 5.73, .26, .29),
      (-1.38, 5.80, .32, .28),
      (-.95, 5.85, .24, .27),
      (-.49, 5.87, .27, .30),
      (-.03, 5.86, .29, .25),
      (.42, 5.83, .25, .31),
      (-1.42, 6.34, .29, .26),
      (-.97, 6.40, .23, .28),
      (-.49, 6.41, .26, .32),
      (.01, 6.39, .21, .26),
      (.46, 6.34, .24, .31),
      (1.03, 6.29, .26, .29),
    ];
    for (var i = 0; i < lots.length; i++) {
      final (x, z, height, width) = lots[i];
      _building(
        mesh,
        terrain,
        x,
        z,
        width: width,
        depth: .23 + (i % 3) * .025,
        height: height,
        color: i.isEven ? walls : warmWalls,
        roofColor: i % 4 == 0 ? roof : const Color(0xffa26d4b),
        pitched: i % 3 != 0,
      );
    }
    // Civic tower and launch apron remain the original settlement landmarks.
    _building(mesh, terrain, 1.05, 5.72, width: .48, depth: .36, height: .57);
    _building(mesh, terrain, .71, 5.72, width: .19, depth: .26, height: .22);
    final mast = terrain.surfacePoint(1.05, 5.72, offset: .86);
    mesh.box(mast, vm.Vector3(.027, .42, .027), steel);
    p.part(
      root,
      p.sphere,
      tank,
      mast + vm.Vector3(0, .21, 0),
      vm.Vector3(.25, .06, .21),
    );
    _road(mesh, terrain, 1.92, 5.66, 1.92, 6.29, width: .63);
    root.add(
      p.rocket()
        ..position = terrain.surfacePoint(1.92, 5.99, offset: .03)
        ..scale = vm.Vector3.all(.33),
    );
    _tree(mesh, terrain, -2.19, 5.72, scale: .70);
    _tree(mesh, terrain, -1.89, 6.35, scale: .72);
    _tree(mesh, terrain, .76, 6.40, scale: .62);
    _tree(mesh, terrain, 1.47, 6.20, scale: .75);
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

  /// Three staggered rings soften silhouettes while preserving a baked mesh.
  void crown(vm.Vector3 center, vm.Vector3 size, Color color, int seed) {
    const segments = 7;
    final rings = <List<vm.Vector3>>[];
    for (var row = 0; row < 3; row++) {
      final radius = row == 1 ? 1.0 : .65;
      rings.add([
        for (var i = 0; i < segments; i++)
          center +
              vm.Vector3(
                math.cos(i * math.pi * 2 / segments + row * .19) *
                    size.x *
                    .5 *
                    radius,
                (row - 1) * size.y * .34,
                math.sin(i * math.pi * 2 / segments + row * .19) *
                    size.z *
                    .5 *
                    radius,
              ),
      ]);
    }
    for (var i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      final facet = Color.lerp(
        color,
        const Color(0xffc2bb65),
        ((i * 3 + seed).abs() % 7) * .018,
      )!;
      triangle(
        rings[0][i],
        rings[0][next],
        center - vm.Vector3(0, size.y * .50, 0),
        facet,
      );
      for (var row = 0; row < 2; row++) {
        quad(
          rings[row][next],
          rings[row][i],
          rings[row + 1][i],
          rings[row + 1][next],
          facet,
        );
      }
      triangle(
        rings[2][next],
        rings[2][i],
        center + vm.Vector3(0, size.y * .52, 0),
        facet,
      );
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
