import 'dart:math' as math;
import 'dart:typed_data';

import 'title_planet_geometry.dart';

/// 土星の環をXZ平面へ置くCPUメッシュ。初期値はNASA VTADのC〜F環の範囲。
///
/// 半径2行、周方向[segments]区間で、表の面は+Yを向く。UVのuは内縁0から
/// 外縁1へ、vは周方向0から1へ進むため、横軸が半径の環画像をそのまま使える。
/// 裏面の描画は材質側のcullingで選び、ここでは面を二重にしない。
TitlePlanetMeshData gasGiantRingMeshData({
  double innerRadius = 1.232301,
  double outerRadius = 2.330901,
  int segments = 256,
}) {
  if (!innerRadius.isFinite || innerRadius <= 0) {
    throw ArgumentError.value(innerRadius, 'innerRadius', '正の有限値が必要です');
  }
  if (!outerRadius.isFinite || outerRadius <= innerRadius) {
    throw ArgumentError.value(outerRadius, 'outerRadius', '内縁より大きい有限値が必要です');
  }
  if (segments < 3) {
    throw ArgumentError.value(segments, 'segments', '3以上が必要です');
  }
  // doubleで有効でもFloat32で無限大・0・同じ半径になる入力は造形できない。
  final radii = Float32List.fromList([innerRadius, outerRadius]);
  if (!radii[0].isFinite ||
      !radii[1].isFinite ||
      radii[0] <= 0 ||
      radii[1] <= radii[0]) {
    throw ArgumentError('環の半径はFloat32で区別できる正の有限値にしてください');
  }

  final stride = segments + 1;
  final vertexCount = stride * 2;
  final positions = Float32List(vertexCount * 3);
  final normals = Float32List(vertexCount * 3);
  final colors = Float32List(vertexCount * 4);
  final texCoords = Float32List(vertexCount * 2);
  final tangents = Float32List(vertexCount * 4);
  final indices = List<int>.filled(segments * 6, 0);
  for (var row = 0; row < 2; row++) {
    final radius = row == 0 ? innerRadius : outerRadius;
    for (var column = 0; column <= segments; column++) {
      final v = column / segments;
      // 最終列は最初と完全に同じ位置にし、UV.vだけを1へ分ける。
      final angle = column == segments ? 0.0 : v * math.pi * 2;
      final cosine = math.cos(angle), sine = math.sin(angle);
      final index = row * stride + column;
      positions[index * 3] = cosine * radius;
      positions[index * 3 + 2] = sine * radius;
      normals[index * 3 + 1] = 1;
      colors.setRange(index * 4, index * 4 + 4, const [1.0, 1.0, 1.0, 1.0]);
      texCoords[index * 2] = row.toDouble();
      texCoords[index * 2 + 1] = v;
      tangents[index * 4] = cosine;
      tangents[index * 4 + 2] = sine;
      // normal×tangentは-vを向くため、bitangentの符号を反転する。
      tangents[index * 4 + 3] = -1;
    }
  }
  for (var column = 0; column < segments; column++) {
    final inner = column, outer = stride + column;
    indices.setRange(column * 6, column * 6 + 6, [
      inner,
      inner + 1,
      outer,
      inner + 1,
      outer + 1,
      outer,
    ]);
  }
  return TitlePlanetMeshData(
    positions: positions,
    normals: normals,
    colors: colors,
    texCoords: texCoords,
    tangents: tangents,
    indices: indices,
  );
}
