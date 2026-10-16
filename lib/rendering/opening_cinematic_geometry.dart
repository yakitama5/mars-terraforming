import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

/// OP用の静的な小物をまとめる。生成はGPU初期化後の一度だけ。
class OpeningMeshBatch {
  final _positions = <double>[];
  final _normals = <double>[];
  final _colors = <double>[];

  static double _linear(double value) => value <= .04045
      ? value / 12.92
      : math.pow((value + .055) / 1.055, 2.4).toDouble();

  void triangle(vm.Vector3 a, vm.Vector3 b, vm.Vector3 c, Color color) {
    final normal = (b - a).cross(c - a)..normalize();
    final rgb = [_linear(color.r), _linear(color.g), _linear(color.b), 1.0];
    for (final point in [a, b, c]) {
      _positions.addAll([point.x, point.y, point.z]);
      _normals.addAll([normal.x, normal.y, normal.z]);
      _colors.addAll(rgb);
    }
  }

  void box(
    vm.Vector3 center,
    vm.Vector3 size,
    Color color, {
    vm.Quaternion? rotation,
  }) {
    final corners = <vm.Vector3>[];
    // Quaternion.rotated は Node の行列と逆向きに回転する。
    // 行列へ統一し、まとめた梁の両端が設計上の接続点に一致するようにする。
    final transform = rotation?.asRotationMatrix();
    for (final corner in const [
      (-1.0, -1.0, -1.0),
      (1.0, -1.0, -1.0),
      (1.0, 1.0, -1.0),
      (-1.0, 1.0, -1.0),
      (-1.0, -1.0, 1.0),
      (1.0, -1.0, 1.0),
      (1.0, 1.0, 1.0),
      (-1.0, 1.0, 1.0),
    ]) {
      final local = vm.Vector3(
        corner.$1 * size.x / 2,
        corner.$2 * size.y / 2,
        corner.$3 * size.z / 2,
      );
      corners.add((transform?.transform(local) ?? local) + center);
    }
    for (final face in const [
      [0, 3, 2, 1],
      [4, 5, 6, 7],
      [0, 4, 7, 3],
      [1, 2, 6, 5],
      [0, 1, 5, 4],
      [3, 7, 6, 2],
    ]) {
      triangle(corners[face[0]], corners[face[1]], corners[face[2]], color);
      triangle(corners[face[0]], corners[face[2]], corners[face[3]], color);
    }
  }

  void beam(vm.Vector3 from, vm.Vector3 to, double width, Color color) {
    final direction = to - from;
    box(
      (from + to) * .5,
      vm.Vector3(width, direction.length, width),
      color,
      rotation: vm.Quaternion.fromTwoVectors(
        vm.Vector3(0, 1, 0),
        direction.normalized(),
      ),
    );
  }

  fs.Node node(String name, {fs.Material? material}) => fs.Node(
    name: name,
    mesh: fs.Mesh(
      fs.MeshGeometry.fromArrays(
        positions: Float32List.fromList(_positions),
        normals: Float32List.fromList(_normals),
        colors: Float32List.fromList(_colors),
        retainCpuData: false,
      ),
      material ??
          (fs.PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4.all(1)
            ..metallicFactor = 0
            ..roughnessFactor = .88),
    ),
  );
}

/// 写真や平面背景ではなく、カメラ移動で視差の出る地表と山稜。
fs.Node openingTerrain({required int world}) {
  final positions = <double>[], normals = <double>[], colors = <double>[];
  final indices = <int>[];
  double height(double x, double z) {
    final foothill = ((-z - 9) / 22).clamp(0.0, 1.0);
    final ridge =
        math.pow(foothill, 2).toDouble() *
        (3.4 + 2.4 * math.sin(x * .21 + 1) + 1.5 * math.sin(x * .59));
    var value = world == 0 ? -.08 : -.08 + ridge;
    if (world == 1) {
      final distance = math.sqrt((x + 10) * (x + 10) + (z + 8) * (z + 8));
      value +=
          .7 * math.exp(-math.pow((distance - 4.1) / .85, 2)) -
          .6 * math.exp(-math.pow(distance / 3.4, 4));
    }
    if (world != 0) value += .035 * math.sin(x * .8) * math.sin(z * .7);
    return value;
  }

  // 被写体の周囲だけ細かくし、遠景は少ない頂点でカメラの描画範囲外まで延ばす。
  // 四角い地面の端が地平線として画面に出ることを防ぐ。
  final xs = [
    -500.0,
    -220.0,
    -120.0,
    -72.0,
    for (var i = -28; i <= 28; i++) i * 1.5,
    72.0,
    120.0,
    220.0,
    500.0,
  ];
  final zs = [
    -500.0,
    -220.0,
    -120.0,
    -72.0,
    for (var i = -35; i <= 20; i++) i * 1.5,
    55.0,
    100.0,
    220.0,
    500.0,
  ];
  for (final z in zs) {
    for (final x in xs) {
      final normal = vm.Vector3(
        height(x - .12, z) - height(x + .12, z),
        .24,
        height(x, z - .12) - height(x, z + .12),
      )..normalize();
      // 隣り合う三角形で頂点色を共有し、市松模様になるセル単位の着色を避ける。
      final variation =
          .5 +
          .18 * math.sin(x * .13 + z * .07) +
          .12 * math.cos(z * .19 - x * .09);
      final color = switch (world) {
        0 => Color.lerp(
          const Color(0xff384744),
          const Color(0xff42534b),
          variation,
        )!,
        1 => Color.lerp(
          const Color(0xff85888d),
          const Color(0xff9c9d9f),
          variation,
        )!,
        _ => Color.lerp(
          const Color(0xff99634a),
          const Color(0xffb27a59),
          variation,
        )!,
      };
      positions.addAll([x, height(x, z), z]);
      normals.addAll([normal.x, normal.y, normal.z]);
      colors.addAll([
        OpeningMeshBatch._linear(color.r),
        OpeningMeshBatch._linear(color.g),
        OpeningMeshBatch._linear(color.b),
        1,
      ]);
    }
  }
  for (var row = 0; row < zs.length - 1; row++) {
    for (var column = 0; column < xs.length - 1; column++) {
      final a = row * xs.length + column, b = a + xs.length;
      indices.addAll([a, b + 1, a + 1, a, b, b + 1]);
    }
  }
  return fs.Node(
    name: '連続した地表と滑らかな山稜',
    mesh: fs.Mesh(
      fs.MeshGeometry.fromArrays(
        positions: Float32List.fromList(positions),
        normals: Float32List.fromList(normals),
        colors: Float32List.fromList(colors),
        indices: indices,
        retainCpuData: false,
      ),
      fs.PhysicallyBasedMaterial()
        ..metallicFactor = 0
        ..roughnessFactor = .95,
    ),
  );
}

/// 半球の透明外殻。下半分が透けて床を突き抜けない専用geometry。
fs.MeshGeometry openingDomeGeometry() {
  final positions = <double>[], normals = <double>[];
  final indices = <int>[];
  const rings = 16, segments = 48;
  for (var row = 0; row <= rings; row++) {
    final elevation = row / rings * math.pi / 2;
    for (var column = 0; column <= segments; column++) {
      final angle = column / segments * math.pi * 2;
      final x = math.cos(angle) * math.cos(elevation);
      final y = math.sin(elevation);
      final z = math.sin(angle) * math.cos(elevation);
      positions.addAll([x, y, z]);
      normals.addAll([x, y, z]);
    }
  }
  for (var row = 0; row < rings; row++) {
    for (var column = 0; column < segments; column++) {
      final a = row * (segments + 1) + column, b = a + segments + 1;
      indices.addAll([a, b, a + 1, a + 1, b, b + 1]);
    }
  }
  return fs.MeshGeometry.fromArrays(
    positions: Float32List.fromList(positions),
    normals: Float32List.fromList(normals),
    indices: indices,
    retainCpuData: false,
  );
}
