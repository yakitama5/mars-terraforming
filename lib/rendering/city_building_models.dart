part of 'city_models.dart';

/// Twelve authored silhouettes. Identity, work and operating state are supplied
/// by the snapshot; model selection never inspects research or save state.
extension _CityBuildingModels on CityModels {
  void _researchBuilding(
    fs.Node root,
    CityTerrain terrain,
    int plotIndex,
    SceneBuilding building, {
    vm.Vector3? centerOverride,
    double? scaleOverride,
  }) {
    final center =
        centerOverride ??
        terrain.buildingCenter(
          plotIndex,
          building.slotIndex,
          occupiesWholePlot: building.occupiesWholePlot,
        );
    final modelScale =
        scaleOverride ?? (building.occupiesWholePlot ? .90 : .48);
    final node = fs.Node(name: building.name)
      ..position = center
      ..scale = vm.Vector3.all(modelScale);
    root.add(node);
    final mesh = _CityMesh();
    if (building.workState == SceneWorkState.queued) {
      _buildingReservation(mesh);
      mesh.attach(node, '予約された施設の用地');
      return;
    }
    if (building.workState == SceneWorkState.building) {
      _buildingConstruction(mesh, building.constructionStage);
      mesh.attach(node, '施設の工事現場');
      return;
    }
    final vehicleSite = ['M25', 'M13'].contains(building.catalogId);
    if (vehicleSite) {
      // Large hangars and their exposed aprons extend beyond the city's small
      // flat center. Clear the complete footprint, including a crater rim.
      final foundation = _vehicleFoundationCenter(terrain, center, modelScale);
      node.position = foundation;
      _vehicleFoundationColumns(mesh, terrain, foundation, modelScale);
    }
    final active = building.operational;
    final accent = active ? const Color(0xff69c4bb) : const Color(0xff78878a);
    mesh.box(
      vm.Vector3(0, -.005, 0),
      vm.Vector3(1.35, .09, 1.32),
      terrain.moon ? const Color(0xff7d828b) : CityModels.paving,
    );
    switch (building.catalogId) {
      case 'base_lab':
        _unit(mesh, -.17, -.10, .82, .67, .38, roof: accent);
        _unit(mesh, .37, .20, .32, .34, .27);
        mesh.box(
          vm.Vector3(-.17, .43, -.10),
          vm.Vector3(.46, .075, .32),
          CityModels.windows,
        );
        break;
      case 'B01':
        _hydroponicBuilding(node, mesh, active);
        break;
      case 'B13':
        _foodBuilding(mesh, accent);
        break;
      case 'R01':
        _analysisBuilding(node, mesh, accent);
        break;
      case 'R05':
        _iceBuilding(mesh, accent);
        break;
      case 'R07':
        _waterBuilding(node, mesh, accent);
        break;
      case 'R15':
        _printingBuilding(mesh, accent);
        break;
      case 'E09':
        _batteryBuilding(mesh, accent);
        break;
      case 'E10':
        _electrolysisBuilding(node, mesh, accent);
        break;
      case 'E13':
        _distributionBuilding(mesh, accent);
        break;
      case 'M08':
        _maintenanceBuilding(mesh, accent);
        break;
      case 'M25':
        _reusableBuilding(node, mesh, accent, building.vehiclePresent);
        break;
      case 'M13':
        _shuttleBuilding(node, mesh, accent, building.vehiclePresent);
        break;
    }
    // A small service lamp and real loading crates show work without endless
    // particles or idle animations. Suspension keeps the installed silhouette.
    final serviceLampX = vehicleSite ? -.60 : .55;
    mesh.box(
      vm.Vector3(serviceLampX, .19, .53),
      vm.Vector3(.035, .38, .035),
      CityModels.steel,
    );
    mesh.box(
      vm.Vector3(serviceLampX, .40, .53),
      vm.Vector3(.10, .055, .075),
      accent,
    );
    for (var i = 0; i < (active ? 3 : 1); i++) {
      mesh.box(
        vm.Vector3(-.46 + i * .19, .09, .53),
        vm.Vector3(.14, .16, .13),
        active ? CityModels.orange : CityModels.steel,
      );
    }
    mesh.attach(node, active ? '稼働中の施設と搬出入ヤード' : '休止中の施設');
  }

  vm.Vector3 _vehicleFoundationCenter(
    CityTerrain terrain,
    vm.Vector3 center,
    double scale,
  ) {
    var highest = center.y - .035;
    // Bounds include the M13 landing legs and M25 recovery cradle. Sampling
    // at about .1 world units resolves the narrow authored crater rim.
    for (var x = 0; x <= 12; x++) {
      for (var z = 0; z <= 12; z++) {
        highest = math.max(
          highest,
          terrain.height(
            center.x + (-.70 + 1.52 * x / 12) * scale,
            center.z + (-.67 + 1.47 * z / 12) * scale,
          ),
        );
      }
    }
    return vm.Vector3(center.x, highest + .035, center.z);
  }

  void _vehicleFoundationColumns(
    _CityMesh mesh,
    CityTerrain terrain,
    vm.Vector3 center,
    double scale,
  ) {
    const slabBottom = -.05;
    for (final x in [-.60, .60]) {
      for (final z in [-.56, .56]) {
        final ground =
            (terrain.height(center.x + x * scale, center.z + z * scale) -
                center.y) /
            scale;
        final height = slabBottom - ground;
        if (height <= .04) continue;
        mesh.box(
          vm.Vector3(x, ground + height / 2, z),
          vm.Vector3(.13, height, .13),
          CityModels.steel,
        );
      }
    }
  }

  void _buildingReservation(_CityMesh mesh) {
    for (final x in [-.59, .59]) {
      for (final z in [-.54, .54]) {
        mesh.box(
          vm.Vector3(x, .14, z),
          vm.Vector3(.045, .28, .045),
          CityModels.orange,
        );
        mesh.box(
          vm.Vector3(x + .07, .23, z),
          vm.Vector3(.15, .07, .02),
          CityModels.orange,
        );
      }
    }
  }

  void _buildingConstruction(_CityMesh mesh, int stage) {
    _buildingReservation(mesh);
    mesh.box(
      vm.Vector3(0, .035, 0),
      vm.Vector3(1.22, .10, 1.10),
      CityModels.steel,
    );
    final height = [.24, .56, .80][stage];
    for (final x in [-.47, .47]) {
      for (final z in [-.41, .41]) {
        mesh.box(
          vm.Vector3(x, height / 2, z),
          vm.Vector3(.055, height, .055),
          CityModels.orange,
        );
      }
    }
    for (final z in [-.41, .41]) {
      mesh.beam(
        vm.Vector3(-.47, height, z),
        vm.Vector3(.47, height, z),
        .04,
        CityModels.steel,
      );
    }
    mesh.box(
      vm.Vector3(.48, .78, -.45),
      vm.Vector3(.05, 1.56, .05),
      CityModels.orange,
    );
    mesh.box(
      vm.Vector3(.13, 1.49, -.45),
      vm.Vector3(.80, .055, .06),
      CityModels.orange,
    );
    mesh.box(
      vm.Vector3(-.21, 1.20, -.45),
      vm.Vector3(.015, .54, .015),
      CityModels.steel,
    );
    if (stage > 0) {
      mesh.box(
        vm.Vector3(0, height / 2, 0),
        vm.Vector3(.94, height * .75, .76),
        CityModels.warmWalls,
      );
    }
  }

  void _unit(
    _CityMesh mesh,
    double x,
    double z,
    double w,
    double d,
    double h, {
    Color color = CityModels.walls,
    Color roof = CityModels.roof,
  }) {
    mesh.box(vm.Vector3(x, h / 2, z), vm.Vector3(w, h, d), color);
    mesh.box(
      vm.Vector3(x, h + .025, z),
      vm.Vector3(w + .035, .05, d + .035),
      roof,
    );
  }

  void _tank(
    fs.Node root,
    double x,
    double z,
    double height,
    double radius, {
    bool sphere = false,
  }) {
    p.part(
      root,
      sphere ? p.sphere : p.cylinder,
      tank,
      vm.Vector3(x, height / 2, z),
      vm.Vector3(radius, height, radius),
    );
  }

  void _hydroponicBuilding(fs.Node root, _CityMesh mesh, bool active) {
    _unit(mesh, -.49, -.03, .23, .90, .28);
    for (final x in [-.12, .33]) {
      _unit(mesh, x, 0, .37, .94, .15, roof: CityModels.steel);
      p.part(
        root,
        p.sphere,
        greenhouseGlass,
        vm.Vector3(x, .29, 0),
        vm.Vector3(.39, .37, .96),
      );
      _domeFrame(mesh, vm.Vector3(x, .29, 0), .39, .37);
      for (var row = 0; row < 4; row++) {
        mesh.box(
          vm.Vector3(x, .19, -.34 + row * .22),
          vm.Vector3(.26, .055, .10),
          active ? const Color(0xff74a360) : const Color(0xff617356),
        );
      }
    }
  }

  void _foodBuilding(_CityMesh mesh, Color accent) {
    _unit(
      mesh,
      -.22,
      -.15,
      .77,
      .71,
      .48,
      color: const Color(0xffd3e1e3),
      roof: const Color(0xff829dad),
    );
    _unit(mesh, .40, -.20, .32, .59, .30, roof: accent);
    for (final x in [-.43, -.20, .03]) {
      mesh.box(
        vm.Vector3(x, .18, .215),
        vm.Vector3(.17, .30, .025),
        CityModels.windows,
      );
      mesh.box(vm.Vector3(x, .36, .24), vm.Vector3(.18, .035, .14), accent);
    }
    mesh.box(
      vm.Vector3(-.20, .08, .36),
      vm.Vector3(.78, .13, .22),
      CityModels.steel,
    );
  }

  void _analysisBuilding(fs.Node root, _CityMesh mesh, Color accent) {
    _unit(mesh, -.19, .06, .76, .66, .30, roof: accent);
    p.part(
      root,
      p.sphere,
      glass,
      vm.Vector3(-.19, .38, .06),
      vm.Vector3(.56, .36, .56),
    );
    mesh.box(
      vm.Vector3(.43, .43, -.26),
      vm.Vector3(.09, .86, .09),
      CityModels.steel,
    );
    p.part(
      root,
      p.sphere,
      p.white,
      vm.Vector3(.43, .88, -.26),
      vm.Vector3(.39, .06, .39),
      rotation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), .6),
    );
    for (var i = 0; i < 3; i++) {
      mesh.box(
        vm.Vector3(.37, .11, .10 + i * .15),
        vm.Vector3(.30, .18, .08),
        CityModels.orange,
      );
    }
  }

  void _iceBuilding(_CityMesh mesh, Color accent) {
    _unit(mesh, -.29, .22, .49, .33, .26, roof: accent);
    for (final x in [.04, .47]) {
      mesh.beam(
        vm.Vector3(x, .08, -.40),
        vm.Vector3(.26, 1.04, -.24),
        .07,
        CityModels.orange,
      );
      mesh.beam(
        vm.Vector3(x, .08, .02),
        vm.Vector3(.26, 1.04, -.24),
        .07,
        CityModels.orange,
      );
    }
    mesh.box(
      vm.Vector3(.26, .56, -.24),
      vm.Vector3(.06, 1.13, .06),
      CityModels.steel,
    );
    mesh.box(
      vm.Vector3(-.12, .15, -.39),
      vm.Vector3(.65, .10, .13),
      CityModels.steel,
    );
    for (var i = 0; i < 4; i++) {
      mesh.box(
        vm.Vector3(-.50 + i * .17, .16, -.39),
        vm.Vector3(.03, .15, .19),
        accent,
      );
    }
  }

  void _waterBuilding(fs.Node root, _CityMesh mesh, Color accent) {
    _unit(mesh, -.39, -.16, .35, .58, .38, roof: accent);
    for (final z in [-.24, .24]) {
      _tank(root, .18, z, .37, .43);
      mesh.box(
        vm.Vector3(.18, .40, z),
        vm.Vector3(.39, .025, .035),
        CityModels.steel,
      );
    }
    _pipe(root, vm.Vector3(-.20, .19, -.16), vm.Vector3(.19, .19, .24), .045);
  }

  void _printingBuilding(_CityMesh mesh, Color accent) {
    _unit(mesh, -.13, -.08, .90, .82, .42, roof: accent);
    for (var i = 0; i < 3; i++) {
      mesh.box(
        vm.Vector3(-.40 + i * .27, .50 + i * .025, -.11),
        vm.Vector3(.24, .16, .66),
        CityModels.roof,
      );
    }
    mesh.box(
      vm.Vector3(.35, .27, .39),
      vm.Vector3(.26, .48, .04),
      CityModels.windows,
    );
    for (var i = 0; i < 3; i++) {
      mesh.box(
        vm.Vector3(-.46 + i * .19, .13, .39),
        vm.Vector3(.13, .22, .16),
        CityModels.steel,
      );
    }
  }

  void _batteryBuilding(_CityMesh mesh, Color accent) {
    for (final x in [-.38, 0.0, .38]) {
      _unit(
        mesh,
        x,
        -.13,
        .28,
        .82,
        .34,
        color: const Color(0xffa4b5c0),
        roof: accent,
      );
      for (var i = 0; i < 4; i++) {
        mesh.box(
          vm.Vector3(x, .17, -.40 + i * .17),
          vm.Vector3(.29, .025, .035),
          CityModels.windows,
        );
      }
    }
    _unit(mesh, .25, .43, .37, .21, .23, roof: CityModels.orange);
  }

  void _electrolysisBuilding(fs.Node root, _CityMesh mesh, Color accent) {
    _unit(mesh, -.36, 0, .40, .82, .42, roof: accent);
    _tank(root, .17, -.24, .73, .29);
    _tank(root, .46, .21, .49, .31, sphere: true);
    mesh.box(
      vm.Vector3(.17, .52, -.24),
      vm.Vector3(.30, .08, .30),
      CityModels.orange,
    );
    mesh.box(vm.Vector3(.46, .26, .21), vm.Vector3(.32, .06, .32), accent);
    _pipe(root, vm.Vector3(-.16, .25, 0), vm.Vector3(.17, .25, -.24), .055);
    _pipe(root, vm.Vector3(.17, .25, -.24), vm.Vector3(.46, .25, .21), .04);
  }

  void _distributionBuilding(_CityMesh mesh, Color accent) {
    _unit(mesh, -.41, -.15, .28, .68, .37, roof: accent);
    for (final z in [-.27, .25]) {
      mesh.box(
        vm.Vector3(.17, .17, z),
        vm.Vector3(.54, .30, .23),
        CityModels.steel,
      );
      for (var i = 0; i < 5; i++) {
        mesh.box(
          vm.Vector3(-.02 + i * .095, .17, z),
          vm.Vector3(.025, .34, .28),
          accent,
        );
      }
      for (final x in [.02, .32]) {
        mesh.box(
          vm.Vector3(x, .43, z),
          vm.Vector3(.045, .24, .045),
          CityModels.orange,
        );
      }
    }
    mesh.box(
      vm.Vector3(.18, .035, 0),
      vm.Vector3(.55, .035, .055),
      CityModels.windows,
    );
  }

  void _maintenanceBuilding(_CityMesh mesh, Color accent) {
    for (final x in [-.47, .43]) {
      for (final z in [-.39, .22]) {
        mesh.box(
          vm.Vector3(x, .30, z),
          vm.Vector3(.045, .60, .045),
          CityModels.steel,
        );
      }
    }
    mesh.box(vm.Vector3(-.02, .64, -.08), vm.Vector3(1.04, .09, .78), accent);
    _unit(mesh, -.44, .44, .28, .23, .28);
    mesh.box(
      vm.Vector3(.05, .14, -.09),
      vm.Vector3(.47, .14, .25),
      CityModels.orange,
    );
    mesh.beam(
      vm.Vector3(.40, .10, .11),
      vm.Vector3(.35, .42, .03),
      .065,
      CityModels.steel,
    );
    mesh.beam(
      vm.Vector3(.35, .42, .03),
      vm.Vector3(.08, .47, -.12),
      .055,
      CityModels.orange,
    );
    mesh.box(
      vm.Vector3(.08, .46, -.12),
      vm.Vector3(.07, .13, .07),
      CityModels.steel,
    );
  }

  void _hangar(_CityMesh mesh, Color accent) {
    _unit(
      mesh,
      -.15,
      -.19,
      .92,
      .80,
      .59,
      color: const Color(0xffc4cdd0),
      roof: accent,
    );
    mesh.box(
      vm.Vector3(-.15, .27, .22),
      vm.Vector3(.76, .48, .025),
      CityModels.windows,
    );
    mesh.box(
      vm.Vector3(-.53, .28, .25),
      vm.Vector3(.07, .52, .07),
      CityModels.steel,
    );
    mesh.box(
      vm.Vector3(.23, .28, .25),
      vm.Vector3(.07, .52, .07),
      CityModels.steel,
    );
    mesh.box(vm.Vector3(-.15, .56, .25), vm.Vector3(.83, .06, .09), accent);
  }

  void _reusableBuilding(
    fs.Node root,
    _CityMesh mesh,
    Color accent,
    bool vehiclePresent,
  ) {
    _hangar(mesh, accent);
    // The standard camera looks from +Z. Keep the complete recovery vehicle
    // on the exposed +X apron, clear of the roof and central selection label.
    if (vehiclePresent) {
      root.add(
        p.rocket()
          ..position = vm.Vector3(.56, .30, -.36)
          ..scale = vm.Vector3.all(.40)
          ..rotation = vm.Quaternion.axisAngle(
            vm.Vector3(1, 0, 0),
            math.pi / 2,
          ),
      );
    }
    for (final z in [-.14, .30]) {
      mesh.box(
        vm.Vector3(.56, .12, z),
        vm.Vector3(.36, .24, .08),
        CityModels.steel,
      );
    }
  }

  void _shuttleBuilding(
    fs.Node root,
    _CityMesh mesh,
    Color accent,
    bool vehiclePresent,
  ) {
    _hangar(mesh, accent);
    if (vehiclePresent) {
      p.part(
        root,
        p.cylinder,
        p.white,
        vm.Vector3(.50, .36, .48),
        vm.Vector3(.30, .44, .30),
      );
      p.part(
        root,
        p.cone,
        p.white,
        vm.Vector3(.50, .69, .48),
        vm.Vector3(.30, .26, .30),
      );
      for (final sign in [-1, 1]) {
        mesh.beam(
          vm.Vector3(.50, .26, .48),
          vm.Vector3(.50 + sign * .26, .05, .48),
          .03,
          CityModels.steel,
        );
        mesh.beam(
          vm.Vector3(.50, .26, .48),
          vm.Vector3(.50, .05, .48 + sign * .26),
          .03,
          CityModels.steel,
        );
      }
    }
    mesh.box(
      vm.Vector3(.50, .03, .48),
      vm.Vector3(.60, .025, .60),
      CityModels.windows,
    );
  }
}
