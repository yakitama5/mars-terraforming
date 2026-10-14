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

  /// Edges shared by two plots are interior roads, not the edge of the city.
  /// Quantized XZ keys tolerate Float32 coordinates without changing geometry.
  List<(vm.Vector3, vm.Vector3)> boundaryEdges(Set<int> indices) {
    final edges = <String, (vm.Vector3, vm.Vector3)>{};
    String vertexKey(vm.Vector3 point) =>
        '${(point.x * 10000).round()}:${(point.z * 10000).round()}';
    for (final plot in plots.where((plot) => indices.contains(plot.index))) {
      final points = boundary(plot.index);
      for (var i = 0; i < points.length; i++) {
        final a = points[i];
        final b = points[(i + 1) % points.length];
        final ak = vertexKey(a);
        final bk = vertexKey(b);
        final key = ak.compareTo(bk) < 0 ? '$ak/$bk' : '$bk/$ak';
        if (edges.containsKey(key)) {
          edges.remove(key);
        } else {
          edges[key] = (a, b);
        }
      }
    }
    return edges.values.toList();
  }

  vm.Vector3 surfacePoint(double x, double z, {double offset = 0}) =>
      vm.Vector3(x, height(x, z) + offset, z);

  double _terrainHeight(String terrain) => switch (terrain) {
    'ridge' => earth ? .95 : 1.00,
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
        (.16 * math.sin(x * .84 + z * .22) +
            .10 * math.cos(z * .9 - x * .30) +
            .04 * math.sin(x * 2.4 + z * 1.2));
    elevation += craterRim * (1 - footprint);
    if (hasCoast) {
      final sea = _smooth(0, .85, -coastDistance(x, z));
      elevation = elevation * (1 - sea) - .32 * sea;
    }
    return elevation;
  }

  /// Curved shoreline outside the coastal building pads. The terrain remains
  /// deterministic and authored; this does not change buildable game plots.
  double coastDistance(double x, double z) =>
      x -
      (-columns * math.sqrt(3) / 2 -
          .40 +
          .35 * math.sin(z * .58 + .40) +
          .14 * math.sin(z * 1.1 - 1.2));

  static double _smooth(double start, double end, double value) {
    final t = ((value - start) / (end - start)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  Color colorAt(double x, double z) {
    // Blend terrain fields instead of coloring the nearest plot's whole
    // Voronoi region. This keeps ice, rock and soil in natural broad patches,
    // including beyond the development boundary.
    var weights = 0.0;
    var red = 0.0, green = 0.0, blue = 0.0;
    for (var i = 0; i < centers.length; i++) {
      final point = centers[i];
      final distance =
          (x - point.x) * (x - point.x) + (z - point.z) * (z - point.z);
      final weight = math.exp(-distance * 1.1);
      final color = switch (plots[i].terrain) {
        'coast' => const Color(0xffb1a36a),
        'ice' => const Color(0xffb6cdd2),
        'mineral' => earth ? const Color(0xff989270) : const Color(0xff75422f),
        'ridge' => earth ? const Color(0xff84926e) : const Color(0xff9b553b),
        'crater' => const Color(0xff714131),
        _ => earth ? const Color(0xff91a55b) : const Color(0xffb05a32),
      };
      weights += weight;
      red += color.r * weight;
      green += color.g * weight;
      blue += color.b * weight;
    }
    final wilderness = earth
        ? const Color(0xff829c52)
        : const Color(0xffac5834);
    var base = weights > 1e-10
        ? Color.lerp(
            wilderness,
            Color.from(
              alpha: 1,
              red: red / weights,
              green: green / weights,
              blue: blue / weights,
            ),
            _smooth(.03, .50, weights),
          )!
        : wilderness;
    final patch =
        .5 +
        .25 * math.sin(x * .66 + z * .32) +
        .25 * math.cos(z * .93 - x * .24);
    base = Color.lerp(
      base,
      earth ? const Color(0xff34582e) : const Color(0xff713925),
      .12 * patch,
    )!;
    if (hasCoast) {
      final distance = coastDistance(x, z);
      final beach = 1 - _smooth(.15, 1.0, distance);
      base = Color.lerp(base, const Color(0xffb8ae76), beach * .65)!;
      final water = _smooth(-.04, .45, -distance);
      final depth = _smooth(.30, 2.0, -distance);
      final sea = Color.lerp(
        const Color(0xff348782),
        const Color(0xff173f70),
        depth,
      )!;
      base = Color.lerp(base, sea, water)!;
      // A thin, soft surf line follows the shore without a texture or network.
      final surf = math.exp(-math.pow((distance + .12) / .075, 2));
      base = Color.lerp(base, const Color(0xffb3d5ba), surf * .48)!;
    }
    return base;
  }

  // FlutterScene's PBR shader multiplies vertex RGB directly into linear
  // albedo. Flutter Color is sRGB; feeding it raw washes out grass and red soil.
  static double linearChannel(double srgb) => srgb <= .04045
      ? srgb / 12.92
      : math.pow((srgb + .055) / 1.055, 2.4).toDouble();

  /// Smooth normals follow the same continuous height field used for placement.
  /// Sharing vertices also avoids the former triangle-by-triangle color bands.
  vm.Vector3 normalAt(double x, double z) {
    const step = .035;
    return vm.Vector3(
      height(x - step, z) - height(x + step, z),
      step * 2,
      height(x, z - step) - height(x, z + step),
    ).normalized();
  }

  fs.MeshGeometry mesh() {
    final positions = <double>[];
    final normals = <double>[];
    final colors = <double>[];
    final uvs = <double>[];
    final indices = <int>[];
    final xs = _meshAxis(halfWidth);
    final zs = _meshAxis(halfDepth);
    for (final z in zs) {
      for (final x in xs) {
        final normal = normalAt(x, z);
        final color = colorAt(x, z);
        positions.addAll([x, height(x, z), z]);
        normals.addAll([normal.x, normal.y, normal.z]);
        // Four world units per repeat: grain remains the same size while
        // orbiting or changing the city's dimensions, instead of stretching.
        uvs.addAll([x / 4, z / 4]);
        colors.addAll([
          linearChannel(color.r),
          linearChannel(color.g),
          linearChannel(color.b),
          1,
        ]);
      }
    }
    for (var iz = 0; iz < zs.length - 1; iz++) {
      for (var ix = 0; ix < xs.length - 1; ix++) {
        final a = iz * xs.length + ix;
        final b = a + xs.length;
        indices.addAll([a, b, b + 1, a, b + 1, a + 1]);
      }
    }
    return fs.MeshGeometry.fromArrays(
      positions: Float32List.fromList(positions),
      normals: Float32List.fromList(normals),
      texCoords: Float32List.fromList(uvs),
      colors: Float32List.fromList(colors),
      indices: indices,
      retainCpuData: false,
    );
  }

  List<double> _meshAxis(double cityExtent) {
    const apron = 10.0;
    const outerStep = 1.25;
    const innerStep = .24;
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
    this.azimuth = neighborhoodAzimuth,
    this.elevation = neighborhoodElevation,
    this.zoom = neighborhoodZoom,
    this.panX = 0,
    this.panZ = 0,
  });

  // A close, oblique neighborhood view makes roofs, walls and streets readable.
  // Overview is an explicit camera mode, rather than the starting composition.
  static const neighborhoodAzimuth = .24;
  static const neighborhoodElevation = .60;
  static const neighborhoodZoom = 2.3;
  static const overviewElevation = .88;
  static const overviewZoom = .9;
  static const minZoom = .8;
  static const maxZoom = 3.2;

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
