import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

/// A quiet optical point for a planet whose actual globe is not resolved.
///
/// This never resizes or replaces the physical globe/rings. Add [nodes] as
/// scene siblings, outside those models' bounds. The supplied position may be
/// shifted slightly toward the camera to clear the body's own opaque surface;
/// ordinary scene depth still hides the point behind foreground Mars.
class TitleDistantPlanetGlow {
  TitleDistantPlanetGlow._(
    this._geometry,
    this._earthMaterial,
    this._jupiterMaterial,
    this._saturnMaterial,
  );

  static const shaderAsset = 'assets/title/shaders/distant_planet_glow.fmat';

  /// Optical FWHM, in actual SceneView render pixels, independent of DPR.
  static const fullWidthHalfMaximumPixels = 1.0;

  /// The almost invisible tail ends here; this is not a planet's disk radius.
  static const supportRadiusPixels = 2.5;

  static WeakReference<_PointGeometry>? _cachedGeometry;

  final _PointGeometry _geometry;
  final fs.PreprocessedMaterial _earthMaterial;
  final fs.PreprocessedMaterial _jupiterMaterial;
  final fs.PreprocessedMaterial _saturnMaterial;

  late final fs.Node earth = _node('earth', _earthMaterial);
  late final fs.Node jupiter = _node('jupiter', _jupiterMaterial);
  late final fs.Node saturn = _node('saturn', _saturnMaterial);
  late final List<fs.Node> nodes = List.unmodifiable([earth, jupiter, saturn]);

  /// Requires Scene.initializeStaticResources. No textures are loaded.
  /// Materials are independent per body/scene; only immutable buffers are shared.
  static Future<TitleDistantPlanetGlow> load() async {
    final materials = await Future.wait([
      fs.loadFmatMaterial(shaderAsset),
      fs.loadFmatMaterial(shaderAsset),
      fs.loadFmatMaterial(shaderAsset),
    ]);
    final geometry = _cachedGeometry?.target ?? _PointGeometry();
    _cachedGeometry = WeakReference(geometry);
    return TitleDistantPlanetGlow._(
      geometry,
      materials[0],
      materials[1],
      materials[2],
    );
  }

  fs.Node _node(String body, fs.Material material) =>
      fs.Node(name: 'title-$body-glow', mesh: fs.Mesh(_geometry.quad, material))
        ..visible = false;

  /// [brightness] is a normalized artistic flux multiplier (0..1), not a
  /// measured astronomical magnitude. At 1 the shader adds at most 0.32 linear
  /// units over the whole point kernel, before exposure/tone mapping. A fully
  /// centered pixel receives about 58% of that energy.
  ///
  /// The caller derives distance/phase fading without changing the globe's
  /// angular size. [viewportHeightPixels] is the logical viewport height times
  /// the SceneView's actual pixel ratio, not the device's unclamped DPR.
  /// [color] is a linear RGB tint. Omit it for subtle planet-specific whites.
  void updateBody(
    String body, {
    required vm.Vector3 position,
    required vm.Vector3 cameraPosition,
    required vm.Vector3 cameraTarget,
    required double verticalFieldOfViewRadians,
    required double viewportHeightPixels,
    required double brightness,
    vm.Vector3? color,
  }) {
    final (node, material, tint) = switch (body) {
      'earth' => (earth, _earthMaterial, vm.Vector3(.82, .91, 1)),
      'jupiter' => (jupiter, _jupiterMaterial, vm.Vector3(1, .93, .82)),
      'saturn' => (saturn, _saturnMaterial, vm.Vector3(1, .96, .85)),
      _ => throw ArgumentError.value(body, 'body', 'Unknown distant planet'),
    };
    node.visible = false;
    if (!_finite(position) ||
        !_finite(cameraPosition) ||
        !_finite(cameraTarget) ||
        !brightness.isFinite ||
        brightness <= 0 ||
        !viewportHeightPixels.isFinite ||
        viewportHeightPixels <= 0 ||
        !verticalFieldOfViewRadians.isFinite ||
        verticalFieldOfViewRadians <= 0 ||
        verticalFieldOfViewRadians >= math.pi ||
        (color != null && !_finite(color))) {
      return;
    }

    final forward = cameraTarget - cameraPosition;
    if (forward.length2 < 1e-12) return;
    forward.normalize();
    // Match the perspective camera's screen plane, rather than individually
    // aiming at the eye (which would foreshorten an off-axis point kernel).
    final depth = (position - cameraPosition).dot(forward);
    if (!depth.isFinite || depth <= 0) return;
    final unitsPerPixel =
        2 *
        depth *
        math.tan(verticalFieldOfViewRadians / 2) /
        viewportHeightPixels;
    if (!unitsPerPixel.isFinite || unitsPerPixel <= 0) return;
    final referenceUp = forward.y.abs() > .999
        ? vm.Vector3(0, 0, 1)
        : vm.Vector3(0, 1, 0);
    final right = forward.cross(referenceUp)..normalize();
    final up = right.cross(forward)..normalize();
    node
      ..position = position.clone()
      ..rotation = vm.Quaternion.fromRotation(
        vm.Matrix3.columns(right, up, -forward),
      )
      ..scale = vm.Vector3.all(unitsPerPixel * supportRadiusPixels)
      ..visible = true;
    material.parameters
      ..setFloat('strength', brightness.clamp(0.0, 1.0))
      ..setVec3('point_color', color ?? tint);
  }

  static bool _finite(vm.Vector3 v) =>
      v.x.isFinite && v.y.isFinite && v.z.isFinite;
}

class _PointGeometry {
  final quad = fs.MeshGeometry.fromArrays(
    positions: Float32List.fromList([-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0]),
    normals: Float32List.fromList([0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]),
    texCoords: Float32List.fromList([0, 1, 1, 1, 1, 0, 0, 0]),
    indices: Uint16List.fromList([0, 1, 2, 0, 2, 3]),
    retainCpuData: false,
  );
}
