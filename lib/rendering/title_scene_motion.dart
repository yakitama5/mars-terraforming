import 'dart:math' as math;

/// 表示用の単調時刻だけを使う。端末時計やゲームの時刻には触れない。
class TitleSceneMotion {
  TitleSceneMotion(double seconds)
    : seconds = seconds.isFinite ? math.max(0, seconds) : 0;

  final double seconds;

  double get starAngle => seconds * .0008;
  double get earthAngle => seconds * .025;
  double get cloudAngle => seconds * .003;
  double get satelliteAngle => seconds * .085 + .35;

  /// 周回の一部だけ画面を通過し、登場しない時間を長く残す。
  double? passage({
    required double period,
    required double duration,
    double delay = 0,
  }) {
    if (seconds < delay) return null;
    final phase = (seconds - delay) % period;
    return phase < duration ? phase / duration : null;
  }

  double? get rocket => passage(period: 47, duration: 14, delay: 4);
  double? asteroid(int index) => passage(
    period: 61 + index * 17,
    duration: 8 + index * 2,
    delay: 13 + index * 23,
  );
}
