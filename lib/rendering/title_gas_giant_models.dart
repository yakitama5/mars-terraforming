import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'title_gas_giant_geometry.dart';
import 'title_planet_geometry.dart';

/// NASA VTAD cloud imagery, oblate globes and Saturn's translucent icy rings.
/// Root +Y is the rotation axis, with equatorial radius 1. Set root transforms
/// before [updateView]; every material instance belongs to this scene alone.
class TitleGasGiantModels {
  TitleGasGiantModels._(
    this._assets,
    this._jupiter,
    this._saturn,
    this._rings,
  ) {
    _bind(_jupiter, 'albedo_map', _assets.textures[0]);
    _bind(_saturn, 'albedo_map', _assets.textures[1]);
    for (final material in [_jupiter, _saturn, _rings]) {
      _bind(material, 'ring_map', _assets.textures[2]);
    }
    _jupiter.parameters.setFloat('polar_ratio', jupiterPolarRatio);
    _saturn.parameters
      ..setFloat('polar_ratio', saturnPolarRatio)
      ..setFloat('rings_enabled', 1);
    _rings.parameters.setFloat('polar_ratio', saturnPolarRatio);
  }

  static const jupiterPolarRatio = 66854 / 71492;
  static const saturnPolarRatio = 54364 / 60268;
  static const _path = 'assets/title/giants';

  final _GasGiantAssets _assets;
  final fs.PreprocessedMaterial _jupiter, _saturn, _rings;
  fs.Node? _jupiterRoot, _saturnRoot;
  int get textureCount => _assets.textures.length;

  static Future<TitleGasGiantModels> load() async {
    final assets = await _GasGiantAssets.load();
    final materials = await Future.wait([
      fs.loadFmatMaterial('$_path/gas_giant_body.fmat'),
      fs.loadFmatMaterial('$_path/gas_giant_body.fmat'),
      fs.loadFmatMaterial('$_path/saturn_rings.fmat'),
    ]);
    return TitleGasGiantModels._(
      assets,
      materials[0],
      materials[1],
      materials[2],
    );
  }

  static void _bind(
    fs.PreprocessedMaterial material,
    String name,
    fs.Texture2D texture,
  ) => material.parameters.setTexture(
    name,
    texture.gpuTexture,
    sampler: texture.sampledSampler,
  );

  fs.Node _body(String name, double polarRatio, fs.Material material) =>
      fs.Node(name: name)..add(
        fs.Node(name: '$name-globe', mesh: fs.Mesh(_assets.globe, material))
          ..scale = vm.Vector3(1, polarRatio, 1),
      );

  fs.Node jupiter() =>
      _jupiterRoot ??= _body('title-jupiter', jupiterPolarRatio, _jupiter);

  fs.Node saturn() {
    final existing = _saturnRoot;
    if (existing != null) return existing;
    final root = _body('title-saturn', saturnPolarRatio, _saturn);
    root.add(
      fs.Node(name: 'title-saturn-rings', mesh: fs.Mesh(_assets.rings, _rings)),
    );
    _saturnRoot = root;
    return root;
  }

  /// Perspective camera/light positions, in the scene's world coordinates.
  /// Analytic self/mutual shadows do not rely on the scene's shadow atlas range.
  void updateView({
    required vm.Vector3 sunPosition,
    required vm.Vector3 cameraPosition,
  }) {
    void update(fs.Node? root, List<fs.PreprocessedMaterial> materials) {
      if (root == null) return;
      // Invert the parent frame, not the flattened globe child. Shadow shaders
      // apply the oblate polar radius once, while the XZ ring remains circular.
      final inverse = vm.Matrix4.inverted(root.globalTransform);
      final sun = inverse.transform3(sunPosition.clone());
      final camera = inverse.transform3(cameraPosition.clone());
      for (final material in materials) {
        material.parameters
          ..setVec3('sun_local', sun)
          ..setVec3('camera_local', camera);
      }
    }

    update(_jupiterRoot, [_jupiter]);
    update(_saturnRoot, [_saturn, _rings]);
  }
}

/// Weak resident reuse and strong ownership by live model instances only.
class _GasGiantAssets {
  _GasGiantAssets(this.textures);

  static WeakReference<_GasGiantAssets>? _cache;
  static Future<_GasGiantAssets>? _inFlight;
  final List<fs.Texture2D> textures;
  late final globe = measuredPlanetMeshData(
    radius: 1,
    rows: 64,
    columns: 128,
  ).geometry();
  late final rings = gasGiantRingMeshData().geometry();

  static Future<_GasGiantAssets> load() async {
    final cached = _cache?.target;
    if (cached != null) return cached;
    final loading = _inFlight;
    if (loading != null) return loading;
    final request = _load();
    _inFlight = request;
    try {
      final assets = await request;
      _cache = WeakReference(assets);
      return assets;
    } finally {
      if (identical(_inFlight, request)) _inFlight = null;
    }
  }

  static Future<_GasGiantAssets> _load() async => _GasGiantAssets(
    await Future.wait([
      fs.Texture2D.fromAsset(
        '${TitleGasGiantModels._path}/jupiter_vtad_2k.jpg',
      ),
      fs.Texture2D.fromAsset('${TitleGasGiantModels._path}/saturn_vtad_2k.jpg'),
      fs.Texture2D.fromAsset(
        '${TitleGasGiantModels._path}/saturn_rings_vtad_2k.png',
        sampling: const fs.TextureSampling(
          addressMode: gpu.SamplerAddressMode.clampToEdge,
        ),
      ),
    ]),
  );
}
