import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

/// 遠景のサイズ計算用の単位。ゲーム進行・主火星・全球表示には適用しない。
abstract final class TitleSolarSystemScale {
  /// IAU 2012の正確な定義をkmへ変換した値。
  /// https://ssd.jpl.nasa.gov/astro_par.html
  static const kilometersPerAu = 149597870.7;
}

/// タイトルの太陽中心座標と見かけの赤道半径の基準。
///
/// 惑星半径はJPL Physical Parameters、半長径はApproximate Positionsの
/// Table 1/J2000の値。Earthの軌道半長径はEarth/Moon barycenterの近似。
/// ここでは円軌道の長さの基準にだけ使い、実暦の位置を再現するものではない。
/// https://ssd.jpl.nasa.gov/planets/phys_par.html
/// https://ssd.jpl.nasa.gov/planets/approx_pos.html
/// 太陽はIAU 2015 B3の公称光球半径695700kmを用いる。
/// https://www.iau.org/common/Uploaded%20files/IAUGA2015-Resolution-B3-recommended-nominal-conversion.pdf
enum TitleDistantBody {
  sun(equatorialRadiusKm: 695700, semiMajorAxisAu: 0),
  earth(equatorialRadiusKm: 6378.1366, semiMajorAxisAu: 1.00000261),
  mars(equatorialRadiusKm: 3396.19, semiMajorAxisAu: 1.52371034),
  jupiter(equatorialRadiusKm: 71492, semiMajorAxisAu: 5.20288700),
  saturn(equatorialRadiusKm: 60268, semiMajorAxisAu: 9.53667594);

  const TitleDistantBody({
    required this.equatorialRadiusKm,
    required this.semiMajorAxisAu,
  });

  /// 太陽だけは公称光球半径。惑星の環やコロナの外縁は含まない。
  final double equatorialRadiusKm;
  final double semiMajorAxisAu;
}

/// 観測者からの実AU相対ベクトルと球の半径から、見かけの角半径を得る。
///
/// 相対ベクトルは呼出側で描画のカメラ座標系へ回転済みとする。
/// 観測者が球の外にいるときの輪郭はtheta=asin(radius/distance)。
/// 空間の描画距離を圧縮しても、球の見かけの角度と天体間の比率を保つ。
class ApparentBody {
  factory ApparentBody({
    required double radiusKm,
    required vm.Vector3 relativeAu,
  }) {
    _requirePositiveFinite(radiusKm, 'radiusKm');
    _requireFiniteVector(relativeAu, 'relativeAu');
    final distanceAu = relativeAu.length;
    _requirePositiveFinite(distanceAu, 'relativeAu.length');
    final radiusRatio =
        (radiusKm / TitleSolarSystemScale.kilometersPerAu) / distanceAu;
    if (!radiusRatio.isFinite || radiusRatio <= 0 || radiusRatio >= 1) {
      throw ArgumentError('観測者は半径より遠い有限の位置に置いてください');
    }
    return ApparentBody._(
      radiusKm,
      relativeAu.clone(),
      distanceAu,
      math.asin(radiusRatio),
    );
  }

  ApparentBody._(
    this.radiusKm,
    this._relativeAu,
    this.distanceAu,
    this.angularRadius,
  );

  final double radiusKm;
  final vm.Vector3 _relativeAu;
  final double distanceAu;

  /// 倍率を掛ける前の実角半径、単位rad。光のにじみや最低pixel数は含めない。
  final double angularRadius;

  vm.Vector3 get relativeAu => _relativeAu.clone();
  vm.Vector3 get direction => _relativeAu / distanceAu;

  /// カメラから球中心までの[renderDistance]で、指定の角半径を再現する球の半径。
  ///
  /// magnificationは角半径の共通倍率。太陽へは呼出側で常に1を使う。
  /// 球の輪郭を使うのでtanではなくsinで戻す。環はこの球と同じroot scaleを
  /// 使用し、元モデルの環/本体の比率と相互の遮蔽を保つ。
  double renderedSphereRadius(
    double renderDistance, {
    double magnification = 1,
  }) {
    _requirePositiveFinite(renderDistance, 'renderDistance');
    _requirePositiveFinite(magnification, 'magnification');
    final angle = angularRadius * magnification;
    if (!angle.isFinite || angle >= math.pi / 2) {
      throw ArgumentError.value(
        magnification,
        'magnification',
        '拡大後の角半径はpi/2未満にしてください',
      );
    }
    final radius = renderDistance * math.sin(angle);
    _requirePositiveFinite(radius, 'renderedSphereRadius');
    return radius;
  }

  /// 元の球半径が[modelRadius]のモデルrootへ適用する一様scale。
  double modelScale({
    required double renderDistance,
    double modelRadius = 1,
    double magnification = 1,
  }) {
    _requirePositiveFinite(modelRadius, 'modelRadius');
    final scale =
        renderedSphereRadius(renderDistance, magnification: magnification) /
        modelRadius;
    if (!scale.isFinite || scale <= 0) {
      throw ArgumentError('modelRadiusと描画距離から有限の正のscaleを作れません');
    }
    return scale;
  }

  /// P=camera+D*direction。火星中心へ足すことによる偽の視差を作らない。
  vm.Vector3 cameraAnchoredPosition(
    vm.Vector3 cameraPosition,
    double renderDistance,
  ) {
    _requireFiniteVector(cameraPosition, 'cameraPosition');
    _requirePositiveFinite(renderDistance, 'renderDistance');
    final position = cameraPosition + direction * renderDistance;
    _requireFiniteVector(position, 'renderedPosition');
    return position;
  }
}

void _requirePositiveFinite(double value, String name) {
  if (!value.isFinite || value <= 0) {
    throw ArgumentError.value(value, name, '正の有限値が必要です');
  }
}

void _requireFiniteVector(vm.Vector3 value, String name) {
  if (!value.x.isFinite || !value.y.isFinite || !value.z.isFinite) {
    throw ArgumentError.value(value, name, '全成分が有限値のベクトルが必要です');
  }
}
