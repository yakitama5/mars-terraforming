import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/rendering/title_scene_motion.dart';

void main() {
  test('周回する宇宙と間隔を空けた飛来を単調時刻から再現する', () {
    final initial = TitleSceneMotion(0), later = TitleSceneMotion(10);
    expect(initial.rocket, isNull);
    expect(later.rocket, closeTo(6 / 14, 1e-10));
    expect(later.starAngle, greaterThan(initial.starAngle));
    expect(later.satelliteAngle, greaterThan(initial.satelliteAngle));
    expect(TitleSceneMotion(20).rocket, isNull);
    expect(TitleSceneMotion(51).rocket, 0);
    expect(TitleSceneMotion(12).asteroid(0), isNull);
    expect(TitleSceneMotion(17).asteroid(0), .5);
    expect(TitleSceneMotion(21).asteroid(0), isNull);
  });

  test('長時間と異常時刻でも描画値が有限でイベントを複製しない', () {
    for (final value in [double.nan, double.infinity, -100.0, 1e12]) {
      final motion = TitleSceneMotion(value);
      expect(motion.starAngle.isFinite, isTrue);
      expect(motion.rocket, anyOf(isNull, inInclusiveRange(0, 1)));
      expect(motion.asteroid(1), anyOf(isNull, inInclusiveRange(0, 1)));
    }
  });
}
