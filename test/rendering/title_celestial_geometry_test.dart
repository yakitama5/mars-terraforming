import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/rendering/title_planet_geometry.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  late MeasuredPlanetHeightField measured;
  setUpAll(() {
    measured = MeasuredPlanetHeightField(
      ByteData.sublistView(
        File('assets/title/planets/mars_mola_height_1k.bin').readAsBytesSync(),
      ),
    );
  });

  test('MOLAは実際のOlympus MonsとHellasの上下を保持する', () {
    expect(measured.at(18, -133), greaterThan(10000));
    expect(measured.at(-42, 70), lessThan(-4000));
    expect(measured.at(18, -133), closeTo(measured.at(18, 227), 1e-6));
    expect(measured.at(90, -120), measured.at(90, 80));
    expect(measured.at(-90, -120), measured.at(-90, 80));
  });

  test('測定球のUV・継目・法線・接線は写真と同じ向きに揃う', () {
    final data = measuredPlanetMeshData(heightField: measured);
    const columns = 320, rows = 192;
    vm.Vector3 point(List<double> values, int i) =>
        vm.Vector3(values[i * 3], values[i * 3 + 1], values[i * 3 + 2]);
    expect(data.positions.length ~/ 3, lessThan(65536));
    for (var row = 0; row <= rows; row++) {
      final left = row * (columns + 1), right = left + columns;
      expect(
        (point(data.positions, left) - point(data.positions, right)).length,
        lessThan(1e-5),
      );
      expect(data.texCoords[left * 2], 0);
      expect(data.texCoords[right * 2], 1);
    }
    for (var i = 0; i < data.positions.length ~/ 3; i++) {
      final position = point(data.positions, i),
          normal = point(data.normals, i);
      expect(position.length, inInclusiveRange(3.08, 3.14));
      expect(normal.length, closeTo(1, 1e-5));
      final tangent = vm.Vector3(
        data.tangents[i * 4],
        data.tangents[i * 4 + 1],
        data.tangents[i * 4 + 2],
      );
      expect(tangent.dot(normal), closeTo(0, 1e-5));
      expect(data.colors[i * 4], 1);
      expect(data.colors[i * 4 + 1], 1);
      expect(data.colors[i * 4 + 2], 1);
    }
    for (var i = 0; i < data.indices.length; i += 3) {
      final a = point(data.positions, data.indices[i]);
      final b = point(data.positions, data.indices[i + 1]);
      final c = point(data.positions, data.indices[i + 2]);
      expect((b - a).cross(c - a).dot(a + b + c), greaterThan(0));
    }
  });

  test('不正な標高ファイルを平面や架空の地形へ黙って置換しない', () {
    expect(() => MeasuredPlanetHeightField(ByteData(4)), throwsFormatException);
    final broken = ByteData(8)..setUint32(0, 0x4d4f4c41);
    broken.setUint16(4, 1024, Endian.little);
    broken.setUint16(6, 512, Endian.little);
    expect(() => MeasuredPlanetHeightField(broken), throwsFormatException);
  });
}
