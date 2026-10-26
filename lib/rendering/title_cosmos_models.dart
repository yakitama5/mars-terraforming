import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'celestial_sun_models.dart';

/// A photographic stellar panorama at infinity, independent of object lighting.
/// The Sun remains a three-dimensional emissive sphere and an additive corona.
class TitleCosmosModels {
  TitleCosmosModels._(
    this.environment,
    this.skySource,
    this._sunModels,
    this.starTexture,
    this.skySampler,
  );

  static const starMapAsset = 'assets/title/cosmos/eso0932a_milky_way.jpg';
  static const skyShaderAsset = 'assets/title/shaders/cosmos_sky.fmat';
  static const sunShaderAsset = CelestialSunModels.photosphereShaderAsset;
  static const coronaShaderAsset = CelestialSunModels.coronaShaderAsset;

  /// Quiet ambient illumination, independent from the photographed sky.
  final fs.EnvironmentMap environment;
  final fs.PreprocessedSky skySource;
  final CelestialSunModels _sunModels;
  final fs.Texture2D starTexture;
  final gpu.SamplerOptions skySampler;

  /// Art-direction offsets in radians. Keep Scene.environmentTransform at
  /// identity when the background should be driven only by these uniforms.
  double skyYawOffset = -1.15;
  double skyTilt = -.55;

  fs.Skybox get skybox => fs.Skybox(skySource);

  /// Call after Scene.initializeStaticResources. Asset loading is entirely local.
  static Future<TitleCosmosModels> load() async {
    // EnvironmentMap's retained background is mipless. A Texture2D builds a
    // colour-correct mip chain and prevents shimmering or enlarged pixel blocks.
    final resources = await Future.wait<Object>([
      fs.loadFmatSky(skyShaderAsset),
      CelestialSunModels.load(),
      fs.Texture2D.fromAsset(
        starMapAsset,
        // Native image upload does not clamp to device limits. Keep the detailed
        // panorama within the 4096px limit supported by older mobile GPUs too.
        maxSize: 4096,
        sampling: const fs.TextureSampling(),
      ),
    ]);
    final sky = resources[0] as fs.PreprocessedSky;
    final sun = resources[1] as CelestialSunModels;
    final stars = resources[2] as fs.Texture2D;
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
    return TitleCosmosModels._(environment, sky, sun, stars, sampler);
  }

  /// Local +Z faces the viewer. Rotate the root toward the fixed title camera;
  /// its central sphere provides an actual curved limb and depth occlusion.
  fs.Node sun({double radius = 1}) => _sunModels.sun(radius: radius);

  /// Solar detail and the distant sky use the display's monotonic time.
  /// Camera translation never introduces parallax into the stellar background.
  void update(double seconds, {double? skyYaw, double bodyTilt = 0}) {
    final time = seconds.isFinite && seconds > 0 ? seconds : 0.0;
    _sunModels.update(time);
    skySource.parameters
      ..setFloat('sky_yaw', skyYawOffset + (skyYaw ?? time * .0008))
      ..setFloat('body_tilt', bodyTilt)
      ..setFloat('sky_tilt', skyTilt);
  }
}
