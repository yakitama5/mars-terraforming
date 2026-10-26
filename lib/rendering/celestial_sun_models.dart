import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

/// The title's HDR Sun without its photographic, memory-intensive sky.
/// Materials belong to one scene; only immutable mesh buffers are shared.
class CelestialSunModels {
  CelestialSunModels._(this._geometry, this._photosphere, this._corona);

  static const photosphereShaderAsset = 'assets/title/shaders/cosmos_sun.fmat';
  static const coronaShaderAsset = 'assets/title/shaders/cosmos_corona.fmat';
  static WeakReference<_SunGeometry>? _cachedGeometry;

  final _SunGeometry _geometry;
  final fs.PreprocessedMaterial _photosphere, _corona;

  /// Requires Scene.initializeStaticResources; loads no star map or cubemap.
  static Future<CelestialSunModels> load() async {
    final materials = await Future.wait([
      fs.loadFmatMaterial(photosphereShaderAsset),
      fs.loadFmatMaterial(coronaShaderAsset),
    ]);
    final geometry = _cachedGeometry?.target ?? _SunGeometry();
    _cachedGeometry = WeakReference(geometry);
    return CelestialSunModels._(geometry, materials[0], materials[1]);
  }

  /// Local +Z faces the viewer; orient the root toward its scene's camera.
  fs.Node sun({double radius = 1}) {
    final root = fs.Node(name: 'HDRの太陽・光球と希薄なコロナ')
      ..scale = vm.Vector3.all(radius);
    root.add(
      fs.Node(
        name: '白熱した太陽光球',
        mesh: fs.Mesh(_geometry.photosphere, _photosphere),
      ),
    );
    root.add(
      fs.Node(
        name: '加算光のコロナ・ストリーマー・微細な回折光',
        mesh: fs.Mesh(_geometry.corona, _corona),
      ),
    );
    return root;
  }

  void update(double seconds) {
    final time = seconds.isFinite && seconds > 0 ? seconds : 0.0;
    _photosphere.parameters.setFloat('time', time);
    _corona.parameters.setFloat('time', time);
  }
}

class _SunGeometry {
  final photosphere = fs.SphereGeometry(radius: 1, segments: 80, rings: 40);
  final corona = fs.MeshGeometry.fromArrays(
    positions: Float32List.fromList([-6, -6, 0, 6, -6, 0, 6, 6, 0, -6, 6, 0]),
    normals: Float32List.fromList([0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]),
    texCoords: Float32List.fromList([0, 1, 1, 1, 1, 0, 0, 0]),
    indices: Uint16List.fromList([0, 1, 2, 0, 2, 3]),
    retainCpuData: false,
  );
}
