import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'city_snapshot.dart';

/// One coordinate system for the land mesh, buildings, boundaries and picking.
/// Geography is an authored game map, not surveyed Earth/Mars elevation data.
class CityTerrain {
  CityTerrain({
    required this.earth,
    required this.columns,
    required this.rows,
    required this.plots,
  }) : centers = [
         for (final plot in plots)
           vm.Vector3(
             ((plot.index % columns) +
                     ((plot.index ~/ columns).isOdd ? .5 : 0) -
                     (columns - 1) / 2 -
                     .2) *
                 math.sqrt(3),
             0,
             ((plot.index ~/ columns) - (rows - 1) / 2) * 1.5,
           ),
       ];

  final bool earth;
  final int columns, rows;
  final List<ScenePlot> plots;
  final List<vm.Vector3> centers;

  double get halfWidth => columns * math.sqrt(3) / 2 + 2.6;
  double get halfDepth => rows * .75 + 2.5;
  bool get hasCoast => earth && plots.any((plot) => plot.terrain == 'coast');

  vm.Vector3 center(int index) {
    final offset = plots.indexWhere((plot) => plot.index == index);
    final point = centers[offset];
    return vm.Vector3(point.x, height(point.x, point.z), point.z);
  }

  List<vm.Vector3> boundary(int index) {
    final point = center(index);
    return [
      for (var corner = 0; corner < 6; corner++)
        surfacePoint(
          point.x + math.cos((corner * 60 - 30) * math.pi / 180),
          point.z + math.sin((corner * 60 - 30) * math.pi / 180),
          offset: .035,
        ),
    ];
  }

  vm.Vector3 surfacePoint(double x, double z, {double offset = 0}) =>
      vm.Vector3(x, height(x, z) + offset, z);

  double _terrainHeight(String terrain) => switch (terrain) {
    'ridge' => earth ? .80 : .90,
    'mineral' => .40,
    'ice' => .17,
    'coast' => .075,
    'crater' => -.08,
    _ => .22,
  };

  double height(double x, double z) {
    var sum = 0.0;
    var weights = 0.0;
    var closestDistance = double.infinity;
    var closest = 0;
    var craterRim = 0.0;
    for (var i = 0; i < centers.length; i++) {
      final point = centers[i];
      final distance =
          (x - point.x) * (x - point.x) + (z - point.z) * (z - point.z);
      final weight = math.exp(-distance * .9);
      if (!earth && plots[i].terrain == 'crater') {
        // Each crater contributes continuously on both sides of a plot edge.
        // A nearest-terrain gate would jump when a shared vertex rounds to the
        // neighboring cell. Max keeps overlapping rims bounded and continuous.
        craterRim = math.max(
          craterRim,
          .34 * math.exp(-math.pow((math.sqrt(distance) - .80) / .17, 2)),
        );
      }
      weights += weight;
      sum += _terrainHeight(plots[i].terrain) * weight;
      if (distance < closestDistance) {
        closestDistance = distance;
        closest = i;
      }
    }
    // Fade smoothly into the surrounding countryside. A hard minimum-weight
    // cutoff produces visible cliffs where the city ends.
    var elevation = (sum + .18 * .04) / (weights + .04);
    final distance = math.sqrt(closestDistance);
    // Flatten only the building footprint, while slopes connect the plots.
    final footprint = ((.80 - distance) / .36).clamp(0.0, 1.0);
    elevation =
        elevation * (1 - footprint) +
        _terrainHeight(plots[closest].terrain) * footprint;
    elevation +=
        (1 - footprint) *
        (.10 * math.sin(x * 2.1 + z) + .07 * math.cos(z * 2.7 - x));
    elevation += craterRim;
    if (hasCoast) {
      final shore = -columns * math.sqrt(3) / 2 + .02 + .13 * math.sin(z * 1.4);
      final sea = ((shore - x) / .75).clamp(0.0, 1.0);
      elevation = elevation * (1 - sea) - .28 * sea;
    }
    return elevation;
  }

  Color colorAt(double x, double z) {
    var distance = double.infinity;
    var terrain = 'plain';
    for (var i = 0; i < centers.length; i++) {
      final point = centers[i];
      final next =
          (x - point.x) * (x - point.x) + (z - point.z) * (z - point.z);
      if (next < distance) {
        distance = next;
        terrain = plots[i].terrain;
      }
    }
    if (hasCoast && height(x, z) < .015) {
      return height(x, z) < -.15
          ? const Color(0xff174b64)
          : const Color(0xff34757f);
    }
    final base = switch (terrain) {
      'coast' => const Color(0xffa69c6f),
      'ice' => const Color(0xff9bafba),
      'mineral' => earth ? const Color(0xff77715b) : const Color(0xff875d48),
      'ridge' => earth ? const Color(0xff6b7962) : const Color(0xffa2694c),
      'crater' => const Color(0xff674c40),
      _ => earth ? const Color(0xff57775a) : const Color(0xffaa7153),
    };
    final variation = .5 + .5 * math.sin(x * 3.7 + z * 6.1);
    return Color.lerp(base, const Color(0xffc9b38f), variation * .12)!;
  }

  fs.MeshGeometry mesh() {
    final positions = <double>[];
    final colors = <double>[];
    // Keep the city detailed, and use a coarse apron to fill wide viewports.
    // Plot coordinates and camera fit are intentionally unchanged.
    final xs = _meshAxis(halfWidth);
    final zs = _meshAxis(halfDepth);
    for (var iz = 0; iz < zs.length - 1; iz++) {
      for (var ix = 0; ix < xs.length - 1; ix++) {
        final corners = [
          surfacePoint(xs[ix], zs[iz]),
          surfacePoint(xs[ix], zs[iz + 1]),
          surfacePoint(xs[ix + 1], zs[iz + 1]),
          surfacePoint(xs[ix + 1], zs[iz]),
        ];
        for (final triangle in const [
          [0, 1, 2],
          [0, 2, 3],
        ]) {
          final mid =
              (corners[triangle[0]] +
                  corners[triangle[1]] +
                  corners[triangle[2]]) /
              3;
          final color = colorAt(mid.x, mid.z);
          for (final index in triangle) {
            final p = corners[index];
            positions.addAll([p.x, p.y, p.z]);
            colors.addAll([color.r, color.g, color.b, 1]);
          }
        }
      }
    }
    return fs.MeshGeometry.fromArrays(
      positions: Float32List.fromList(positions),
      colors: Float32List.fromList(colors),
      retainCpuData: false,
    );
  }

  List<double> _meshAxis(double cityExtent) {
    const apron = 10.0;
    const outerStep = 1.25;
    const innerStep = .34;
    return [
      for (var x = -cityExtent - apron; x < -cityExtent; x += outerStep) x,
      for (var x = -cityExtent; x < cityExtent; x += innerStep) x,
      for (var x = cityExtent; x <= cityExtent + apron; x += outerStep) x,
    ];
  }
}

/// Camera and polygon projection have no GPU dependency and can be tested with
/// the same geometry used by SceneView. Hex corners, not rectangular bounds,
/// decide whether a pointer belongs to a plot.
class CityMapProjection {
  CityMapProjection({
    required this.terrain,
    this.azimuth = .18,
    this.elevation = .92,
    this.zoom = 1,
    this.panX = 0,
    this.panZ = 0,
  });

  final CityTerrain terrain;
  final double azimuth, elevation, zoom, panX, panZ;

  fs.OrthographicCamera get camera => fs.OrthographicCamera(
    position: vm.Vector3(
      panX + math.sin(azimuth) * math.cos(elevation) * 24,
      math.sin(elevation) * 24,
      panZ + math.cos(azimuth) * math.cos(elevation) * 24,
    ),
    target: vm.Vector3(panX, .2, panZ),
    projection: fs.OrthographicProjection(
      size: fs.OrthographicSize.contain(
        (terrain.columns * math.sqrt(3) + 2.3) / zoom,
        (terrain.rows * 1.5 + 2.0) / zoom,
      ),
      near: .1,
      far: 60,
    ),
  );

  Offset center(int index, Size size) =>
      camera.worldToScreen(terrain.center(index), size)!;

  List<Offset> corners(int index, Size size) => [
    for (final point in terrain.boundary(index))
      camera.worldToScreen(point, size)!,
  ];

  Path polygon(int index, Size size) =>
      Path()..addPolygon(corners(index, size), true);

  int? pickPlot(Offset position, Size size) {
    if (!(Offset.zero & size).contains(position)) return null;
    final candidates = terrain.plots
        .where((plot) => polygon(plot.index, size).contains(position))
        .toList();
    if (candidates.isEmpty) return null;
    // Slopes can overlap near their silhouette. Pick the closest plot center.
    candidates.sort(
      (a, b) => (center(a.index, size) - position).distanceSquared.compareTo(
        (center(b.index, size) - position).distanceSquared,
      ),
    );
    return candidates.first.index;
  }
}
