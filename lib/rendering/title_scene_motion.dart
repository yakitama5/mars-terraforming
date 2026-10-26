import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import 'orbital_motion.dart';

export 'orbital_motion.dart' show KeplerOrbit, OrbitalPose;

/// 表示用の単調時刻だけを使う。端末時計やゲームの時刻には触れない。
///
/// 太陽中心の共通慣性系から、火星の周囲をゆっくり巡るカメラ座標へ変換する。
/// 火星の地表の自転はカメラの周回と分ける。周期・初期位相・傾斜はタイトルの
/// 構図のために圧縮した美術仕様であり、実暦ではない。
class TitleSceneMotion {
  TitleSceneMotion(double seconds) : seconds = safeMotionSeconds(seconds);

  final double seconds;

  static const marsDay = 180.0;
  static const cameraOrbitFraction = .25;
  static const cameraOrbitPeriod = marsDay / cameraOrbitFraction;
  // カメラ周回と公転の同期で太陽が固定されないよう、公転は十分遅くする。
  static const marsYear = 7200.0;
  static const earthYear = 4500.0;
  static const jupiterYear = 36000.0;
  static const saturnYear = 72000.0;
  static const earthDay = 55.0;
  static const sunDay = 112.0;
  static const jupiterDay = 72.0;
  static const saturnDay = 80.0;
  static const sunDistance = 120.0;
  static const earthDistance = 110.0;
  static const jupiterDistance = 140.0;
  static const saturnDistance = 155.0;
  static const cameraFrameTilt = .30;
  static const jupiterAxialTilt = 3.13 * math.pi / 180;
  static const saturnAxialTilt = 26.7 * math.pi / 180;
  // 最初は横から光を受ける火星と巨惑星。地球、次に太陽が地平線へ巡る。
  static const cameraOrbitAtEpoch = 4.68;
  static const marsOrbitAtEpoch = math.pi / 2;
  static const earthOrbitAtEpoch = .7;
  static const jupiterOrbitAtEpoch = 341 * math.pi / 180;
  static const saturnOrbitAtEpoch = 350 * math.pi / 180;

  /// 火星中心・カメラ座標の見かけの近傍軌道。軌道面の法線を視線へ寄せ、地平線の
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

  double get marsSpin => periodicMotionAngle(seconds, marsDay);
  double get cameraOrbit =>
      periodicMotionAngle(seconds, cameraOrbitPeriod, cameraOrbitAtEpoch);

  /// 空の sampling は視線をカメラ系から慣性系へ戻すので + カメラ周回角。
  /// 傾斜を含めた完全な変換には [cameraToInertial] を使う。
  double get starAngle => cameraOrbit;
  double get earthAngle => periodicMotionAngle(seconds, earthDay, -2.1);
  double get cloudAngle => periodicMotionAngle(seconds, math.pi * 2 / .003);

  late final vm.Quaternion inertialToCamera =
      vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -cameraOrbit) *
      vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), cameraFrameTilt);
  late final vm.Quaternion cameraToInertial = inertialToCamera.conjugated();

  /// 地表・施設・雲・大気の共通rootへ適用する姿勢。
  ///
  /// 初期の撮影姿勢はそのままに、モデルの地理上の +Y 軸で自転する。
  /// 撮影姿勢と自転軸は可換でないので、単に画面のY軸だけでは回さない。
  vm.Quaternion marsRotation(vm.Quaternion initialOrientation) =>
      vm.Quaternion.axisAngle(
        vm.Vector3(0, 1, 0),
        -periodicMotionAngle(seconds, cameraOrbitPeriod),
      ) *
      initialOrientation *
      vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), marsSpin);

  late final vm.Vector3 _marsInertial = _circularPosition(
    1.52,
    periodicMotionAngle(seconds, marsYear, marsOrbitAtEpoch),
  );
  late final vm.Vector3 _earthInertial = _circularPosition(
    1,
    periodicMotionAngle(seconds, earthYear, earthOrbitAtEpoch),
  );
  late final vm.Vector3 _jupiterInertial = _circularPosition(
    5.2,
    periodicMotionAngle(seconds, jupiterYear, jupiterOrbitAtEpoch),
  );
  late final vm.Vector3 _saturnInertial = _circularPosition(
    9.58,
    periodicMotionAngle(seconds, saturnYear, saturnOrbitAtEpoch),
  );

  /// 光源と太陽の見かけの位置で、この同じ方向を共有する。
  late final vm.Vector3 sunDirection = inertialToCamera
      .asRotationMatrix()
      .transformed(-_marsInertial)
      .normalized();
  late final vm.Vector3 earthDirection = inertialToCamera
      .asRotationMatrix()
      .transformed(_earthInertial - _marsInertial)
      .normalized();
  late final vm.Vector3 jupiterDirection = inertialToCamera
      .asRotationMatrix()
      .transformed(_jupiterInertial - _marsInertial)
      .normalized();
  late final vm.Vector3 saturnDirection = inertialToCamera
      .asRotationMatrix()
      .transformed(_saturnInertial - _marsInertial)
      .normalized();

  /// 遠景の描画距離のみを圧縮し、方向と光の整合性を保つ。
  vm.Vector3 get sunOffset => sunDirection * sunDistance;
  vm.Vector3 get earthOffset => earthDirection * earthDistance;
  vm.Vector3 get jupiterOffset => jupiterDirection * jupiterDistance;
  vm.Vector3 get saturnOffset => saturnDirection * saturnDistance;

  late final vm.Quaternion earthRotation =
      inertialToCamera *
      vm.Quaternion.axisAngle(vm.Vector3(0, 1, .15)..normalize(), earthAngle);
  late final vm.Quaternion sunRotation =
      inertialToCamera *
      vm.Quaternion.axisAngle(
        vm.Vector3(0, 1, .08)..normalize(),
        periodicMotionAngle(seconds, sunDay),
      );
  late final vm.Quaternion jupiterRotation =
      inertialToCamera *
      vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), jupiterAxialTilt) *
      vm.Quaternion.axisAngle(
        vm.Vector3(0, 1, 0),
        periodicMotionAngle(seconds, jupiterDay),
      );
  late final vm.Quaternion saturnRotation =
      inertialToCamera *
      vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), saturnAxialTilt) *
      vm.Quaternion.axisAngle(
        vm.Vector3(0, 1, 0),
        periodicMotionAngle(seconds, saturnDay),
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
