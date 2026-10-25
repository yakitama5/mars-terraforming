import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/rendering/title_planet_geometry.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('地形は経度の継ぎ目と極で閉じ、全方向で有限の半径を持つ', () {
    for (var lat = -90.0; lat <= 90; lat += 3) {
      final left = TitleMarsSurface.point(lat, -180);
      final right = TitleMarsSurface.point(lat, 180);
      expect((left - right).length, lessThan(1e-5));
      final leftColor = TitleMarsSurface.color(lat, -180);
      final rightColor = TitleMarsSurface.color(lat, 180);
      expect(leftColor.r, closeTo(rightColor.r, 1e-8));
      expect(leftColor.g, closeTo(rightColor.g, 1e-8));
      expect(leftColor.b, closeTo(rightColor.b, 1e-8));
      for (var lon = -180.0; lon <= 180; lon += 6) {
        final point = TitleMarsSurface.point(lat, lon);
        expect(point.length.isFinite, isTrue);
        expect(
          point.length,
          inInclusiveRange(
            TitleMarsSurface.radius * (1 + TitleMarsSurface.minElevationRatio) -
                1e-5,
            TitleMarsSurface.radius * (1 + TitleMarsSurface.maxElevationRatio) +
                1e-5,
          ),
        );
        if (lat.abs() == 90) {
          expect(point.length, closeTo(TitleMarsSurface.radius, 1e-5));
        }
      }
    }
  });

  test('峡谷・火山・クレーターは色だけでなく実際の凹凸を持つ', () {
    final canyon = TitleMarsSurface.elevation(47, 190);
    final plateau = TitleMarsSurface.elevation(53, 190);
    expect(canyon, lessThan(plateau - .005));
    final volcano = TitleMarsSurface.elevation(57, 143);
    final plain = TitleMarsSurface.elevation(57, 120);
    expect(volcano, greaterThan(plain + .012));
    const crater = (64.0, 184.0, 5.5);
    final floor = TitleMarsSurface.elevation(crater.$1, crater.$2);
    final rim = TitleMarsSurface.elevation(crater.$1 + crater.$3, crater.$2);
    expect(floor, lessThan(rim - .004));
  });

  test('主峡谷は局所的な浅い裂け目で、同じ緯度を横断する溝にしない', () {
    final center = TitleMarsSurface.elevation(47, 190);
    final northBank = TitleMarsSurface.elevation(50, 190);
    final southBank = TitleMarsSurface.elevation(44, 190);
    expect(center, lessThan(math.min(northBank, southBank) - .004));
    expect(center, greaterThan(-.02));
    // 主裂け目の東西を離れた地点は、長い均一な帯へ沈めない。
    expect(TitleMarsSurface.elevation(47, 260), greaterThan(-.005));
    expect(TitleMarsSurface.elevation(47, 100), greaterThan(-.005));
  });

  test('滑らかな地形の法線は正規化され、三角形は外向きで極の縮退がない', () {
    final mesh = titleMarsMeshData(rows: 40, columns: 80);
    vm.Vector3 vector(List<double> values, int index) => vm.Vector3(
      values[index * 3],
      values[index * 3 + 1],
      values[index * 3 + 2],
    );
    for (var i = 0; i < mesh.positions.length ~/ 3; i++) {
      final point = vector(mesh.positions, i), normal = vector(mesh.normals, i);
      expect(normal.length, closeTo(1, 1e-5));
      expect(normal.dot(point), greaterThan(0));
      final tangent = vm.Vector3(
        mesh.tangents[i * 4],
        mesh.tangents[i * 4 + 1],
        mesh.tangents[i * 4 + 2],
      );
      expect(tangent.length, closeTo(1, 1e-5));
      expect(tangent.dot(normal), closeTo(0, 1e-5));
    }
    for (var i = 0; i < mesh.indices.length; i += 3) {
      final a = vector(mesh.positions, mesh.indices[i]);
      final b = vector(mesh.positions, mesh.indices[i + 1]);
      final c = vector(mesh.positions, mesh.indices[i + 2]);
      final cross = (b - a).cross(c - a);
      expect(cross.length, greaterThan(1e-7));
      expect(cross.dot(a + b + c), greaterThan(0));
    }
    for (var row = 0; row <= 40; row++) {
      final left = vector(mesh.normals, row * 81);
      final right = vector(mesh.normals, row * 81 + 80);
      expect((left - right).length, lessThan(1e-5));
    }
  });

  test('緑化は凹凸・氷冠を動かさず限定された入植域の配色だけを変える', () {
    final untouched = TitleMarsSurface.color(52, 190);
    final developed = TitleMarsSurface.color(52, 190, greening: 1);
    expect(developed, isNot(untouched));
    expect(developed.g / developed.r, greaterThan(untouched.g / untouched.r));
    final remote = TitleMarsSurface.color(-40, 0, greening: 1);
    final remoteOriginal = TitleMarsSurface.color(-40, 0);
    expect((remote.r - remoteOriginal.r).abs(), lessThan(.001));
    expect(
      TitleMarsSurface.color(90, 0, greening: double.nan),
      TitleMarsSurface.color(90, 0),
    );
    // 世界状態に依存せず同じ座標へ同じ地形を再現する。
    expect(
      TitleMarsSurface.elevation(24, 190),
      closeTo(TitleMarsSurface.elevation(24, 190 + 360), 1e-10),
    );
  });

  test('タイトルの標準地形は高密度でも16bit頂点範囲に収まる', () {
    final mesh = titleMarsMeshData();
    expect(mesh.positions.length ~/ 3, lessThan(65536));
    expect(mesh.indices.length ~/ 3, greaterThan(100000));
    expect(mesh.indices.reduce(math.max), lessThan(mesh.positions.length ~/ 3));
  });

  test('砂塵のマップは決定的で不透明、法線の向きは外向きを保つ', () {
    final first = TitleMarsDetailPixels.generate(width: 128, height: 64);
    final second = TitleMarsDetailPixels.generate(width: 128, height: 64);
    expect(first.albedo, orderedEquals(second.albedo));
    expect(first.normal, orderedEquals(second.normal));
    final values = <int>{};
    for (var i = 0; i < first.albedo.length; i += 4) {
      values.add(first.albedo[i]);
      expect(first.albedo[i + 3], 255);
      expect(first.normal[i + 3], 255);
      expect(first.normal[i + 2], greaterThan(128));
    }
    expect(values.length, greaterThan(5));
  });
}
