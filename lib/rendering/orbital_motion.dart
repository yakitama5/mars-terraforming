import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

const _tau = math.pi * 2;

/// 描画用の単調時刻。保存時刻や端末時計を参照しない。
double safeMotionSeconds(double seconds) =>
    seconds.isFinite && seconds > 0 ? seconds : 0;

/// 乗算前に剰余を取り、非常に長い稼働時間でも有限の角度を返す。
double periodicMotionAngle(double seconds, double period, [double phase = 0]) {
  if (!period.isFinite || period <= 0 || !phase.isFinite) {
    throw ArgumentError(
      'A finite positive period and finite phase are required.',
    );
  }
  return ((safeMotionSeconds(seconds) % period) / period * _tau +
          phase % _tau) %
      _tau;
}

/// 火星中心を原点とした描画位置と解析的な速度。
///
/// [orientation] はモデルの +Y を進行方向、+Z を軌道面の法線へ向ける。
/// モデル固有の軸補正は、この姿勢の子ノードで適用する。
class OrbitalPose {
  const OrbitalPose({
    required this.position,
    required this.velocity,
    required this.orientation,
    required this.orbitNormal,
  });

  final vm.Vector3 position;
  final vm.Vector3 velocity;
  final vm.Quaternion orientation;
  final vm.Vector3 orbitNormal;
}

/// タイトルの見かけの楕円軌道。期間・距離は美術用で、実天体の軌道要素ではない。
///
/// 火星を楕円の焦点に置き、平均近点角を一定速度で進める。位置と速度は
/// 同じ離心近点角から求めるため、継ぎ目や近点でも姿勢が移動に追従する。
class KeplerOrbit {
  KeplerOrbit({
    required this.semiMajorAxis,
    required this.eccentricity,
    required this.period,
    this.inclination = 0,
    this.ascendingNode = 0,
    this.argumentOfPeriapsis = 0,
    this.meanAnomalyAtEpoch = 0,
  }) {
    if (!semiMajorAxis.isFinite ||
        semiMajorAxis <= 0 ||
        !eccentricity.isFinite ||
        eccentricity < 0 ||
        eccentricity >= 1 ||
        !period.isFinite ||
        period <= 0 ||
        !inclination.isFinite ||
        !ascendingNode.isFinite ||
        !argumentOfPeriapsis.isFinite ||
        !meanAnomalyAtEpoch.isFinite) {
      throw ArgumentError(
        'Elliptical orbit elements must be finite and valid.',
      );
    }
  }

  final double semiMajorAxis;
  final double eccentricity;
  final double period;
  final double inclination;
  final double ascendingNode;
  final double argumentOfPeriapsis;
  final double meanAnomalyAtEpoch;

  double get periapsis => semiMajorAxis * (1 - eccentricity);
  double get apoapsis => semiMajorAxis * (1 + eccentricity);

  late final vm.Matrix3 _planeRotation =
      (vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), ascendingNode) *
              vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), inclination) *
              vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), argumentOfPeriapsis))
          .asRotationMatrix();

  OrbitalPose sample(double seconds) {
    final meanAnomaly = periodicMotionAngle(
      seconds,
      period,
      meanAnomalyAtEpoch,
    );
    final eccentricAnomaly = _solveEccentricAnomaly(meanAnomaly, eccentricity);
    final cosine = math.cos(eccentricAnomaly);
    final sine = math.sin(eccentricAnomaly);
    final minorRatio = math.sqrt(1 - eccentricity * eccentricity);
    final angularVelocity = (_tau / period) / (1 - eccentricity * cosine);
    final position = _planeRotation.transformed(
      vm.Vector3(
        semiMajorAxis * (cosine - eccentricity),
        0,
        semiMajorAxis * minorRatio * sine,
      ),
    );
    final velocity = _planeRotation.transformed(
      vm.Vector3(
        -semiMajorAxis * sine * angularVelocity,
        0,
        semiMajorAxis * minorRatio * cosine * angularVelocity,
      ),
    );
    // XZ の正方向の公転は -Y 法線。右手系の姿勢を接線から構成する。
    final normal = _planeRotation.transformed(vm.Vector3(0, -1, 0));
    final forward = velocity.normalized();
    final right = forward.cross(normal).normalized();
    final up = right.cross(forward).normalized();
    return OrbitalPose(
      position: position,
      velocity: velocity,
      orientation: vm.Quaternion.fromRotation(
        vm.Matrix3.columns(right, forward, up),
      )..normalize(),
      orbitNormal: normal,
    );
  }
}

double _solveEccentricAnomaly(double mean, double eccentricity) {
  if (mean == 0 || eccentricity == 0) return mean;
  var lower = 0.0;
  var upper = _tau;
  var estimate = eccentricity < .8 ? mean : math.pi;
  // Newton 法を区間内に制限し、非常に細長い楕円でも収束を保証する。
  for (var i = 0; i < 48; i++) {
    final residual = estimate - eccentricity * math.sin(estimate) - mean;
    if (residual.abs() < 1e-13) break;
    if (residual < 0) {
      lower = estimate;
    } else {
      upper = estimate;
    }
    final candidate =
        estimate - residual / (1 - eccentricity * math.cos(estimate));
    estimate = candidate > lower && candidate < upper
        ? candidate
        : (lower + upper) / 2;
  }
  return estimate;
}
