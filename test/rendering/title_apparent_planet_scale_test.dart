import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/rendering/title_apparent_planet_scale.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  ApparentBody body(TitleDistantBody planet, double distanceAu) => ApparentBody(
    radiusKm: planet.equatorialRadiusKm,
    relativeAu: vm.Vector3(0, 0, -distanceAu),
  );

  test('AU・赤道半径・J2000半長径はNASA/JPLの同じ単位で固定する', () {
    expect(TitleSolarSystemScale.kilometersPerAu, 149597870.7);
    for (final (planet, radiusKm, semiMajorAxisAu) in [
      (TitleDistantBody.sun, 695700.0, 0.0),
      (TitleDistantBody.earth, 6378.1366, 1.00000261),
      (TitleDistantBody.mars, 3396.19, 1.52371034),
      (TitleDistantBody.jupiter, 71492.0, 5.20288700),
      (TitleDistantBody.saturn, 60268.0, 9.53667594),
    ]) {
      expect(planet.equatorialRadiusKm, radiusKm);
      expect(planet.semiMajorAxisAu, semiMajorAxisAu);
    }
  });

  test('火星の平均距離から見る太陽は実寸で角直径約0.35度になる', () {
    final sun = body(
      TitleDistantBody.sun,
      TitleDistantBody.mars.semiMajorAxisAu,
    );
    final diameterDegrees = sun.angularRadius * 2 * 180 / math.pi;
    expect(diameterDegrees, inInclusiveRange(.34, .36));
    expect(
      math.asin(sun.renderedSphereRadius(120) / 120),
      closeTo(sun.angularRadius, 1e-14),
    );
  });

  test('球の接線による輪郭を用い、角半径と圧縮距離から正確な球半径へ戻す', () {
    final sphere = ApparentBody(
      radiusKm: TitleSolarSystemScale.kilometersPerAu / 2,
      relativeAu: vm.Vector3(0, 0, -1),
    );
    expect(sphere.angularRadius, closeTo(math.pi / 6, 1e-14));
    expect(sphere.renderedSphereRadius(200), closeTo(100, 1e-12));
    expect(
      sphere.modelScale(renderDistance: 200, modelRadius: 3.1) * 3.1,
      closeTo(100, 1e-12),
    );
  });

  test('実AU相対ベクトルの長さで見かけが変わり、実寸の表示半径は距離に反比例する', () {
    final first = body(TitleDistantBody.jupiter, 4);
    final second = body(TitleDistantBody.jupiter, 8);
    final diagonal = ApparentBody(
      radiusKm: TitleDistantBody.jupiter.equatorialRadiusKm,
      relativeAu: vm.Vector3(3, 4, 0),
    );
    expect(diagonal.distanceAu, 5);
    expect(first.angularRadius, greaterThan(second.angularRadius));
    expect(
      first.renderedSphereRadius(140) / second.renderedSphereRadius(140),
      closeTo(2, 1e-12),
    );
  });

  test('圧縮描画距離と元モデル半径を変えても観測角半径は同じになる', () {
    final earth = body(TitleDistantBody.earth, .8);
    for (final renderDistance in [20.0, 110.0, 155.0, 1000.0]) {
      for (final modelRadius in [1.0, 3.1]) {
        final scale = earth.modelScale(
          renderDistance: renderDistance,
          modelRadius: modelRadius,
        );
        expect(
          math.asin(scale * modelRadius / renderDistance),
          closeTo(earth.angularRadius, 1e-14),
        );
      }
    }
  });

  test('惑星の共通倍率は角度の比率を保ち、倍率を渡さない太陽は1倍を維持する', () {
    final planets = [
      body(TitleDistantBody.earth, .8),
      body(TitleDistantBody.jupiter, 4),
      body(TitleDistantBody.saturn, 8),
    ];
    final sun = body(
      TitleDistantBody.sun,
      TitleDistantBody.mars.semiMajorAxisAu,
    );
    final sunRadius = sun.renderedSphereRadius(120);
    for (final magnification in [1.0, 20.0, 64.0, 100.0, 128.0]) {
      for (final planet in planets) {
        final angle = math.asin(
          planet.renderedSphereRadius(155, magnification: magnification) / 155,
        );
        expect(angle / planet.angularRadius, closeTo(magnification, 1e-10));
      }
      expect(sun.renderedSphereRadius(120), sunRadius);
    }
  });

  test('camera anchored配置はカメラ位置によらず同じ距離・視線方向を保つ', () {
    final planet = ApparentBody(
      radiusKm: TitleDistantBody.saturn.equatorialRadiusKm,
      relativeAu: vm.Vector3(3, 4, -5),
    );
    for (final camera in [vm.Vector3(0, 1, 14), vm.Vector3(-2, 3, 9)]) {
      final original = List<double>.of(camera.storage);
      final center = planet.cameraAnchoredPosition(camera, 155);
      final fromCamera = center - camera;
      expect(fromCamera.length, closeTo(155, 2e-5));
      expect(
        (fromCamera.normalized() - planet.direction).length,
        lessThan(1e-6),
      );
      expect(camera.storage, orderedEquals(original));
    }
  });

  test('相対ベクトルはコピーし、呼出側の変更で確定した角度や方向を変えない', () {
    final source = vm.Vector3(3, 4, -5);
    final original = source.clone();
    final planet = ApparentBody(
      radiusKm: TitleDistantBody.earth.equatorialRadiusKm,
      relativeAu: source,
    );
    final angle = planet.angularRadius;
    source.setValues(9, 9, 9);
    planet.relativeAu.setValues(8, 8, 8);
    planet.direction.setValues(7, 7, 7);
    expect(planet.relativeAu.storage, orderedEquals(original.storage));
    expect(planet.angularRadius, angle);
    expect((planet.direction - original.normalized()).length, lessThan(1e-7));
  });

  test('非有限値・正でない半径や距離・球の内部の観測者を拒否する', () {
    for (final radius in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => ApparentBody(radiusKm: radius, relativeAu: vm.Vector3(0, 0, -1)),
        throwsArgumentError,
      );
    }
    for (final relative in [
      vm.Vector3.zero(),
      vm.Vector3(double.nan, 0, 1),
      vm.Vector3(0, double.infinity, 1),
      vm.Vector3(1, 0, -double.infinity),
      vm.Vector3(double.maxFinite, 0, 0),
    ]) {
      expect(
        () => ApparentBody(radiusKm: 1, relativeAu: relative),
        throwsArgumentError,
      );
    }
    for (final distance in [.5, 1.0]) {
      expect(
        () => ApparentBody(
          radiusKm: TitleSolarSystemScale.kilometersPerAu,
          relativeAu: vm.Vector3(distance, 0, 0),
        ),
        throwsArgumentError,
      );
    }
  });

  test('倍率・描画距離・元モデル半径の不正値と90度以上の角半径を拒否する', () {
    final planet = ApparentBody(
      radiusKm: TitleSolarSystemScale.kilometersPerAu / 2,
      relativeAu: vm.Vector3(0, 0, -1),
    );
    for (final value in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      -double.infinity,
    ]) {
      expect(() => planet.renderedSphereRadius(value), throwsArgumentError);
      expect(
        () => planet.renderedSphereRadius(120, magnification: value),
        throwsArgumentError,
      );
      expect(
        () => planet.modelScale(renderDistance: 120, modelRadius: value),
        throwsArgumentError,
      );
      expect(
        () => planet.cameraAnchoredPosition(vm.Vector3.zero(), value),
        throwsArgumentError,
      );
    }
    for (final magnification in [3.0, 4.0, double.maxFinite]) {
      expect(
        () => planet.renderedSphereRadius(120, magnification: magnification),
        throwsArgumentError,
      );
    }
    expect(
      () => planet.cameraAnchoredPosition(vm.Vector3(double.nan, 0, 0), 120),
      throwsArgumentError,
    );
  });
}
