import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'planet_geometry.dart';

/// A visual snapshot supplied by the UI. No simulation runs in the renderer.
@immutable
class SceneCity {
  const SceneCity({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.development = 0,
    this.isActive = true,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int development;
  final bool isActive;

  bool hasSameAppearance(SceneCity other) =>
      id == other.id &&
      name == other.name &&
      latitude == other.latitude &&
      longitude == other.longitude &&
      development == other.development &&
      isActive == other.isActive;
}

/// Shared primitive buffers keep the many small buildings inexpensive.
class PlanetModels {
  final box = fs.CuboidGeometry(vm.Vector3.all(1));
  final sphere = fs.SphereGeometry(radius: 0.5, segments: 16, rings: 8);
  final cylinder = fs.CylinderGeometry(radialSegments: 16);
  final cone = fs.CylinderGeometry(topRadius: 0, radialSegments: 16);
  final nozzle = fs.CylinderGeometry(topRadius: 0.28, radialSegments: 12);
  final ring = fs.TorusGeometry(
    radius: 0.5,
    tubeRadius: 0.018,
    radialSegments: 40,
    tubularSegments: 5,
  );
  final orbitRing = fs.TorusGeometry(
    radius: 4,
    tubeRadius: 0.02,
    radialSegments: 80,
    tubularSegments: 4,
  );
  final rock = fs.IcosphereGeometry(radius: 0.5, subdivisions: 0);
  final white = material(0.79, 0.85, 0.84, metallic: 0.2);
  final navy = material(0.025, 0.06, 0.09, metallic: 0.25);
  final blue = material(0.035, 0.25, 0.40, metallic: 0.45);
  final orange = material(0.98, 0.40, 0.10, metallic: 0.15);
  final concrete = material(0.12, 0.20, 0.22);
  final cyan = material(0.11, 0.74, 0.72)
    ..emissiveFactor = vm.Vector4(0.04, 0.26, 0.23, 1);
  final ice = material(0.71, 0.83, 0.83);
  final dust = material(0.47, 0.20, 0.105);
  final darkDust = material(0.28, 0.105, 0.055);

  static fs.PhysicallyBasedMaterial material(
    double r,
    double g,
    double b, {
    double metallic = 0,
  }) => fs.PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(r, g, b, 1)
    ..metallicFactor = metallic
    ..roughnessFactor = 0.8;

  fs.Node part(
    fs.Node parent,
    fs.Geometry geometry,
    fs.Material material,
    vm.Vector3 position,
    vm.Vector3 scale, {
    vm.Quaternion? rotation,
  }) {
    final node = fs.Node(mesh: fs.Mesh(geometry, material))
      ..position = position
      ..scale = scale;
    if (rotation != null) node.rotation = rotation;
    parent.add(node);
    return node;
  }

  fs.Node surface(double lat, double lon, {double radius = 3.1}) {
    final point = planetPoint(lat, lon, radius);
    return fs.Node()
      ..position = point
      ..rotation = vm.Quaternion.fromTwoVectors(
        vm.Vector3(0, 1, 0),
        point.normalized(),
      );
  }

  fs.Node globe(bool earth) {
    final root = fs.Node(name: earth ? '地球' : '火星');
    root.add(
      fs.Node(
        mesh: fs.Mesh(makePlanetGeometry(earth: earth), material(1, 1, 1)),
      ),
    );
    if (earth) {
      // Small broken cloud bands leave the continental silhouettes readable.
      for (final band in const [
        (51.0, -32.0),
        (13.0, -48.0),
        (-31.0, -12.0),
        (46.0, 160.0),
        (-22.0, 79.0),
        (57.0, 83.0),
      ]) {
        final cloud = surface(band.$1, band.$2, radius: 3.14);
        for (var j = 0; j < 3; j++) {
          part(
            cloud,
            rock,
            white,
            vm.Vector3((j - 1) * 0.15, 0, 0),
            vm.Vector3(0.38, 0.075, 0.13 + j * 0.025),
          );
        }
        root.add(cloud);
      }
    } else {
      // Flattened dark bowls with raised rims read clearly at globe scale.
      for (final crater in const [
        (-12.0, -35.0, 0.42),
        (24.0, -64.0, 0.30),
        (-40.0, -105.0, 0.25),
        (3.0, 21.0, 0.20),
        (48.0, 45.0, 0.21),
        (-13.0, 109.0, 0.29),
        (26.0, 163.0, 0.35),
        (-49.0, 19.0, 0.32),
        (57.0, -159.0, 0.23),
      ]) {
        final bowl = surface(crater.$1, crater.$2, radius: 3.08);
        part(
          bowl,
          sphere,
          darkDust,
          vm.Vector3.zero(),
          vm.Vector3(crater.$3 * 1.8, 0.08, crater.$3 * 1.8),
        );
        part(
          bowl,
          ring,
          dust,
          vm.Vector3(0, 0.037, 0),
          vm.Vector3.all(crater.$3 * 1.8),
        );
        root.add(bowl);
      }
    }
    return root;
  }

  fs.Node city(
    SceneCity city, {
    required bool earth,
    required bool selected,
    bool cargo = false,
  }) {
    final root = surface(city.latitude, city.longitude, radius: 3.11)
      ..name = city.name;
    // These are bounded visual detail levels, not game progression rules.
    // A fully upgraded 25-plot city reaches 75; intermediate investment still
    // changes building height and footprint after the next mesh count cap.
    final development = city.isActive ? city.development.clamp(0, 75) : 0;
    final maturity = development / 75;
    final tier = switch (development) {
      >= 65 => 6,
      >= 45 => 5,
      >= 25 => 4,
      >= 12 => 3,
      >= 5 => 2,
      > 0 => 1,
      _ => 0,
    };
    final footprint = 0.85 + maturity * 0.52;
    final base = city.isActive ? concrete : darkDust;
    part(
      root,
      cylinder,
      base,
      vm.Vector3(0, 0.025, 0),
      vm.Vector3(footprint, 0.06, footprint),
    );
    part(
      root,
      ring,
      selected ? cyan : orange,
      vm.Vector3(0, 0.07, 0),
      vm.Vector3.all(footprint + 0.06),
    );
    if (!city.isActive) {
      // Surveyed sites remain different from established settlements.
      part(
        root,
        cylinder,
        white,
        vm.Vector3(0, 0.13, 0),
        vm.Vector3(0.018, 0.24, 0.018),
      );
      part(
        root,
        box,
        orange,
        vm.Vector3(0.07, 0.22, 0),
        vm.Vector3(0.13, 0.08, 0.012),
      );
      return root;
    }
    final blocks = fs.Node(name: '街区')
      ..scale = vm.Vector3(1 + maturity * 0.25, 1, 1 + maturity * 0.25);
    root.add(blocks);
    part(
      blocks,
      box,
      white,
      vm.Vector3(0, 0.063, 0),
      vm.Vector3(0.62 + maturity * 0.25, 0.01, 0.035),
    );
    part(
      blocks,
      box,
      white,
      vm.Vector3(-0.025, 0.063, 0),
      vm.Vector3(0.035, 0.01, 0.65 + maturity * 0.20),
    );
    if (earth) {
      // Fill the core first, then a second ring of blocks. At most 16 towers
      // (48 shared-geometry nodes), with a changing skyline through level 75.
      const lots = [
        (-0.17, -0.17),
        (0.02, -0.18),
        (0.20, -0.17),
        (-0.16, 0.02),
        (0.03, 0.03),
        (0.21, 0.03),
        (-0.17, 0.21),
        (0.02, 0.21),
        (-0.33, -0.11),
        (0.36, -0.11),
        (-0.31, 0.12),
        (0.35, 0.12),
        (-0.16, -0.34),
        (0.06, -0.35),
        (0.22, -0.31),
        (-0.31, -0.30),
      ];
      final count = development < 5 ? 3 + development : 8 + (tier - 2) * 2;
      for (var i = 0; i < count; i++) {
        final central = i == 1 || i == 4;
        final height =
            0.15 + (i % 3) * 0.065 + maturity * (central ? 0.43 : 0.20);
        _building(blocks, lots[i].$1, lots[i].$2, height);
        if (central && tier >= 4) {
          part(
            blocks,
            box,
            cyan,
            vm.Vector3(lots[i].$1, height + 0.10, lots[i].$2),
            vm.Vector3(0.09, 0.035, 0.07),
          );
        }
      }
      _solar(blocks, -0.20, 0.35);
      if (tier >= 3) _solar(blocks, -0.36, 0.32);
      final port = fs.Node()
        ..position = vm.Vector3(0.25, 0.07, 0.32)
        ..scale = vm.Vector3.all(0.20 + maturity * 0.025);
      blocks.add(port);
      part(port, cylinder, navy, vm.Vector3.zero(), vm.Vector3(1.2, 0.04, 1.2));
      port.add(rocket()..scale = vm.Vector3.all(0.33));
    } else {
      // A robot-only outpost has no dome. Later growth increases both the
      // dome cluster and its support systems, capped at eight modules.
      final count = development == 0
          ? 0
          : development < 5
          ? development
          : tier + 2;
      const lots = [
        (-0.15, -0.17),
        (0.15, -0.17),
        (-0.15, 0.09),
        (0.15, 0.09),
        (-0.32, -0.35),
        (0.0, -0.38),
        (0.32, -0.35),
        (0.36, 0.12),
      ];
      final domeSize = 1 + maturity * 0.16;
      for (var i = 0; i < count; i++) {
        final (x, z) = lots[i];
        part(
          blocks,
          cylinder,
          white,
          vm.Vector3(x, 0.12, z),
          vm.Vector3(0.23 * domeSize, 0.14, 0.23 * domeSize),
        );
        part(
          blocks,
          sphere,
          blue,
          vm.Vector3(x, 0.21 + maturity * 0.025, z),
          vm.Vector3(0.25 * domeSize, 0.23 + maturity * 0.08, 0.25 * domeSize),
        );
        part(
          blocks,
          box,
          orange,
          vm.Vector3(x, 0.11, z + 0.12),
          vm.Vector3(0.065, 0.085, 0.08),
        );
        if (i > 0 && tier >= 3) {
          final (px, pz) = lots[i - 1];
          final start = vm.Vector3(px, 0.11, pz);
          final end = vm.Vector3(x, 0.11, z);
          final direction = end - start;
          part(
            blocks,
            cylinder,
            white,
            (start + end) * 0.5,
            vm.Vector3(0.04, direction.length, 0.04),
            rotation: vm.Quaternion.fromTwoVectors(
              vm.Vector3(0, 1, 0),
              direction.normalized(),
            ),
          );
        }
      }
      final arrays = tier >= 5
          ? 4
          : tier >= 3
          ? 3
          : 2;
      for (var i = 0; i < arrays; i++) {
        _solar(blocks, (i - (arrays - 1) / 2) * 0.21, 0.34);
      }
      // Water/air stores, a greenhouse and a comms dish distinguish mature
      // settlements without introducing more than 65 mesh nodes per city.
      if (tier >= 2) {
        for (var i = 0; i < (tier >= 5 ? 3 : 2); i++) {
          part(
            blocks,
            cylinder,
            ice,
            vm.Vector3(-0.36, 0.16, -0.08 + i * 0.12),
            vm.Vector3(0.08, 0.20 + maturity * 0.08, 0.08),
          );
        }
      }
      if (tier >= 4) {
        part(
          blocks,
          box,
          white,
          vm.Vector3(0.28, 0.12, -0.02),
          vm.Vector3(0.19, 0.10, 0.14),
        );
        part(
          blocks,
          sphere,
          cyan,
          vm.Vector3(0.28, 0.18, -0.02),
          vm.Vector3(0.21, 0.16, 0.15),
        );
      }
      if (tier >= 6) {
        part(
          blocks,
          cylinder,
          white,
          vm.Vector3(0.40, 0.29, -0.11),
          vm.Vector3(0.025, 0.43, 0.025),
        );
        part(
          blocks,
          sphere,
          white,
          vm.Vector3(0.40, 0.51, -0.11),
          vm.Vector3(0.17, 0.04, 0.17),
          rotation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.5),
        );
      }
      if (cargo) {
        part(
          blocks,
          box,
          orange,
          vm.Vector3(0.24, 0.12, 0.02),
          vm.Vector3(0.16, 0.11, 0.13),
        );
        part(
          blocks,
          box,
          white,
          vm.Vector3(0.24, 0.18, 0.02),
          vm.Vector3(0.18, 0.02, 0.14),
        );
      }
    }
    // The common mast also gains height with the surrounding skyline.
    final mastHeight = 0.34 + maturity * 0.27;
    part(
      blocks,
      cylinder,
      white,
      vm.Vector3(0.24, 0.06 + mastHeight / 2, -0.22),
      vm.Vector3(0.02, mastHeight, 0.02),
    );
    part(
      blocks,
      sphere,
      cyan,
      vm.Vector3(0.24, 0.06 + mastHeight, -0.22),
      vm.Vector3.all(0.075),
    );
    return root;
  }

  void _building(fs.Node root, double x, double z, double height) {
    part(
      root,
      box,
      white,
      vm.Vector3(x, 0.065 + height / 2, z),
      vm.Vector3(0.14, height, 0.12),
    );
    part(
      root,
      box,
      navy,
      vm.Vector3(x, 0.07 + height, z),
      vm.Vector3(0.16, 0.025, 0.14),
    );
    part(
      root,
      box,
      blue,
      vm.Vector3(x, 0.07 + height * 0.64, z - 0.061),
      vm.Vector3(0.105, 0.048, 0.008),
    );
  }

  void _solar(fs.Node root, double x, double z) {
    part(
      root,
      box,
      blue,
      vm.Vector3(x, 0.11, z),
      vm.Vector3(0.23, 0.023, 0.14),
      rotation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -0.2),
    );
    for (var i = -1; i <= 1; i++) {
      part(
        root,
        box,
        white,
        vm.Vector3(x + i * 0.07, 0.123, z),
        vm.Vector3(0.006, 0.009, 0.13),
      );
    }
  }

  fs.Node rocket() {
    final root = fs.Node(name: '多段式輸送ロケット');
    part(
      root,
      cylinder,
      white,
      vm.Vector3(0, 0.88, 0),
      vm.Vector3(0.30, 1.44, 0.30),
    );
    part(
      root,
      cone,
      white,
      vm.Vector3(0, 1.86, 0),
      vm.Vector3(0.30, 0.54, 0.30),
    );
    for (final y in [0.27, 0.76, 1.40, 1.60]) {
      part(
        root,
        cylinder,
        navy,
        vm.Vector3(0, y, 0),
        vm.Vector3(0.308, 0.05, 0.308),
      );
    }
    part(
      root,
      cylinder,
      orange,
      vm.Vector3(0, 1.26, 0),
      vm.Vector3(0.313, 0.12, 0.313),
    );
    part(
      root,
      box,
      navy,
      vm.Vector3(0, 1.49, -0.147),
      vm.Vector3(0.11, 0.09, 0.012),
    );
    part(
      root,
      nozzle,
      navy,
      vm.Vector3(0, 0.095, 0),
      vm.Vector3(0.29, 0.19, 0.29),
    );
    // Paired booster stages have their own nose cones, seams and engines.
    for (final side in [-1.0, 1.0]) {
      final x = side * 0.245;
      part(
        root,
        cylinder,
        white,
        vm.Vector3(x, 0.57, 0),
        vm.Vector3(0.17, 0.89, 0.17),
      );
      part(
        root,
        cone,
        orange,
        vm.Vector3(x, 1.12, 0),
        vm.Vector3(0.17, 0.23, 0.17),
      );
      part(
        root,
        cylinder,
        orange,
        vm.Vector3(x, 0.38, 0),
        vm.Vector3(0.177, 0.10, 0.177),
      );
      part(
        root,
        nozzle,
        navy,
        vm.Vector3(x, 0.075, 0),
        vm.Vector3(0.17, 0.15, 0.17),
      );
      part(
        root,
        box,
        white,
        vm.Vector3(side * 0.32, 0.26, 0),
        vm.Vector3(0.20, 0.26, 0.055),
        rotation: vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), side * -0.40),
      );
    }
    // Fore/aft fins, conduits and a payload hatch remain visible from any view.
    for (final side in [-1.0, 1.0]) {
      part(
        root,
        box,
        orange,
        vm.Vector3(0, 0.26, side * 0.19),
        vm.Vector3(0.045, 0.29, 0.22),
        rotation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), side * 0.35),
      );
      part(
        root,
        cylinder,
        navy,
        vm.Vector3(0.07, 0.98, side * 0.148),
        vm.Vector3(0.018, 0.69, 0.018),
      );
    }
    return root;
  }

  fs.Node orbit() {
    final root = fs.Node(name: '輸送軌道の概念表示')
      ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.43);
    part(
      root,
      orbitRing,
      material(0.08, 0.30, 0.36),
      vm.Vector3.zero(),
      vm.Vector3.all(1),
    );
    return root;
  }
}
