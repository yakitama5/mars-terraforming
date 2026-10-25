import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'planet_geometry.dart';

/// NASA MGS/MOLAの標高。ヘッダーMOLA/幅/高さに続く符号付き16bit LE、単位m。
class MeasuredPlanetHeightField {
  MeasuredPlanetHeightField(ByteData data) : _data = data {
    if (data.lengthInBytes < 8 || data.getUint32(0) != 0x4d4f4c41) {
      throw const FormatException('MOLA height header is invalid');
    }
    width = data.getUint16(4, Endian.little);
    height = data.getUint16(6, Endian.little);
    if (width < 2 ||
        height < 2 ||
        data.lengthInBytes != 8 + width * height * 2) {
      throw const FormatException('MOLA height dimensions are invalid');
    }
  }

  final ByteData _data;
  late final int width, height;

  double sample(double u, double v) {
    final x = ((u % 1) * width - .5), y = (v.clamp(0.0, 1.0) * height - .5);
    final ix = x.floor(),
        iy = y.floor(),
        tx = x - x.floor(),
        ty = y - y.floor();
    double pixel(int a, int b) => _data
        .getInt16(
          8 + ((b.clamp(0, height - 1) * width + a % width) * 2),
          Endian.little,
        )
        .toDouble();
    final a = pixel(ix, iy), b = pixel(ix + 1, iy);
    final c = pixel(ix, iy + 1), d = pixel(ix + 1, iy + 1);
    return (a + (b - a) * tx) * (1 - ty) + (c + (d - c) * tx) * ty;
  }

  double at(double latitude, double longitude) => sample(
    latitude.abs() >= 90 ? .5 : (longitude + 180) / 360,
    (90 - latitude) / 180,
  );
}

/// 写真のUVと実測標高が一致する球。色の模様や架空の地形は生成しない。
TitlePlanetMeshData measuredPlanetMeshData({
  MeasuredPlanetHeightField? heightField,
  double radius = 3.1,
  double exaggeration = 1.5,
  int rows = 192,
  int columns = 320,
}) {
  final positions = <double>[], normals = <double>[], colors = <double>[];
  final texCoords = <double>[], tangents = <double>[];
  final indices = <int>[];
  for (var row = 0; row <= rows; row++) {
    final latitude = -90 + row / rows * 180;
    for (var column = 0; column <= columns; column++) {
      final longitude = -180 + column / columns * 360;
      final meters = heightField?.at(latitude, longitude) ?? 0;
      final point = planetPoint(
        latitude,
        longitude,
        radius * (1 + meters / 3396000 * exaggeration),
      );
      final normal = point.normalized();
      final lon = longitude * math.pi / 180;
      positions.addAll([point.x, point.y, point.z]);
      normals.addAll([normal.x, normal.y, normal.z]);
      colors.addAll([1, 1, 1, 1]);
      texCoords.addAll([column / columns, 1 - row / rows]);
      tangents.addAll([math.cos(lon), 0, math.sin(lon), 1]);
      if (row < rows && column < columns) {
        final a = row * (columns + 1) + column, b = a + columns + 1;
        if (row > 0) indices.addAll([a, b, a + 1]);
        if (row < rows - 1) indices.addAll([a + 1, b, b + 1]);
      }
    }
  }
  return TitlePlanetMeshData(
    positions: Float32List.fromList(positions),
    normals: Float32List.fromList(normals),
    colors: Float32List.fromList(colors),
    texCoords: Float32List.fromList(texCoords),
    tangents: Float32List.fromList(tangents),
    indices: indices,
  );
}

/// タイトルのために造形した火星。標高・配色は実測地図ではない。
/// 周期的な関数と固定クレーターだけを使い、再起動でも地形を保つ。
class TitleMarsSurface {
  static const radius = 3.1;
  // タイトルの俯瞰で読むための意図的な誇張。複数地形が重なっても、
  // 高さは半径の+6%、深さは-4.5%へ収めて外周を安定させる。
  static const maxElevationRatio = .06;
  static const minElevationRatio = -.045;

  static double _longitudeDistance(double a, double b) =>
      (a - b + 180) % 360 - 180;

  static double _distance(
    double lat,
    double lon,
    double centerLat,
    double centerLon,
  ) {
    final x =
        _longitudeDistance(lon, centerLon) *
        math.cos((lat + centerLat) * math.pi / 360);
    return math.sqrt((lat - centerLat) * (lat - centerLat) + x * x);
  }

  static ({double elevation, double darkness, double rim}) _fissures(
    double lat,
    double lon,
  ) {
    var elevation = 0.0, darkness = 0.0, rim = 0.0;
    // 同じ緯度を一周する帯にせず、長さ・傾きの違う三つの裂け目を置く。
    for (final path in const [
      (47.0, 190.0, .17, 21.0, .012, 0.0),
      (54.0, 174.0, -.28, 13.0, .0065, 1.0),
      (40.0, 204.0, .35, 11.0, .0055, 2.0),
    ]) {
      final x = _longitudeDistance(lon, path.$2);
      final taper = math.exp(-math.pow(x / path.$4, 4));
      if (taper < .00001) continue;
      final center =
          path.$1 +
          x * path.$3 +
          (math.sin(x * .14 + path.$6) - math.sin(path.$6)) * 1.7;
      final distance = (lat - center).abs();
      final width = .75 + .45 * taper * (.7 + .3 * math.sin(x * .2 + path.$6));
      final floor = math.exp(-math.pow(distance / width, 2)) * taper;
      final brokenRim =
          .45 + .55 * math.pow(math.sin(x * .27 + path.$6), 2).toDouble();
      final shoulder =
          math.exp(-math.pow((distance - width * 1.6) / .8, 2)) *
          taper *
          brokenRim;
      elevation += -path.$5 * floor + path.$5 * .18 * shoulder;
      darkness = math.max(darkness, floor);
      rim = math.max(rim, shoulder);
    }
    return (elevation: elevation, darkness: darkness, rim: rim);
  }

  static double elevation(double lat, double lon) {
    final a = lat * math.pi / 180, b = lon * math.pi / 180;
    // 大きな高地と、流れる地層の細かな起伏。格子単位で乱数着色しない。
    var height =
        .0015 * math.sin(b * 5 + math.sin(a * 4)) * math.cos(a * 3) +
        .0007 * math.sin(b * 17 - a * 11) * math.sin(a * 9 + b * 6);
    // 少数の特徴を俯瞰で読ませ、地平線を切る巨大な溝は作らない。
    height += _fissures(lat, lon).elevation;
    for (final volcano in const [
      (57.0, 143.0, 10.0, .038),
      (39.0, 151.0, 6.3, .018),
      (32.0, 158.0, 5.5, .015),
      (38.0, 224.0, 5.2, .019),
    ]) {
      final distance = _distance(lat, lon, volcano.$1, volcano.$2);
      height += volcano.$4 * math.exp(-math.pow(distance / volcano.$3, 2));
      height -=
          volcano.$4 *
          .35 *
          math.exp(-math.pow(distance / (volcano.$3 * .23), 2));
    }
    // 大盆地と、抉られた床・盛り上がった縁を持つクレーター。
    final basin = _distance(lat, lon, 39, 219);
    height -= .009 * math.exp(-math.pow(basin / 15, 2));
    for (final crater in craters) {
      final d = _distance(lat, lon, crater.$1, crater.$2) / crater.$3;
      if (d > 1.65) continue;
      final relief = .35 + .65 * (crater.$3 / 5).clamp(0.0, 1.0);
      height += .0058 * relief * math.exp(-math.pow((d - 1) / .27, 2));
      height -= .0055 * relief * math.exp(-math.pow(d / .75, 2));
      if (crater.$3 > 4) height += .0013 * math.exp(-math.pow(d / .25, 2));
    }
    return height.clamp(minElevationRatio, maxElevationRatio) *
        ((90 - lat.abs()) / 4).clamp(0.0, 1.0);
  }

  static vm.Vector3 point(double lat, double lon, {double lift = 0}) =>
      planetPoint(lat, lon, radius * (1 + elevation(lat, lon)) + lift);

  static Color color(double lat, double lon, {double greening = 0}) {
    final a = lat * math.pi / 180, b = lon * math.pi / 180;
    final broad =
        .5 + .25 * math.sin(b * 3 + a * 4) + .18 * math.cos(a * 7 - b * 5);
    final strata = .5 + .5 * math.sin(a * 27 + b * 7 + 2 * math.sin(b * 4));
    final height = elevation(lat, lon);
    var color = Color.lerp(
      const Color(0xff9b6147),
      const Color(0xffc18a66),
      (broad * .93 + strata * .07).clamp(0.0, 1.0),
    )!;
    // 閾値で濃い色へ切り替えると円の底が四角い画素に見えるため連続化。
    final depression = ((-height - .001) / .013).clamp(0.0, 1.0);
    final uplift = ((height - .003) / .03).clamp(0.0, 1.0);
    color = Color.lerp(color, const Color(0xff77503c), depression * .24)!;
    color = Color.lerp(color, const Color(0xffd5a47b), uplift * .18)!;
    final fissure = _fissures(lat, lon);
    color = Color.lerp(color, const Color(0xff71513e), fissure.darkness * .32)!;
    color = Color.lerp(color, const Color(0xffc99c74), fissure.rim * .1)!;
    final iceBoundary = 75 + 2.5 * math.sin(b * 5) + 1.5 * math.cos(b * 9);
    final polar = ((lat.abs() - iceBoundary) / 5).clamp(0.0, 1.0);
    color = Color.lerp(color, const Color(0xffd4ddd8), polar)!;
    // 入植域の限定的な緑。全球居住・海洋成立を意味する判定ではない。
    final green = greening.isFinite ? greening.clamp(0.0, 1.0) : 0.0;
    final pockets =
        math.exp(-math.pow((lat - 52) / 14, 2)) *
        math.exp(-math.pow(_longitudeDistance(lon, 190) / 39, 2));
    return Color.lerp(color, const Color(0xff698575), green * pockets * .58)!;
  }

  static const craters = <(double, double, double)>[
    (64, 184, 5.5),
    (45, 216, 5.8),
    (-24, 164, 6.3),
    (-38, 184, 4.9),
    (67, 152, 3.4),
    (20, 230, 5.5),
    (8, 129, 3.7),
    (-19, 243, 7.1),
    (60, 216, 3.1),
    (-53, 140, 6.5),
    (-3, 196, 2.0),
    (40, 197, 2.1),
    (49, 132, 2.8),
    (70, 204, 3.3),
    (-25, 207, 2.3),
    (-9, 228, 1.7),
    (18, 176, 1.9),
    (-45, 252, 5.3),
    (7, 253, 3.7),
    (36, 119, 4.4),
    (-64, 203, 3.6),
    (14, 31, 7.5),
    (-34, 55, 6.1),
    (52, -65, 4.8),
    (-18, -25, 3.2),
    (25, 75, 6.5),
    (-48, -100, 5.2),
    (61, 42, 4.2),
    (-12, 95, 3.9),
    (8, -78, 5.1),
    (54, 233, 1.8),
    (62, 230, 2.2),
    (57, 200, 1.3),
    (38, 173, 1.9),
    (35, 189, 1.4),
    (43, 235, 2.4),
    (69, 169, 1.6),
    (59, 171, 1.2),
    (63, 164, 1.5),
    (42, 128, 2.5),
    (52, 123, 1.6),
    (36, 211, 1.4),
  ];
}

/// CPU配列はテスト可能なまま用意し、GPUへの転送はScene初期化後だけ行う。
class TitlePlanetMeshData {
  const TitlePlanetMeshData({
    required this.positions,
    required this.normals,
    required this.colors,
    required this.texCoords,
    required this.tangents,
    required this.indices,
  });

  final Float32List positions;
  final Float32List normals;
  final Float32List colors;
  final Float32List texCoords;
  final Float32List tangents;
  final List<int> indices;

  fs.MeshGeometry geometry() => fs.MeshGeometry.fromArrays(
    positions: positions,
    normals: normals,
    colors: colors,
    texCoords: texCoords,
    tangents: tangents,
    indices: indices,
    retainCpuData: false,
  );
}

double titleLinear(double value) => value <= .04045
    ? value / 12.92
    : math.pow((value + .055) / 1.055, 2.4).toDouble();

TitlePlanetMeshData titleMarsMeshData({
  double greening = 0,
  int rows = 160,
  int columns = 320,
}) {
  assert(rows >= 4 && columns >= 8);
  final points = <vm.Vector3>[];
  final positions = <double>[], normals = <double>[], colors = <double>[];
  final texCoords = <double>[], tangents = <double>[];
  final indices = <int>[];
  for (var row = 0; row <= rows; row++) {
    final t = row / rows;
    // 固定カメラから見える北半球へ密度を配り、クレーターの縁を丸く保つ。
    // 25〜75°は約.57°刻み。不可視の南半球を同じ密度にはしない。
    final lat = t < .35
        ? -90 + t / .35 * 115
        : t < .90
        ? 25 + (t - .35) / .55 * 50
        : 75 + (t - .90) / .10 * 15;
    for (var column = 0; column <= columns; column++) {
      final lon = -180 + column * 360 / columns;
      final point = TitleMarsSurface.point(lat, lon);
      points.add(point);
      positions.addAll([point.x, point.y, point.z]);
      texCoords.addAll([column / columns, 1 - row / rows]);
      final color = TitleMarsSurface.color(lat, lon, greening: greening);
      colors.addAll([
        titleLinear(color.r),
        titleLinear(color.g),
        titleLinear(color.b),
        1,
      ]);
    }
  }
  for (var row = 0; row <= rows; row++) {
    for (var column = 0; column <= columns; column++) {
      final index = row * (columns + 1) + column;
      vm.Vector3 normal;
      if (row == 0 || row == rows) {
        normal = points[index].normalized();
      } else {
        final previousColumn = column == 0 ? columns - 1 : column - 1;
        final nextColumn = column == columns ? 1 : column + 1;
        final latitudeDirection =
            points[index + columns + 1] - points[index - columns - 1];
        final longitudeDirection =
            points[row * (columns + 1) + nextColumn] -
            points[row * (columns + 1) + previousColumn];
        normal = latitudeDirection.cross(longitudeDirection)..normalize();
      }
      normals.addAll([normal.x, normal.y, normal.z]);
      final lon = (-180 + column * 360 / columns) * math.pi / 180;
      final east = vm.Vector3(math.cos(lon), 0, math.sin(lon));
      final tangent = (east - normal * east.dot(normal))..normalize();
      tangents.addAll([tangent.x, tangent.y, tangent.z, 1]);
      if (row < rows && column < columns) {
        final a = index, b = index + columns + 1;
        // 極の縮退三角形は作らず、極冠の斑点と無効法線を防ぐ。
        if (row > 0) indices.addAll([a, b, a + 1]);
        if (row < rows - 1) indices.addAll([a + 1, b, b + 1]);
      }
    }
  }
  return TitlePlanetMeshData(
    positions: Float32List.fromList(positions),
    normals: Float32List.fromList(normals),
    colors: Float32List.fromList(colors),
    texCoords: Float32List.fromList(texCoords),
    tangents: Float32List.fromList(tangents),
    indices: indices,
  );
}

/// 砂丘・風化した層を補う、オフラインの色/法線マップ。
/// 大きな凹凸は実際のgeometryに残し、細粒をテクスチャへ分担する。
class TitleMarsDetailPixels {
  const TitleMarsDetailPixels({
    required this.width,
    required this.height,
    required this.albedo,
    required this.normal,
  });

  final int width, height;
  final Uint8List albedo, normal;

  static double _hash(int x, int y) {
    var n = (x * 374761393 + y * 668265263 + 81302) & 0x7fffffff;
    n = ((n ^ (n >> 13)) * 127412) & 0x7fffffff;
    n ^= n >> 16;
    return (n & 65535) / 65535;
  }

  static double _noise(double x, double y, int periodX, int periodY) {
    final ix = x.floor(), iy = y.floor();
    final tx = x - ix, ty = y - iy;
    final sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty);
    double sample(int a, int b) => _hash(a % periodX, b % periodY);
    final a = sample(ix, iy), b = sample(ix + 1, iy);
    final c = sample(ix, iy + 1), d = sample(ix + 1, iy + 1);
    return (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy;
  }

  factory TitleMarsDetailPixels.generate({int width = 1024, int height = 512}) {
    final albedo = Uint8List(width * height * 4);
    final normal = Uint8List(width * height * 4);
    final heights = Float32List(width * height);
    for (var y = 0; y < height; y++) {
      final v = y / height;
      final polar = math.sin(v * math.pi);
      for (var x = 0; x < width; x++) {
        final u = x / width;
        final broad = _noise(u * 48, v * 24, 48, 24);
        final grain = _noise(u * 192, v * 96, 192, 96);
        final fine = _hash(x, y);
        heights[y * width + x] =
            (grain * .30 + fine * .045 + broad * .12) * polar;
        final value = (1 - (.028 * broad + .024 * grain + .012 * fine) * polar)
            .clamp(.92, 1.0);
        final index = (y * width + x) * 4;
        albedo[index] = (255 * value).round();
        albedo[index + 1] = (255 * value).round();
        albedo[index + 2] = (255 * value).round();
        albedo[index + 3] = 255;
      }
    }
    double sample(int x, int y) =>
        heights[y.clamp(0, height - 1) * width + x % width];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final n = vm.Vector3(
          (sample(x - 1, y) - sample(x + 1, y)) * 2.4,
          (sample(x, y - 1) - sample(x, y + 1)) * 2.4,
          1,
        )..normalize();
        final index = (y * width + x) * 4;
        normal[index] = (128 + n.x * 127).round();
        normal[index + 1] = (128 + n.y * 127).round();
        normal[index + 2] = (128 + n.z * 127).round();
        normal[index + 3] = 255;
      }
    }
    return TitleMarsDetailPixels(
      width: width,
      height: height,
      albedo: albedo,
      normal: normal,
    );
  }
}

/// 視点固定の球の外周だけを淡く照らす。球全体を透明殻で覆わない。
fs.MeshGeometry titleLimbGeometry({
  required double radius,
  required double width,
  required Color color,
  double opacity = .28,
}) {
  final positions = <double>[], normals = <double>[], colors = <double>[];
  final indices = <int>[];
  const rings = 10, segments = 160;
  for (var ring = 0; ring <= rings; ring++) {
    final t = ring / rings;
    final r = radius + width * t;
    final alpha = opacity * math.pow(1 - t, 2).toDouble();
    for (var i = 0; i <= segments; i++) {
      final a = i / segments * math.pi * 2;
      positions.addAll([math.cos(a) * r, math.sin(a) * r, 0]);
      normals.addAll([0, 0, 1]);
      colors.addAll([
        titleLinear(color.r),
        titleLinear(color.g),
        titleLinear(color.b),
        alpha,
      ]);
      if (ring < rings && i < segments) {
        final v = ring * (segments + 1) + i;
        indices.addAll([
          v,
          v + segments + 1,
          v + 1,
          v + 1,
          v + segments + 1,
          v + segments + 2,
        ]);
      }
    }
  }
  return fs.MeshGeometry.fromArrays(
    positions: Float32List.fromList(positions),
    normals: Float32List.fromList(normals),
    colors: Float32List.fromList(colors),
    indices: indices,
    retainCpuData: false,
  );
}
