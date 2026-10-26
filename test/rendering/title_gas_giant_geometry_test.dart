import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/rendering/title_gas_giant_geometry.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('NASA元meshの環半径と各頂点属性・indicesが整合する', () {
    final mesh = gasGiantRingMeshData();
    const segments = 256, stride = segments + 1, vertexCount = stride * 2;
    expect(mesh.positions.length, vertexCount * 3);
    expect(mesh.normals.length, vertexCount * 3);
    expect(mesh.colors.length, vertexCount * 4);
    expect(mesh.texCoords.length, vertexCount * 2);
    expect(mesh.tangents.length, vertexCount * 4);
    expect(mesh.indices.length, segments * 6);
    expect(mesh.indices.toSet().length, vertexCount);
    expect(
      mesh.indices.every((index) => index >= 0 && index < vertexCount),
      isTrue,
    );
    for (final values in [
      mesh.positions,
      mesh.normals,
      mesh.colors,
      mesh.texCoords,
      mesh.tangents,
    ]) {
      expect(values.every((value) => value.isFinite), isTrue);
    }
    for (var index = 0; index < vertexCount; index++) {
      final point = _vector(mesh.positions, index);
      expect(point.y, 0);
      expect(point.length, closeTo(index < stride ? 1.232301 : 2.330901, 1e-6));
      final normal = _vector(mesh.normals, index);
      expect(normal.storage, orderedEquals([0.0, 1.0, 0.0]));
      expect(
        mesh.colors.sublist(index * 4, index * 4 + 4),
        orderedEquals([1.0, 1.0, 1.0, 1.0]),
      );
      final tangent = vm.Vector3(
        mesh.tangents[index * 4],
        mesh.tangents[index * 4 + 1],
        mesh.tangents[index * 4 + 2],
      );
      expect(tangent.length, closeTo(1, 1e-6));
      expect(tangent.dot(normal), closeTo(0, 1e-6));
      expect(tangent.dot(point.normalized()), closeTo(1, 1e-6));
      final bitangent = normal.cross(tangent) * mesh.tangents[index * 4 + 3];
      final azimuth = vm.Vector3(-point.z, 0, point.x)..normalize();
      expect(bitangent.dot(azimuth), closeTo(1, 1e-6));
    }
  });

  for (final segments in [3, 8, 256]) {
    test('$segments分割の環は縮退や重複面を作らず+Y向きに一周を覆う', () {
      const innerRadius = 1.4, outerRadius = 2.8;
      final mesh = gasGiantRingMeshData(
        innerRadius: innerRadius,
        outerRadius: outerRadius,
        segments: segments,
      );
      var area = 0.0;
      for (var index = 0; index < mesh.indices.length; index += 3) {
        final a = _vector(mesh.positions, mesh.indices[index]);
        final b = _vector(mesh.positions, mesh.indices[index + 1]);
        final c = _vector(mesh.positions, mesh.indices[index + 2]);
        final face = (b - a).cross(c - a);
        expect(face.y, greaterThan(0));
        expect(face.x, 0);
        expect(face.z, 0);
        area += face.length / 2;
      }
      final polygonArea =
          segments *
          math.sin(math.pi * 2 / segments) *
          (outerRadius * outerRadius - innerRadius * innerRadius) /
          2;
      expect(area, closeTo(polygonArea, 1e-4));
    });
  }

  test('シームの位置と接空間は完全に閉じ、UV横軸は半径へ対応する', () {
    const segments = 8, stride = segments + 1;
    final mesh = gasGiantRingMeshData(segments: segments);
    for (var row = 0; row < 2; row++) {
      for (final (values, width) in [
        (mesh.positions, 3),
        (mesh.normals, 3),
        (mesh.colors, 4),
        (mesh.tangents, 4),
      ]) {
        final first = row * stride * width;
        final last = (row * stride + segments) * width;
        expect(
          values.sublist(first, first + width),
          orderedEquals(values.sublist(last, last + width)),
        );
      }
      for (var column = 0; column <= segments; column++) {
        final index = row * stride + column;
        expect(mesh.texCoords[index * 2], row.toDouble());
        expect(mesh.texCoords[index * 2 + 1], closeTo(column / segments, 1e-7));
      }
      final quarterTurn = _vector(mesh.positions, row * stride + segments ~/ 4);
      expect(quarterTurn.x, closeTo(0, 1e-7));
      expect(quarterTurn.z, closeTo(row == 0 ? 1.232301 : 2.330901, 1e-6));
    }
    expect(
      mesh.indices.sublist(mesh.indices.length - 6),
      orderedEquals([
        segments - 1,
        segments,
        stride + segments - 1,
        segments,
        stride + segments,
        stride + segments - 1,
      ]),
    );
  });

  test('半径・分割数の不正値とFloat32で潰れる環を明確に拒否する', () {
    for (final inner in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      -double.infinity,
    ]) {
      expect(
        () => gasGiantRingMeshData(innerRadius: inner),
        throwsArgumentError,
      );
    }
    for (final outer in [
      -1.0,
      0.0,
      1.232301,
      double.nan,
      double.infinity,
      -double.infinity,
      double.maxFinite,
      1.232301 + 1e-12,
    ]) {
      expect(
        () => gasGiantRingMeshData(outerRadius: outer),
        throwsArgumentError,
      );
    }
    expect(
      () => gasGiantRingMeshData(innerRadius: 1e-300, outerRadius: 2e-300),
      throwsArgumentError,
    );
    for (final segments in [-1, 0, 1, 2]) {
      expect(
        () => gasGiantRingMeshData(segments: segments),
        throwsArgumentError,
      );
    }
  });
}

vm.Vector3 _vector(List<double> values, int index) =>
    vm.Vector3(values[index * 3], values[index * 3 + 1], values[index * 3 + 2]);
