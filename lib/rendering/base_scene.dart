import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

/// A presentation-only diorama. Progress and persistence stay outside the GPU.
class BaseScene extends StatefulWidget {
  const BaseScene({
    required this.earth,
    required this.earthLevel,
    required this.marsHabitats,
    required this.hasCargo,
    super.key,
  });

  final bool earth;
  final int earthLevel;
  final int marsHabitats;
  final bool hasCargo;

  @override
  State<BaseScene> createState() => _BaseSceneState();
}

class _BaseSceneState extends State<BaseScene> {
  fs.Scene? _scene;
  fs.Node? _earthRoot;
  fs.Node? _marsRoot;
  fs.Node? _cargo;
  final List<fs.Node> _earthGrowth = [];
  final List<fs.Node> _habitats = [];
  Object? _error;
  bool _loading = true;
  double _azimuth = -0.68;
  double _elevation = 0.63;

  // Share primitive buffers and materials across all the small buildings.
  late fs.CuboidGeometry _box;
  late fs.SphereGeometry _sphere;
  late fs.CylinderGeometry _cylinder;
  late fs.CylinderGeometry _cone;
  late fs.IcosphereGeometry _rock;
  late fs.PhysicallyBasedMaterial _white;
  late fs.PhysicallyBasedMaterial _blue;
  late fs.PhysicallyBasedMaterial _navy;
  late fs.PhysicallyBasedMaterial _orange;
  late fs.PhysicallyBasedMaterial _concrete;
  late fs.PhysicallyBasedMaterial _green;
  late fs.PhysicallyBasedMaterial _rust;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    fs.Scene? pending;
    try {
      await fs.Scene.initializeStaticResources();
      if (!mounted) return;
      pending = fs.Scene()
        ..environmentIntensity = 0.8
        ..directionalLight = fs.DirectionalLight(
          direction: vm.Vector3(-0.6, -1.0, 0.5),
          intensity: 2.4,
        );
      _box = fs.CuboidGeometry(vm.Vector3.all(1));
      _sphere = fs.SphereGeometry(radius: 0.5, segments: 24, rings: 12);
      _cylinder = fs.CylinderGeometry(radialSegments: 32);
      _cone = fs.CylinderGeometry(topRadius: 0, radialSegments: 16);
      _rock = fs.IcosphereGeometry(radius: 0.5, subdivisions: 0);
      _white = _material(0.79, 0.82, 0.75);
      _blue = _material(0.045, 0.34, 0.54, metallic: 0.25);
      _navy = _material(0.018, 0.06, 0.12, metallic: 0.25);
      _orange = _material(0.95, 0.34, 0.07);
      _concrete = _material(0.16, 0.23, 0.27);
      _green = _material(0.045, 0.25, 0.15);
      _rust = _material(0.45, 0.16, 0.075);
      _earthGrowth.clear();
      _habitats.clear();
      _earthRoot = _makeEarth();
      _marsRoot = _makeMars();
      pending
        ..add(_earthRoot!)
        ..add(_marsRoot!);
      _scene = pending;
      _syncProgress();
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (error, stack) {
      pending?.dispose();
      debugPrint('FlutterScene initialization: $error\n$stack');
      if (mounted) {
        setState(() {
          _scene = null;
          _error = error;
          _loading = false;
        });
      }
    }
  }

  fs.PhysicallyBasedMaterial _material(
    double red,
    double green,
    double blue, {
    double metallic = 0,
  }) => fs.PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(red, green, blue, 1)
    ..metallicFactor = metallic
    ..roughnessFactor = 0.76;

  fs.Node _part(
    fs.Node parent,
    fs.Geometry geometry,
    fs.PhysicallyBasedMaterial material,
    vm.Vector3 position,
    vm.Vector3 scale, {
    double tilt = 0,
  }) {
    final node = fs.Node(mesh: fs.Mesh(geometry, material))
      ..position = position
      ..scale = scale;
    if (tilt != 0) {
      node.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), tilt);
    }
    parent.add(node);
    return node;
  }

  void _building(fs.Node parent, double x, double z, double height) {
    _part(
      parent,
      _box,
      _white,
      vm.Vector3(x, height / 2, z),
      vm.Vector3(0.8, height, 0.75),
    );
    _part(
      parent,
      _box,
      _blue,
      vm.Vector3(x, height * 0.67, z - 0.39),
      vm.Vector3(0.64, 0.22, 0.035),
    );
    _part(
      parent,
      _box,
      _navy,
      vm.Vector3(x, height + 0.035, z),
      vm.Vector3(0.9, 0.07, 0.84),
    );
  }

  void _solar(fs.Node parent, double x, double z) {
    _part(
      parent,
      _cylinder,
      _white,
      vm.Vector3(x, 0.25, z),
      vm.Vector3(0.08, 0.5, 0.08),
    );
    _part(
      parent,
      _box,
      _navy,
      vm.Vector3(x, 0.49, z),
      vm.Vector3(1.12, 0.055, 0.76),
      tilt: -0.22,
    );
    for (var i = 0; i < 3; i++) {
      _part(
        parent,
        _box,
        _blue,
        vm.Vector3(x - 0.35 + i * 0.35, 0.525, z),
        vm.Vector3(0.31, 0.022, 0.68),
        tilt: -0.22,
      );
    }
  }

  void _launchPad(fs.Node parent, double x, double z, {bool rocket = false}) {
    _part(
      parent,
      _cylinder,
      _concrete,
      vm.Vector3(x, 0.07, z),
      vm.Vector3(2.15, 0.14, 2.15),
    );
    _part(
      parent,
      _cylinder,
      _orange,
      vm.Vector3(x, 0.147, z),
      vm.Vector3(1.62, 0.014, 1.62),
    );
    _part(
      parent,
      _cylinder,
      _navy,
      vm.Vector3(x, 0.16, z),
      vm.Vector3(1.38, 0.014, 1.38),
    );
    if (!rocket) return;
    _part(
      parent,
      _cylinder,
      _white,
      vm.Vector3(x, 1.02, z),
      vm.Vector3(0.39, 1.7, 0.39),
    );
    _part(
      parent,
      _cone,
      _orange,
      vm.Vector3(x, 2.07, z),
      vm.Vector3(0.39, 0.42, 0.39),
    );
    _part(
      parent,
      _box,
      _orange,
      vm.Vector3(x, 0.32, z),
      vm.Vector3(0.72, 0.25, 0.16),
    );
    _part(
      parent,
      _box,
      _orange,
      vm.Vector3(x, 0.32, z),
      vm.Vector3(0.16, 0.25, 0.72),
    );
    _part(
      parent,
      _box,
      _concrete,
      vm.Vector3(x + 0.67, 1.12, z + 0.3),
      vm.Vector3(0.13, 2.2, 0.13),
    );
  }

  fs.Node _makeEarth() {
    final root = fs.Node(name: '地球・産業拠点');
    final soil = _material(0.085, 0.17, 0.14);
    _part(
      root,
      _cylinder,
      soil,
      vm.Vector3(0, -0.36, 0),
      vm.Vector3(9.7, 0.7, 9.7),
    );
    _part(
      root,
      _cylinder,
      _green,
      vm.Vector3(0, 0, 0),
      vm.Vector3(9.65, 0.03, 9.65),
    );
    // Two crossing roads join manufacturing, research, and the launch pad.
    _part(
      root,
      _box,
      _concrete,
      vm.Vector3(0, 0.04, 0),
      vm.Vector3(7.7, 0.045, 0.5),
    );
    _part(
      root,
      _box,
      _concrete,
      vm.Vector3(0.15, 0.043, 0),
      vm.Vector3(0.5, 0.045, 7.6),
    );
    for (var i = -3; i <= 3; i++) {
      _part(
        root,
        _box,
        _white,
        vm.Vector3(i.toDouble(), 0.07, 0),
        vm.Vector3(0.4, 0.008, 0.045),
      );
    }
    _launchPad(root, -2.35, -1.9, rocket: true);
    _building(root, 1.1, -1.1, 1.15);
    _building(root, 2.2, -1.1, 1.55);
    _building(root, 1.1, -2.2, 0.85);
    // Factory: broad footprint, orange roof, three tanks.
    _part(
      root,
      _box,
      _white,
      vm.Vector3(-2.0, 0.4, 1.5),
      vm.Vector3(1.85, 0.8, 1.05),
    );
    _part(
      root,
      _box,
      _orange,
      vm.Vector3(-2.0, 0.83, 1.5),
      vm.Vector3(1.97, 0.1, 1.16),
    );
    for (var i = 0; i < 3; i++) {
      _part(
        root,
        _cylinder,
        _blue,
        vm.Vector3(-2.6 + i * 0.6, 0.48, 2.48),
        vm.Vector3(0.42, 0.94, 0.42),
      );
    }
    _solar(root, 1.15, 2.9);
    _solar(root, 2.55, 2.4);
    for (var i = 0; i < 6; i++) {
      final growth = fs.Node(name: '住宅 ${i + 1}');
      _building(
        growth,
        0.9 + (i % 3) * 1.02,
        0.92 + (i ~/ 3) * 1.03,
        0.85 + (i % 3) * 0.28,
      );
      root.add(growth);
      _earthGrowth.add(growth);
    }
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final x = math.cos(angle) * 4.0;
      final z = math.sin(angle) * 4.0;
      _part(
        root,
        _cylinder,
        soil,
        vm.Vector3(x, 0.19, z),
        vm.Vector3(0.08, 0.38, 0.08),
      );
      _part(
        root,
        _cone,
        _green,
        vm.Vector3(x, 0.62, z),
        vm.Vector3(0.52, 0.9, 0.52),
      );
    }
    return root;
  }

  fs.Node _makeMars() {
    final root = fs.Node(name: '火星・先遣拠点');
    _part(
      root,
      _cylinder,
      _material(0.25, 0.075, 0.04),
      vm.Vector3(0, -0.4, 0),
      vm.Vector3(9.7, 0.8, 9.7),
    );
    _part(
      root,
      _cylinder,
      _rust,
      vm.Vector3(0, 0.01, 0),
      vm.Vector3(9.65, 0.045, 9.65),
    );
    final dust = _material(0.59, 0.27, 0.12);
    final rock = _material(0.30, 0.10, 0.055);
    for (var i = 0; i < 18; i++) {
      final angle = i * 2.39996;
      final radius = 3.7 + (i % 3) * 0.26;
      final size = 0.3 + (i % 4) * 0.14;
      _part(
        root,
        _rock,
        i.isEven ? dust : rock,
        vm.Vector3(
          math.cos(angle) * radius,
          size * 0.25,
          math.sin(angle) * radius,
        ),
        vm.Vector3(size * 1.4, size, size),
      );
    }
    _launchPad(root, -2.3, -1.8);
    _solar(root, -2.6, 1.1);
    _solar(root, -2.6, 2.1);
    _solar(root, -1.2, 2.1);
    // Communication mast marks the initial robotic outpost.
    _part(
      root,
      _box,
      _concrete,
      vm.Vector3(0.05, 0.17, -2.8),
      vm.Vector3(0.7, 0.34, 0.7),
    );
    _part(
      root,
      _cylinder,
      _white,
      vm.Vector3(0.05, 1.1, -2.8),
      vm.Vector3(0.08, 1.9, 0.08),
    );
    _part(
      root,
      _sphere,
      _orange,
      vm.Vector3(0.05, 2.1, -2.8),
      vm.Vector3(0.22, 0.22, 0.22),
    );
    _part(
      root,
      _box,
      _blue,
      vm.Vector3(0.05, 1.76, -2.8),
      vm.Vector3(0.9, 0.12, 0.35),
      tilt: 0.6,
    );
    _cargo = fs.Node(name: '着陸済み貨物');
    _part(
      _cargo!,
      _box,
      _orange,
      vm.Vector3(-2.3, 0.48, -1.8),
      vm.Vector3(0.75, 0.62, 0.72),
    );
    _part(
      _cargo!,
      _box,
      _white,
      vm.Vector3(-2.3, 0.81, -1.8),
      vm.Vector3(0.82, 0.07, 0.78),
    );
    root.add(_cargo!);
    for (var i = 0; i < 6; i++) {
      final habitat = fs.Node(name: '与圧居住棟 ${i + 1}');
      final x = 0.8 + (i % 2) * 1.75;
      final z = -1.8 + (i ~/ 2) * 1.8;
      _part(
        habitat,
        _cylinder,
        _concrete,
        vm.Vector3(x, 0.1, z),
        vm.Vector3(1.65, 0.2, 1.65),
      );
      // Lower half of the sphere sits inside the solid cylinder, making a dome.
      _part(
        habitat,
        _cylinder,
        _white,
        vm.Vector3(x, 0.48, z),
        vm.Vector3(1.34, 0.76, 1.34),
      );
      _part(
        habitat,
        _sphere,
        _blue,
        vm.Vector3(x, 0.88, z),
        vm.Vector3(1.35, 1.02, 1.35),
      );
      _part(
        habitat,
        _box,
        _orange,
        vm.Vector3(x, 0.34, z - 0.76),
        vm.Vector3(0.48, 0.5, 0.46),
      );
      _part(
        habitat,
        _box,
        _concrete,
        vm.Vector3(x, 0.07, z - 1.04),
        vm.Vector3(0.55, 0.14, 0.32),
      );
      root.add(habitat);
      _habitats.add(habitat);
    }
    return root;
  }

  void _syncProgress() {
    _earthRoot?.visible = widget.earth;
    _marsRoot?.visible = !widget.earth;
    _cargo?.visible = widget.hasCargo;
    for (var i = 0; i < _earthGrowth.length; i++) {
      _earthGrowth[i].visible = i < widget.earthLevel;
    }
    for (var i = 0; i < _habitats.length; i++) {
      _habitats[i].visible = i < widget.marsHabitats;
    }
  }

  @override
  void didUpdateWidget(covariant BaseScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncProgress();
  }

  @override
  void dispose() {
    _scene?.removeAll();
    _scene?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, 0.1),
          radius: 1.05,
          colors: widget.earth
              ? const [Color(0xff183d45), Color(0xff07111e)]
              : const [Color(0xff422820), Color(0xff100f19)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _StarsPainter()),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            _failure()
          else if (_scene != null)
            Semantics(
              label: widget.earth
                  ? '地球の産業拠点。住宅開発 ${widget.earthLevel} 段階。ドラッグで回転。'
                  : '火星の先遣拠点。与圧居住棟 ${widget.marsHabitats} 棟。ドラッグで回転。',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => setState(() {
                  _azimuth -= details.delta.dx * 0.009;
                  _elevation = (_elevation + details.delta.dy * 0.005).clamp(
                    0.35,
                    1.15,
                  );
                }),
                child: fs.SceneView(
                  _scene!,
                  camera: fs.OrthographicCamera(
                    position: vm.Vector3(
                      math.sin(_azimuth) * math.cos(_elevation) * 16,
                      math.sin(_elevation) * 16,
                      -math.cos(_azimuth) * math.cos(_elevation) * 16,
                    ),
                    target: vm.Vector3(0, 0.5, 0),
                    projection: fs.OrthographicProjection(
                      size: const fs.OrthographicSize.contain(11.3, 8.4),
                      near: 0.1,
                      far: 50,
                    ),
                  ),
                ),
              ),
            ),
          if (!_loading && _error == null)
            const Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Text(
                  'ドラッグで見回す · 発展すると街が変化',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xff9aabb5), fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _failure() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.view_in_ar_outlined,
            color: Color(0xffdb9c73),
            size: 36,
          ),
          const SizedBox(height: 12),
          const Text('3D表示を開始できませんでした', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text(
            '再試行するか、アプリを起動し直してください。\n開発環境では Flutter GPU の有効化を確認してください。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xffa5b4be)),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _initialize();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('3D表示を再試行'),
          ),
        ],
      ),
    ),
  );
}

class _StarsPainter extends CustomPainter {
  const _StarsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var i = 0; i < 46; i++) {
      final x = ((i * 73 + 17) % 997) / 997 * size.width;
      final y = ((i * 137 + 53) % 991) / 991 * size.height;
      paint.color = Color(i % 5 == 0 ? 0x667faaaa : 0x337faaaa);
      canvas.drawCircle(Offset(x, y), i % 5 == 0 ? 1.1 : 0.65, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarsPainter oldDelegate) => false;
}
