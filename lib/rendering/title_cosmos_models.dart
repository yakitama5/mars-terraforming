import 'dart:typed_data';

import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

/// A photographic stellar panorama at infinity, independent of object lighting.
/// The Sun remains a three-dimensional emissive sphere and an additive corona.
class TitleCosmosModels {
  TitleCosmosModels._(
    this.environment,
    this.skySource,
    this._photosphere,
    this._corona,
    this.starTexture,
    this.skySampler,
  );

  static const starMapAsset = 'assets/title/cosmos/eso0932a_milky_way.jpg';
  static const skyShaderAsset = 'assets/title/shaders/cosmos_sky.fmat';
  static const sunShaderAsset = 'assets/title/shaders/cosmos_sun.fmat';
  static const coronaShaderAsset = 'assets/title/shaders/cosmos_corona.fmat';

  /// Quiet ambient illumination, independent from the photographed sky.
  final fs.EnvironmentMap environment;
  final fs.PreprocessedSky skySource;
  final fs.PreprocessedMaterial _photosphere, _corona;
  final fs.Texture2D starTexture;
  final gpu.SamplerOptions skySampler;

  /// Art-direction offsets in radians. Keep Scene.environmentTransform at
  /// identity when the background should be driven only by these uniforms.
  double skyYawOffset = -1.15;
  double skyTilt = -.55;

  fs.Skybox get skybox => fs.Skybox(skySource);

  /// Call after Scene.initializeStaticResources. Asset loading is entirely local.
  static Future<TitleCosmosModels> load() async {
    final sky = await fs.loadFmatSky(skyShaderAsset);
    final photosphere = await fs.loadFmatMaterial(sunShaderAsset);
    final corona = await fs.loadFmatMaterial(coronaShaderAsset);
    // EnvironmentMap's retained background is mipless. A Texture2D builds a
    // colour-correct mip chain and prevents shimmering or enlarged pixel blocks.
    final stars = await fs.Texture2D.fromAsset(
      starMapAsset,
      // Native image upload does not clamp to device limits. Keep the detailed
      // panorama within the 4096px limit supported by older mobile GPUs too.
      maxSize: 4096,
      sampling: const fs.TextureSampling(),
    );
    final mipped = stars.gpuTexture.mipLevelCount > 1;
    final sampler = gpu.SamplerOptions(
      minFilter: gpu.MinMagFilter.linear,
      magFilter: gpu.MinMagFilter.linear,
      mipFilter: mipped ? gpu.MipFilter.linear : gpu.MipFilter.nearest,
      widthAddressMode: gpu.SamplerAddressMode.repeat,
      heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      maxAnisotropy: mipped ? 8 : 1,
    );
    sky.parameters.setTexture('star_map', stars.gpuTexture, sampler: sampler);
    final environment = fs.EnvironmentMap.constantDiffuse(
      vm.Vector3(.1, .12, .16),
    );
    return TitleCosmosModels._(
      environment,
      sky,
      photosphere,
      corona,
      stars,
      sampler,
    );
  }

  /// Local +Z faces the viewer. Rotate the root toward the fixed title camera;
  /// its central sphere provides an actual curved limb and depth occlusion.
  fs.Node sun({double radius = 1}) {
    final root = fs.Node(name: 'HDRの太陽・光球と希薄なコロナ')
      ..scale = vm.Vector3.all(radius);
    root.add(
      fs.Node(
        name: '白熱した太陽光球',
        mesh: fs.Mesh(
          fs.SphereGeometry(radius: 1, segments: 80, rings: 40),
          _photosphere,
        ),
      ),
    );
    root.add(
      fs.Node(
        name: '加算光のコロナ・ストリーマー・微細な回折光',
        mesh: fs.Mesh(_coronaPlane(), _corona),
      ),
    );
    return root;
  }

  /// Solar detail and the distant sky use the display's monotonic time.
  /// Camera translation never introduces parallax into the stellar background.
  void update(double seconds) {
    final time = seconds.isFinite && seconds > 0 ? seconds : 0.0;
    _photosphere.parameters.setFloat('time', time);
    _corona.parameters.setFloat('time', time);
    skySource.parameters
      ..setFloat('sky_yaw', skyYawOffset + time * .0008)
      ..setFloat('sky_tilt', skyTilt);
  }

  static fs.MeshGeometry _coronaPlane() => fs.MeshGeometry.fromArrays(
    positions: Float32List.fromList([-6, -6, 0, 6, -6, 0, 6, 6, 0, -6, 6, 0]),
    normals: Float32List.fromList([0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]),
    texCoords: Float32List.fromList([0, 1, 1, 1, 1, 0, 0, 0]),
    indices: Uint16List.fromList([0, 1, 2, 0, 2, 3]),
    retainCpuData: false,
  );
}
