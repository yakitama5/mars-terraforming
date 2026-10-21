import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

/// Fixed, local geometry: stylized geography, not scientific terrain data.
/// Each face owns its vertices to retain the small low-poly lighting facets.
fs.MeshGeometry makePlanetGeometry({
  required bool earth,
  bool moon = false,
  double radius = 3.1,
}) {
  final positions = <double>[];
  final colors = <double>[];
  const rows = 36;
  const columns = 72;
  for (var row = 0; row < rows; row++) {
    final south = -90.0 + row * 180 / rows;
    final north = south + 180 / rows;
    for (var column = 0; column < columns; column++) {
      final west = -180.0 + column * 360 / columns;
      final east = west + 360 / columns;
      final corners = [
        (south, west),
        (north, west),
        (north, east),
        (south, east),
      ];
      for (final triangle in const [
        [0, 1, 2],
        [0, 2, 3],
      ]) {
        final lat = triangle.fold(0.0, (v, i) => v + corners[i].$1) / 3;
        final lon = triangle.fold(0.0, (v, i) => v + corners[i].$2) / 3;
        final seed = ((row * 31 + column * 17 + triangle[1]) % 11) / 10;
        final color = moon
            ? _moonColor(lat, lon, seed)
            : earth
            ? _earthColor(lat, lon, seed)
            : _marsColor(lat, lon, seed);
        for (final index in triangle) {
          final point = planetPoint(
            corners[index].$1,
            corners[index].$2,
            radius,
          );
          positions.addAll([point.x, point.y, point.z]);
          colors.addAll([...color, 1]);
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

vm.Vector3 planetPoint(double latitude, double longitude, double radius) {
  final lat = latitude * math.pi / 180;
  final lon = longitude * math.pi / 180;
  return vm.Vector3(
    math.cos(lat) * math.sin(lon),
    math.sin(lat),
    -math.cos(lat) * math.cos(lon),
  )..scale(radius);
}

List<double> _earthColor(double lat, double lon, double seed) {
  if (lat < -74 || lat > 79 || (lat > 60 && lon > -58 && lon < -27)) {
    return [0.72 + seed * 0.07, 0.86 + seed * 0.05, 0.85 + seed * 0.06];
  }
  final land = _continents.any((polygon) => _contains(polygon, lat, lon));
  if (!land) {
    return [0.022 + seed * 0.012, 0.18 + seed * 0.025, 0.34 + seed * 0.035];
  }
  if ((lat > 10 && lat < 32 && lon > -18 && lon < 60) ||
      (lat < -17 && lon > 110 && lon < 155)) {
    return [0.57 + seed * 0.07, 0.49 + seed * 0.06, 0.29 + seed * 0.04];
  }
  return [0.14 + seed * 0.045, 0.36 + seed * 0.055, 0.24 + seed * 0.045];
}

List<double> _marsColor(double lat, double lon, double seed) {
  if (lat > 78 || lat < -80) return [0.72, 0.68, 0.60];
  final terrain =
      math.sin(lon * 0.035 + lat * 0.025) +
      math.cos(lat * 0.11 - lon * 0.015) * 0.45;
  if (terrain > 0.5) {
    return [0.53 + seed * 0.045, 0.22 + seed * 0.026, 0.115 + seed * 0.015];
  }
  if (terrain < -0.5) {
    return [0.38 + seed * 0.04, 0.14 + seed * 0.022, 0.075 + seed * 0.012];
  }
  return [0.64 + seed * 0.045, 0.30 + seed * 0.03, 0.16 + seed * 0.02];
}

List<double> _moonColor(double lat, double lon, double seed) {
  // Broad basalt plains and pale highlands, authored for recognition at game
  // scale. This is neither an observed albedo map nor surveyed lunar geology.
  final maria =
      math.sin(lon * .038 - lat * .023) +
      .65 * math.cos(lat * .071 + lon * .014);
  final light = (maria > .30 ? .34 : .58) + seed * .055;
  return [light, light * .99, light * 1.015];
}

bool _contains(List<(double, double)> polygon, double lat, double lon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i];
    final b = polygon[j];
    if ((a.$1 > lat) != (b.$1 > lat) &&
        lon < (b.$2 - a.$2) * (lat - a.$1) / (b.$1 - a.$1) + a.$2) {
      inside = !inside;
    }
  }
  return inside;
}

// Latitude/longitude contours, intentionally simplified for the globe view.
const _continents = <List<(double, double)>>[
  // North America.
  [
    (70, -166),
    (72, -135),
    (61, -112),
    (72, -85),
    (57, -56),
    (49, -53),
    (45, -66),
    (25, -81),
    (18, -88),
    (16, -96),
    (28, -113),
    (49, -126),
    (59, -142),
    (61, -165),
  ],
  // South America.
  [
    (12, -80),
    (10, -64),
    (3, -50),
    (-8, -35),
    (-22, -42),
    (-35, -53),
    (-55, -68),
    (-47, -75),
    (-20, -71),
    (0, -80),
  ],
  // Africa.
  [
    (36, -6),
    (37, 11),
    (32, 32),
    (13, 43),
    (11, 51),
    (-12, 40),
    (-35, 20),
    (-29, 12),
    (-5, 9),
    (5, -2),
    (6, -16),
    (20, -18),
  ],
  // Europe and Asia.
  [
    (36, -10),
    (44, -10),
    (50, -5),
    (58, 6),
    (71, 24),
    (68, 44),
    (73, 75),
    (72, 120),
    (64, 179),
    (50, 160),
    (44, 144),
    (35, 139),
    (21, 120),
    (8, 107),
    (1, 103),
    (22, 94),
    (8, 78),
    (25, 66),
    (12, 44),
    (30, 34),
    (41, 28),
    (36, 22),
    (44, 15),
    (36, 4),
  ],
  // Australia, Madagascar, Japan, New Zealand, and the British Isles.
  [(-12, 113), (-11, 134), (-17, 146), (-38, 151), (-40, 135), (-33, 115)],
  [(-12, 49), (-25, 47), (-24, 43), (-15, 44)],
  [(44, 141), (39, 143), (31, 131), (34, 130)],
  [(-34, 173), (-42, 177), (-47, 168), (-42, 167)],
  [(59, -6), (51, 2), (50, -6), (55, -10)],
  [(6, 96), (-6, 106), (-8, 119), (-3, 119), (6, 114)],
];
