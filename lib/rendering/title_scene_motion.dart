import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import 'orbital_motion.dart';

export 'orbital_motion.dart' show KeplerOrbit, OrbitalPose;

/// 表示用の単調時刻だけを使う。端末時計やゲームの時刻には触れない。
///
/// 太陽中心の共通慣性系から火星の身体固定座標へ変換する。周期・初期位相・
/// 傾斜はタイトルの構図のために圧縮した美術仕様であり、実暦ではない。
class TitleSceneMotion {
  TitleSceneMotion(double seconds) : seconds = safeMotionSeconds(seconds);

  final double seconds;

  static const marsDay = 180.0;
  static const marsYear = 720.0;
  static const earthYear = 450.0;
  static const earthDay = 55.0;
  static const sunDay = 112.0;
  static const sunDistance = 120.0;
  static const earthDistance = 110.0;
  static const marsAxialTilt = .30;
  // 最初は地形の見える日中。回転が進むと地球や太陽が地平線へ巡る。
  static const marsSpinAtEpoch = 4.2;

  /// 火星身体固定の見かけの近傍軌道。軌道面の法線を視線へ寄せ、地平線の
  /// 上に弧が現れつつカメラへ接近しない傾斜を選ぶ。近日点を含めて最大
  /// 地形半径約 8.14 の外側を通る。
  static final satelliteOrbit = KeplerOrbit(
    semiMajorAxis: 10.3,
    eccentricity: .04,
    period: 92,
    inclination: .92,
    ascendingNode: .12,
    argumentOfPeriapsis: .15,
    meanAnomalyAtEpoch: 4.2,
  );
  static final rocketOrbit = KeplerOrbit(
    semiMajorAxis: 11.2,
    eccentricity: .06,
    period: 136,
    inclination: 1.03,
    ascendingNode: -.18,
    argumentOfPeriapsis: .65,
    meanAnomalyAtEpoch: 2.1,
  );
  static final asteroidOrbits = List<KeplerOrbit>.unmodifiable([
    KeplerOrbit(
      semiMajorAxis: 12,
      eccentricity: .06,
      period: 196,
      inclination: .84,
      ascendingNode: .24,
      argumentOfPeriapsis: .35,
      meanAnomalyAtEpoch: 4.2,
    ),
    KeplerOrbit(
      semiMajorAxis: 12.8,
      eccentricity: .07,
      period: 241,
      inclination: 1.10,
      ascendingNode: -.26,
      argumentOfPeriapsis: -.4,
      meanAnomalyAtEpoch: 5.5,
    ),
  ]);

  double get marsSpin => periodicMotionAngle(seconds, marsDay, marsSpinAtEpoch);

  /// 空の sampling は視線を身体固定系から慣性系へ戻すので + 自転角。
  /// 軸傾斜を含めた完全な変換には [bodyToInertial] を使う。
  double get starAngle => marsSpin;
  double get earthAngle => periodicMotionAngle(seconds, earthDay, -2.1);
  double get cloudAngle => periodicMotionAngle(seconds, math.pi * 2 / .003);

  late final vm.Quaternion inertialToBody =
      vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -marsSpin) *
      vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), marsAxialTilt);
  late final vm.Quaternion bodyToInertial = inertialToBody.conjugated();

  late final vm.Vector3 _marsInertial = _circularPosition(
    1.52,
    periodicMotionAngle(seconds, marsYear, math.pi / 2),
  );
  late final vm.Vector3 _earthInertial = _circularPosition(
    1,
    periodicMotionAngle(seconds, earthYear, 3),
  );

  /// 光源と太陽の見かけの位置で、この同じ方向を共有する。
  late final vm.Vector3 sunDirection = inertialToBody
      .asRotationMatrix()
      .transformed(-_marsInertial)
      .normalized();
  late final vm.Vector3 earthDirection = inertialToBody
      .asRotationMatrix()
      .transformed(_earthInertial - _marsInertial)
      .normalized();

  /// 遠景の描画距離のみを圧縮し、方向と光の整合性を保つ。
  vm.Vector3 get sunOffset => sunDirection * sunDistance;
  vm.Vector3 get earthOffset => earthDirection * earthDistance;

  late final vm.Quaternion earthRotation =
      inertialToBody *
      vm.Quaternion.axisAngle(vm.Vector3(0, 1, .15)..normalize(), earthAngle);
  late final vm.Quaternion sunRotation =
      inertialToBody *
      vm.Quaternion.axisAngle(
        vm.Vector3(0, 1, .08)..normalize(),
        periodicMotionAngle(seconds, sunDay),
      );

  OrbitalPose get satellite => satelliteOrbit.sample(seconds);
  OrbitalPose get rocket => rocketOrbit.sample(seconds);

  OrbitalPose asteroid(int index) {
    RangeError.checkValidIndex(index, asteroidOrbits, 'index');
    return asteroidOrbits[index].sample(seconds);
  }
}

vm.Vector3 _circularPosition(double radius, double angle) =>
    vm.Vector3(radius * math.cos(angle), 0, radius * math.sin(angle));
