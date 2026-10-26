import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/rendering/orbital_motion.dart';
import 'package:mars_terraforming/rendering/title_apparent_planet_scale.dart';
import 'package:mars_terraforming/rendering/title_scene_motion.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('異常時刻は初期構図になり、極端な長時間も有限で角度を保つ', () {
    final initial = TitleSceneMotion(0);
    for (final time in [
      double.nan,
      double.infinity,
      -double.infinity,
      -100.0,
    ]) {
      final motion = TitleSceneMotion(time);
      expect(motion.seconds, 0);
      _expectVector(motion.sunDirection, initial.sunDirection);
      _expectVector(motion.earthDirection, initial.earthDirection);
      _expectVector(motion.jupiterDirection, initial.jupiterDirection);
      _expectVector(motion.saturnDirection, initial.saturnDirection);
      _expectVector(motion.rocket.position, initial.rocket.position);
    }
    for (final time in [0.0, 1e12, 1e308, double.maxFinite]) {
      final motion = TitleSceneMotion(time);
      for (final angle in [
        motion.starAngle,
        motion.marsSpin,
        motion.earthAngle,
        motion.cloudAngle,
      ]) {
        expect(angle, inInclusiveRange(0, math.pi * 2));
      }
      for (final direction in [
        motion.sunDirection,
        motion.earthDirection,
        motion.jupiterDirection,
        motion.saturnDirection,
      ]) {
        _expectFiniteVector(direction);
        expect(direction.length, closeTo(1, 1e-6));
      }
      for (final relativeAu in [
        motion.sunRelativeAu,
        motion.earthRelativeAu,
        motion.jupiterRelativeAu,
        motion.saturnRelativeAu,
      ]) {
        _expectFiniteVector(relativeAu);
        expect(relativeAu.length, greaterThan(0));
      }
      for (final rotation in [
        motion.marsRotation(vm.Quaternion.identity()),
        motion.earthRotation,
        motion.sunRotation,
        motion.jupiterRotation,
        motion.saturnRotation,
      ]) {
        expect(rotation.storage.every((value) => value.isFinite), isTrue);
        expect(rotation.length, closeTo(1, 2e-6));
      }
      for (final pose in [
        motion.satellite,
        motion.rocket,
        motion.asteroid(1),
      ]) {
        _expectFiniteVector(pose.position);
        _expectFiniteVector(pose.velocity);
        _expectFrame(pose);
      }
    }
  });

  test('同じ時刻の天体と宇宙機の配置は呼び出し順序によらず再現する', () {
    final first = TitleSceneMotion(127.25);
    first.asteroid(1);
    first.sunRotation;
    final second = TitleSceneMotion(127.25);
    _expectVector(first.sunOffset, second.sunOffset);
    _expectVector(first.earthOffset, second.earthOffset);
    _expectVector(first.jupiterOffset, second.jupiterOffset);
    _expectVector(first.saturnOffset, second.saturnOffset);
    _expectVector(first.sunRelativeAu, second.sunRelativeAu);
    _expectVector(first.earthRelativeAu, second.earthRelativeAu);
    _expectVector(first.jupiterRelativeAu, second.jupiterRelativeAu);
    _expectVector(first.saturnRelativeAu, second.saturnRelativeAu);
    _expectVector(first.satellite.position, second.satellite.position);
    _expectVector(first.rocket.velocity, second.rocket.velocity);
    _expectRotation(first.earthRotation, second.earthRotation);
  });

  test('太陽・地球・巨惑星・星空は同じ太陽中心慣性系とカメラ座標を共有する', () {
    for (final time in [0.0, 32.5, 180.0, 583.0, 3600.0]) {
      final motion = TitleSceneMotion(time);
      final marsAngle =
          TitleSceneMotion.marsOrbitAtEpoch +
          time / TitleSceneMotion.marsYear * math.pi * 2;
      final mars = vm.Vector3(
        TitleDistantBody.mars.semiMajorAxisAu * math.cos(marsAngle),
        0,
        TitleDistantBody.mars.semiMajorAxisAu * math.sin(marsAngle),
      );
      final cameraToInertial = motion.cameraToInertial.asRotationMatrix();
      _expectVector(cameraToInertial.transformed(motion.sunRelativeAu), -mars);
      expect(
        motion.sunRelativeAu.length,
        closeTo(TitleDistantBody.mars.semiMajorAxisAu, 1e-6),
      );
      _expectVector(
        cameraToInertial.transformed(motion.sunDirection),
        (-mars).normalized(),
      );
      for (final (
            radius,
            period,
            phase,
            relativeAu,
            direction,
            offset,
            distance,
          )
          in [
            (
              TitleDistantBody.earth.semiMajorAxisAu,
              TitleSceneMotion.earthYear,
              TitleSceneMotion.earthOrbitAtEpoch,
              motion.earthRelativeAu,
              motion.earthDirection,
              motion.earthOffset,
              TitleSceneMotion.earthDistance,
            ),
            (
              TitleDistantBody.jupiter.semiMajorAxisAu,
              TitleSceneMotion.jupiterYear,
              TitleSceneMotion.jupiterOrbitAtEpoch,
              motion.jupiterRelativeAu,
              motion.jupiterDirection,
              motion.jupiterOffset,
              TitleSceneMotion.jupiterDistance,
            ),
            (
              TitleDistantBody.saturn.semiMajorAxisAu,
              TitleSceneMotion.saturnYear,
              TitleSceneMotion.saturnOrbitAtEpoch,
              motion.saturnRelativeAu,
              motion.saturnDirection,
              motion.saturnOffset,
              TitleSceneMotion.saturnDistance,
            ),
          ]) {
        final angle = phase + time / period * math.pi * 2;
        final planet = vm.Vector3(
          radius * math.cos(angle),
          0,
          radius * math.sin(angle),
        );
        _expectVector(cameraToInertial.transformed(relativeAu), planet - mars);
        expect(
          relativeAu.length,
          closeTo((planet - mars).length, 2e-5),
          reason: '見かけのサイズへ使う実AU距離を正規化で失わない',
        );
        _expectVector(relativeAu.normalized(), direction);
        _expectVector(
          cameraToInertial.transformed(direction),
          (planet - mars).normalized(),
        );
        _expectVector(offset.normalized(), direction);
        expect(offset.length, closeTo(distance, 2e-5));
      }
      _expectVector(motion.sunOffset.normalized(), motion.sunDirection);
      expect(motion.sunOffset.length, closeTo(120, 2e-5));
      expect(motion.earthOffset.length, closeTo(110, 2e-5));

      final skyRotation =
          vm.Quaternion.axisAngle(
            vm.Vector3(1, 0, 0),
            -TitleSceneMotion.cameraFrameTilt,
          ) *
          vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), motion.starAngle);
      _expectRotation(skyRotation, motion.cameraToInertial);
    }
  });

  test('火星一日やカメラ一周で遠景を固定せず、公転も見かけの向きを変える', () {
    final initial = TitleSceneMotion(0);
    final day = TitleSceneMotion(TitleSceneMotion.marsDay);
    expect(initial.sunDirection.dot(day.sunDirection), lessThan(.5));
    expect(
      (initial.earthDirection - day.earthDirection).length,
      greaterThan(.5),
    );
    final halfOrbit = TitleSceneMotion(TitleSceneMotion.cameraOrbitPeriod / 2);
    expect(initial.sunDirection.dot(halfOrbit.sunDirection), lessThan(0));
    final cameraOrbit = TitleSceneMotion(TitleSceneMotion.cameraOrbitPeriod);
    expect(
      (initial.sunDirection - cameraOrbit.sunDirection).length,
      greaterThan(.3),
    );
    final cycle = TitleSceneMotion(72000);
    _expectVector(initial.sunDirection, cycle.sunDirection);
    _expectVector(initial.earthDirection, cycle.earthDirection);
    _expectVector(initial.jupiterDirection, cycle.jupiterDirection);
    _expectVector(initial.saturnDirection, cycle.saturnDirection);
  });

  test('撮影姿勢を保って火星地理軸で自転し、カメラ周回と分離する', () {
    final authored = vm.Quaternion.euler(.7, -1.1, .35);
    final original = List<double>.of(authored.storage);
    final initial = TitleSceneMotion(0);
    _expectRotation(initial.marsRotation(authored), authored);
    for (final time in [30.0, 90.0, 180.0, 720.0, 1e12]) {
      final motion = TitleSceneMotion(time);
      final inertialMars =
          motion.cameraToInertial * motion.marsRotation(authored);
      _expectRotation(
        inertialMars,
        initial.cameraToInertial *
            authored *
            vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), motion.marsSpin),
      );
    }
    final afterThirty = TitleSceneMotion(30);
    final landmark = vm.Vector3(1, 0, 0);
    expect(
      (afterThirty
                  .marsRotation(authored)
                  .asRotationMatrix()
                  .transformed(landmark) -
              authored.asRotationMatrix().transformed(landmark))
          .length,
      greaterThan(.5),
      reason: 'カメラを地表と一緒に回して自転を相殺しない',
    );
    expect(
      afterThirty.cameraOrbit - TitleSceneMotion.cameraOrbitAtEpoch,
      closeTo(afterThirty.marsSpin * .25, 1e-10),
    );
    expect(authored.storage, orderedEquals(original));
  });

  test('地球・太陽・巨惑星の自転は慣性系でそれぞれの周期に閉じる', () {
    vm.Quaternion inertialEarth(double time) {
      final motion = TitleSceneMotion(time);
      return motion.cameraToInertial * motion.earthRotation;
    }

    vm.Quaternion inertialSun(double time) {
      final motion = TitleSceneMotion(time);
      return motion.cameraToInertial * motion.sunRotation;
    }

    vm.Quaternion inertialJupiter(double time) {
      final motion = TitleSceneMotion(time);
      return motion.cameraToInertial * motion.jupiterRotation;
    }

    vm.Quaternion inertialSaturn(double time) {
      final motion = TitleSceneMotion(time);
      return motion.cameraToInertial * motion.saturnRotation;
    }

    _expectRotation(inertialEarth(0), inertialEarth(TitleSceneMotion.earthDay));
    _expectRotation(inertialSun(0), inertialSun(TitleSceneMotion.sunDay));
    _expectRotation(
      inertialJupiter(0),
      inertialJupiter(TitleSceneMotion.jupiterDay),
    );
    _expectRotation(
      inertialSaturn(0),
      inertialSaturn(TitleSceneMotion.saturnDay),
    );
    for (final time in [0.0, 18.0, 60.0, 150.0]) {
      final pole = inertialSaturn(time)
          .asRotationMatrix()
          .transformed(vm.Vector3(0, 1, 0));
      expect(pole.y, closeTo(math.cos(TitleSceneMotion.saturnAxialTilt), 1e-6));
    }
    expect(
      (inertialSun(0).asRotationMatrix().transformed(vm.Vector3(1, 0, 0)) -
              inertialSun(TitleSceneMotion.sunDay / 4)
                  .asRotationMatrix()
                  .transformed(vm.Vector3(1, 0, 0)))
          .length,
      greaterThan(1),
    );
  });

  test('巨惑星は最初から見え、120秒以内に地球と太陽も地平線へ現れる', () {
    for (final aspect in [568 / 320, 844 / 390]) {
      for (final time in [0.0, 3.0, 18.0, 30.0, 60.0]) {
        final motion = TitleSceneMotion(time);
        expect(
          _isVisible(motion.jupiterOffset, aspect),
          isTrue,
          reason: '$time秒の木星は火星に遮蔽されず画角へ入る',
        );
        expect(
          _isVisible(motion.saturnOffset, aspect),
          isTrue,
          reason: '$time秒の土星は火星に遮蔽されず画角へ入る',
        );
      }
      final firstTwoMinutes = [
        for (var time = 0.0; time <= 120; time += 5) TitleSceneMotion(time),
      ];
      expect(
        firstTwoMinutes.any((motion) => _isVisible(motion.earthOffset, aspect)),
        isTrue,
      );
      expect(
        firstTwoMinutes.any((motion) => _isVisible(motion.sunOffset, aspect)),
        isTrue,
      );
    }
  });

  test('遠景を画面へ固定せず、各天体は自然な運動で画角へ出入りする', () {
    for (final offsetAt in [
      (TitleSceneMotion motion) => motion.sunOffset,
      (TitleSceneMotion motion) => motion.earthOffset,
      (TitleSceneMotion motion) => motion.jupiterOffset,
      (TitleSceneMotion motion) => motion.saturnOffset,
    ]) {
      var visible = 0;
      var hidden = 0;
      for (var time = 0.0; time < 720; time += 5) {
        if (_isVisible(offsetAt(TitleSceneMotion(time)), 844 / 390)) {
          visible++;
        } else {
          hidden++;
        }
      }
      expect(visible, greaterThan(0));
      expect(hidden, greaterThan(0));
    }
  });

  test('円・高離心率・傾斜楕円で周期の位置・速度・姿勢が連続する', () {
    for (final orbit in [
      KeplerOrbit(semiMajorAxis: 12, eccentricity: 0, period: 100),
      KeplerOrbit(
        semiMajorAxis: 12,
        eccentricity: .95,
        period: 100,
        inclination: .4,
      ),
      ..._localOrbits,
    ]) {
      final start = orbit.sample(0);
      final full = orbit.sample(orbit.period);
      _expectVector(start.position, full.position);
      _expectVector(start.velocity, full.velocity);
      _expectRotation(start.orientation, full.orientation);
      // Vector3 は Float32。差分幅を十分に取り量子化誤差を抑える。
      const epsilon = .001;
      final before = orbit.sample(orbit.period - epsilon);
      final after = orbit.sample(orbit.period + epsilon);
      _expectVector(
        (after.position - before.position) / (epsilon * 2),
        start.velocity,
        tolerance: .003,
      );
    }
  });

  test('解析速度は位置の微分と一致し姿勢が接線と軌道法線を向く', () {
    const delta = .001;
    for (final orbit in _localOrbits) {
      for (final fraction in [.1, .33, .72]) {
        final time = orbit.period * fraction;
        final pose = orbit.sample(time);
        final numericalVelocity =
            (orbit.sample(time + delta).position -
                orbit.sample(time - delta).position) /
            (delta * 2);
        _expectVector(pose.velocity, numericalVelocity, tolerance: .002);
        expect(pose.position.dot(pose.orbitNormal), closeTo(0, 2e-5));
        expect(pose.velocity.dot(pose.orbitNormal), closeTo(0, 2e-5));
        _expectFrame(pose);
      }
    }
  });

  test('近傍軌道は火星地形の外側を通りカメラへ接近しすぎない', () {
    final cameraRelativeToMars = vm.Vector3(0, 8.4, 14);
    for (final orbit in _localOrbits) {
      var maxY = -double.infinity;
      var minY = double.infinity;
      for (var i = 0; i <= 720; i++) {
        final pose = orbit.sample(orbit.period * i / 360);
        final radius = pose.position.length;
        expect(radius, greaterThan(8.14 + 1));
        expect(radius, greaterThanOrEqualTo(orbit.periapsis - 2e-5));
        expect(radius, lessThanOrEqualTo(orbit.apoapsis + 2e-5));
        expect((pose.position - cameraRelativeToMars).length, greaterThan(9.5));
        minY = math.min(minY, pose.position.y);
        maxY = math.max(maxY, pose.position.y);
      }
      expect(maxY - minY, greaterThan(1));
    }
  });

  test('各機体の軌道が火星に遮蔽されず横長タイトルの画角に繰り返し入る', () {
    // 実画面の構図を火星中心相対座標で検査する。地形全体を包む球を使い、
    // 画角にあっても火星の裏なら可視として数えない。
    final camera = vm.Vector3(0, 8.4, 14);
    final target = vm.Vector3(0, 9.2, 0);
    final forward = (target - camera).normalized();
    final right = forward.cross(vm.Vector3(0, 1, 0)).normalized();
    final up = right.cross(forward).normalized();
    final halfHeight = math.tan(43 * math.pi / 360);
    const aspect = 844 / 390;
    const samples = 720;
    for (final orbit in _localOrbits) {
      var visibleSamples = 0;
      var highestVisibleY = -double.infinity;
      for (var i = 0; i < samples; i++) {
        final position = orbit.sample(orbit.period * i / samples).position;
        final ray = position - camera;
        final depth = ray.dot(forward);
        if (depth <= .25 || depth >= 240) continue;
        final x = ray.dot(right) / (depth * halfHeight * aspect);
        final y = ray.dot(up) / (depth * halfHeight);
        if (x.abs() > 1 || y.abs() > 1) continue;
        final closestPointFraction = (-camera.dot(ray) / ray.length2)
            .clamp(0.0, 1.0)
            .toDouble();
        final closestPoint = camera + ray * closestPointFraction;
        if (closestPoint.length2 <= 8.14 * 8.14) continue;
        visibleSamples++;
        highestVisibleY = math.max(highestVisibleY, y);
      }
      // 一瞬だけ画面下端へかすめる軌道ではなく、十分な時間と高さを確保する。
      expect(visibleSamples, greaterThan(samples * .15));
      expect(highestVisibleY, greaterThan(-.35));
    }
  });

  test('旧飛来窓の境界も物体を消さず同じ軌道を進む', () {
    for (final time in [0.0, 4.0, 13.0, 18.0, 47.0, 51.0, 61.0]) {
      final motion = TitleSceneMotion(time);
      _expectVector(
        motion.rocket.position,
        TitleSceneMotion.rocketOrbit.sample(time).position,
      );
      _expectVector(
        motion.satellite.position,
        TitleSceneMotion.satelliteOrbit.sample(time).position,
      );
      for (var i = 0; i < TitleSceneMotion.asteroidOrbits.length; i++) {
        _expectVector(
          motion.asteroid(i).position,
          TitleSceneMotion.asteroidOrbits[i].sample(time).position,
        );
      }
    }
  });

  test('不正な軌道と範囲外の小惑星は明確に拒否する', () {
    for (final eccentricity in [-.1, 1.0, double.nan]) {
      expect(
        () => KeplerOrbit(
          semiMajorAxis: 10,
          eccentricity: eccentricity,
          period: 100,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => KeplerOrbit(semiMajorAxis: 0, eccentricity: 0, period: 100),
      throwsArgumentError,
    );
    expect(
      () => KeplerOrbit(
        semiMajorAxis: 10,
        eccentricity: 0,
        period: double.infinity,
      ),
      throwsArgumentError,
    );
    expect(() => periodicMotionAngle(1, 0), throwsArgumentError);
    expect(() => TitleSceneMotion(0).asteroid(-1), throwsRangeError);
    expect(() => TitleSceneMotion(0).asteroid(2), throwsRangeError);
  });
}

List<KeplerOrbit> get _localOrbits => [
  TitleSceneMotion.satelliteOrbit,
  TitleSceneMotion.rocketOrbit,
  ...TitleSceneMotion.asteroidOrbits,
];

/// 遠景はcamera+offsetへ置き、火星中心相対の球で視線の遮蔽を除く。
bool _isVisible(vm.Vector3 cameraOffset, double aspect) {
  final camera = vm.Vector3(0, 8.4, 14);
  final target = vm.Vector3(0, 9.2, 0);
  final forward = (target - camera).normalized();
  final right = forward.cross(vm.Vector3(0, 1, 0)).normalized();
  final up = right.cross(forward).normalized();
  final ray = cameraOffset;
  final depth = ray.dot(forward);
  if (depth <= .25 || depth >= 240) return false;
  final halfHeight = math.tan(43 * math.pi / 360);
  final x = ray.dot(right) / (depth * halfHeight * aspect);
  final y = ray.dot(up) / (depth * halfHeight);
  if (x.abs() > 1 || y.abs() > 1) return false;
  final closestPointFraction = (-camera.dot(ray) / ray.length2)
      .clamp(0.0, 1.0)
      .toDouble();
  final closestPoint = camera + ray * closestPointFraction;
  return closestPoint.length2 > 8.14 * 8.14;
}

void _expectFiniteVector(vm.Vector3 vector) {
  expect(vector.x.isFinite && vector.y.isFinite && vector.z.isFinite, isTrue);
}

void _expectVector(
  vm.Vector3 actual,
  vm.Vector3 expected, {
  double tolerance = 2e-5,
}) {
  expect(actual.x, closeTo(expected.x, tolerance));
  expect(actual.y, closeTo(expected.y, tolerance));
  expect(actual.z, closeTo(expected.z, tolerance));
}

void _expectRotation(vm.Quaternion actual, vm.Quaternion expected) {
  for (final axis in [
    vm.Vector3(1, 0, 0),
    vm.Vector3(0, 1, 0),
    vm.Vector3(0, 0, 1),
  ]) {
    _expectVector(
      actual.asRotationMatrix().transformed(axis),
      expected.asRotationMatrix().transformed(axis),
    );
  }
}

void _expectFrame(OrbitalPose pose) {
  final rotation = pose.orientation.asRotationMatrix();
  _expectVector(
    rotation.transformed(vm.Vector3(0, 1, 0)),
    pose.velocity.normalized(),
  );
  _expectVector(rotation.transformed(vm.Vector3(0, 0, 1)), pose.orbitNormal);
  expect(pose.orientation.length, closeTo(1, 2e-6));
  expect(rotation.determinant(), closeTo(1, 2e-6));
}
