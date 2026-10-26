import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'celestial_sun_models.dart';
import 'title_celestial_models.dart';
import 'title_scene_snapshot.dart';

/// Geographic game globes using the title's observed maps and HDR Sun.
/// Never rotates the ground under city markers, and never loads the ESO sky.
class OrbitalCelestialModels {
  OrbitalCelestialModels._(this._planets, this._sunModels, this._snapshot) {
    earth = _planets.earth()..name = 'map-earth';
    _mars = _makeMars();
    sun = _sunModels.sun()..name = 'map-sun';
  }

  final TitleCelestialModels _planets;
  final CelestialSunModels _sunModels;
  TitleSceneSnapshot _snapshot;
  late TitleMarsModel _mars;
  late final fs.Node earth, sun;

  fs.Node get mars => _mars.root;

  static Future<OrbitalCelestialModels> load({
    TitleSceneSnapshot marsSnapshot = TitleSceneSnapshot.pristine,
  }) async {
    final resources = await Future.wait<Object>([
      TitleCelestialModels.load(),
      CelestialSunModels.load(),
    ]);
    return OrbitalCelestialModels._(
      resources[0] as TitleCelestialModels,
      resources[1] as CelestialSunModels,
      marsSnapshot,
    );
  }

  TitleMarsModel _makeMars() {
    final model = _planets.mars(_snapshot, titleOrientation: false);
    model.root.name = 'map-mars';
    // The game already places its actual cities at saved lat/lon. The title's
    // artistic settlement lights would imply extra cities in another region.
    model.settlements.visible = false;
    return model;
  }

  /// Only progress changes replace nodes; textures and terrain buffers persist.
  bool updateMars(TitleSceneSnapshot snapshot) {
    if (_snapshot.hasSameModel(snapshot)) return false;
    _snapshot = snapshot;
    _mars = _makeMars();
    return true;
  }

  double marsSurfaceRadius(double latitude, double longitude) =>
      _planets.marsSurfaceRadius(latitude, longitude);

  void updateView({
    required vm.Vector3 cameraPosition,
    required vm.Vector3 sunPosition,
    required double seconds,
  }) {
    _planets.updateView(
      cameraPosition: cameraPosition,
      sunDirection: sunPosition.normalized(),
      sunPosition: sunPosition,
      seconds: seconds,
    );
    _sunModels.update(seconds);
  }
}
