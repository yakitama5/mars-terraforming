import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'planet_geometry.dart';
import 'planet_models.dart';

export 'planet_models.dart' show SceneCity;

/// An offline, presentation-only globe. Progress and persistence stay outside
/// the GPU; city snapshots are mapped by the presentation layer.
class BaseScene extends StatefulWidget {
  const BaseScene({
    required this.earth,
    required this.earthLevel,
    required this.marsHabitats,
    required this.hasCargo,
    this.cities = const [],
    this.selectedCityId,
    this.onCitySelected,
    super.key,
  });

  final bool earth;
  final int earthLevel;
  final int marsHabitats;
  final bool hasCargo;
  final List<SceneCity> cities;
  final String? selectedCityId;
  final ValueChanged<String>? onCitySelected;

  @override
  State<BaseScene> createState() => _BaseSceneState();
}

class _BaseSceneState extends State<BaseScene> {
  fs.Scene? _scene;
  PlanetModels? _models;
  fs.Node? _earthRoot;
  fs.Node? _marsRoot;
  fs.Node? _citiesRoot;
  fs.Node? _rocket;
  List<SceneCity> _shownCities = const [];
  String? _shownSelected;
  bool? _shownEarth;
  bool? _shownCargo;
  Object? _error;
  bool _loading = true;
  double _azimuth = -0.60;
  double _elevation = 0.35;
  double _zoom = 1;
  double _gestureZoom = 1;

  @override
  void initState() {
    super.initState();
    _resetView();
    _initialize();
  }

  List<SceneCity> get _cities => widget.cities.isNotEmpty
      ? widget.cities
      : widget.earth
      ? [
          SceneCity(
            id: 'earth_delta',
            name: 'デルタ湾岸',
            latitude: 28,
            longitude: -80,
            development: widget.earthLevel,
          ),
          const SceneCity(
            id: 'earth_highland',
            name: '高原科学都市',
            latitude: 35,
            longitude: 10,
            development: 1,
          ),
        ]
      : [
          SceneCity(
            id: 'mars_arcadia',
            name: 'アルカディア',
            latitude: 40,
            longitude: -110,
            development: widget.marsHabitats,
          ),
          const SceneCity(
            id: 'mars_elysium',
            name: 'エリシウム',
            latitude: 5,
            longitude: 150,
            isActive: false,
          ),
          const SceneCity(
            id: 'mars_hellas',
            name: 'ヘラス',
            latitude: -42,
            longitude: 70,
            isActive: false,
          ),
        ];

  Future<void> _initialize() async {
    fs.Scene? pending;
    try {
      await fs.Scene.initializeStaticResources();
      if (!mounted) return;
      pending = fs.Scene()
        ..environmentIntensity = 0.82
        ..directionalLight = fs.DirectionalLight(
          direction: vm.Vector3(0.35, -0.75, 0.55),
          intensity: 2.6,
        );
      final models = PlanetModels();
      _models = models;
      _earthRoot = models.globe(true);
      _marsRoot = models.globe(false);
      _rocket = models.rocket()..scale = vm.Vector3.all(0.62);
      pending
        ..add(_earthRoot!)
        ..add(_marsRoot!)
        ..add(models.orbit())
        ..add(_rocket!);
      _scene = pending;
      _syncVisuals(force: true);
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

  void _syncVisuals({bool force = false}) {
    final scene = _scene;
    final models = _models;
    if (scene == null || models == null) return;
    _earthRoot?.visible = widget.earth;
    _marsRoot?.visible = !widget.earth;
    final cities = _cities;
    final unchanged =
        _shownCities.length == cities.length &&
        List.generate(
          cities.length,
          (i) => cities[i].hasSameAppearance(_shownCities[i]),
        ).every((v) => v);
    if (!force &&
        unchanged &&
        _shownSelected == widget.selectedCityId &&
        _shownEarth == widget.earth &&
        _shownCargo == widget.hasCargo) {
      return;
    }
    if (_citiesRoot != null) scene.remove(_citiesRoot!);
    final root = fs.Node(name: '都市と調査地点');
    for (var i = 0; i < cities.length; i++) {
      root.add(
        models.city(
          cities[i],
          earth: widget.earth,
          selected: cities[i].id == widget.selectedCityId,
          cargo: widget.hasCargo && i == 0,
        ),
      );
    }
    scene.add(root);
    _citiesRoot = root;
    _shownCities = List.of(cities);
    _shownSelected = widget.selectedCityId;
    _shownEarth = widget.earth;
    _shownCargo = widget.hasCargo;
  }

  void _resetView() {
    _zoom = 1;
    _elevation = widget.earth ? 0.38 : 0.32;
    _azimuth = widget.earth ? -0.58 : -1.52;
  }

  void _focusCity(String? id) {
    for (final city in _cities) {
      if (city.id != id) continue;
      _azimuth = city.longitude * math.pi / 180 + 0.20;
      _elevation = (city.latitude * math.pi / 180 - 0.10).clamp(-1.15, 1.15);
      return;
    }
  }

  @override
  void didUpdateWidget(covariant BaseScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.earth != widget.earth) {
      _resetView();
    } else if (oldWidget.selectedCityId != widget.selectedCityId) {
      _focusCity(widget.selectedCityId);
    }
    _syncVisuals();
  }

  @override
  void dispose() {
    _scene?.removeAll();
    _scene?.dispose();
    super.dispose();
  }

  fs.OrthographicCamera _camera() {
    final direction = planetPoint(
      _elevation * 180 / math.pi,
      _azimuth * 180 / math.pi,
      1,
    );
    // The foreground transport keeps its detailed silhouette readable as the
    // player rotates the planet. The orbit is a schematic, not flight physics.
    final right = vm.Vector3(-direction.z, 0, direction.x)..normalize();
    final up = right.cross(direction)..normalize();
    _scene?.directionalLight = fs.DirectionalLight(
      direction: right * 0.5 - up * 0.7 - direction * 0.8,
      intensity: 2.6,
    );
    _rocket?.position = right * 3.65 + up * 0.85 + direction * 0.8;
    _rocket?.rotation = vm.Quaternion.fromTwoVectors(
      vm.Vector3(0, 1, 0),
      (up + right * 0.3).normalized(),
    );
    return fs.OrthographicCamera(
      position: direction * 18,
      target: vm.Vector3.zero(),
      projection: fs.OrthographicProjection(
        size: fs.OrthographicSize.contain(10.6 / _zoom, 8.6 / _zoom),
        near: 0.1,
        far: 40,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: const Alignment(-0.15, -0.05),
        radius: 0.85,
        colors: widget.earth
            ? const [Color(0xff122e42), Color(0xff06101c)]
            : const [Color(0xff39251f), Color(0xff0b101b)],
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
          LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final camera = _camera();
              return Stack(
                fit: StackFit.expand,
                children: [
                  Semantics(
                    label: widget.earth
                        ? '地球の球体と複数の都市。ドラッグで回転、ピンチで拡大。'
                        : '火星の球体と開発・調査地点。ドラッグで回転、ピンチで拡大。',
                    child: Listener(
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) {
                          GestureBinding.instance.pointerSignalResolver
                              .register(event, (event) {
                                final scroll = event as PointerScrollEvent;
                                setState(
                                  () => _zoom =
                                      (_zoom - scroll.scrollDelta.dy * 0.0015)
                                          .clamp(0.85, 1.65),
                                );
                              });
                        }
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: (_) => _gestureZoom = _zoom,
                        onScaleUpdate: (details) => setState(() {
                          _azimuth -= details.focalPointDelta.dx * 0.007;
                          _elevation =
                              (_elevation + details.focalPointDelta.dy * 0.005)
                                  .clamp(-1.2, 1.2);
                          _zoom = (_gestureZoom * details.scale).clamp(
                            0.85,
                            1.65,
                          );
                        }),
                        child: fs.SceneView(
                          _scene!,
                          camera: camera,
                          maxFrameRate: 30,
                          pixelRatio: MediaQuery.devicePixelRatioOf(context)
                              .clamp(1, 2),
                        ),
                      ),
                    ),
                  ),
                  for (final city in _cities) ..._marker(city, camera, size),
                  Positioned(right: 10, bottom: 44, child: _viewControls()),
                  Positioned(
                    left: 12,
                    bottom: 46,
                    child: IgnorePointer(
                      child: Text(
                        size.width < 450
                            ? 'ドラッグで回転 · 都市を選択'
                            : 'ドラッグで回転 · ピンチで拡大 · 都市を選択',
                        style: const TextStyle(
                          color: Color(0xff7e98a8),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    ),
  );

  List<Widget> _marker(SceneCity city, fs.Camera camera, Size size) {
    final point = planetPoint(city.latitude, city.longitude, 3.24);
    if (point.normalized().dot(camera.position.normalized()) < 0.20) {
      return const [];
    }
    final anchor = camera.worldToScreen(point, size);
    if (anchor == null) return const [];
    // Keep controls above the miniature buildings, including a city directly
    // facing the camera where radial offsets project to the same pixel.
    final screen = anchor - const Offset(0, 30);
    if (screen.dx < 12 ||
        screen.dx > size.width - 12 ||
        screen.dy < 20 ||
        screen.dy > size.height - 54) {
      return const [];
    }
    final selected = city.id == widget.selectedCityId;
    final color = selected ? const Color(0xff8fe3d6) : const Color(0xfff2bd8c);
    return [
      Positioned(
        left: screen.dx - 0.5,
        top: screen.dy + 15,
        child: IgnorePointer(
          child: Container(
            width: 1,
            height: 13,
            color: color.withValues(alpha: 0.5),
          ),
        ),
      ),
      Positioned(
        left: screen.dx - 16,
        top: screen.dy - 16,
        child: Semantics(
          button: true,
          selected: selected,
          label: '${city.name}を選択${city.isActive ? '' : '、調査地点'}',
          child: Tooltip(
            message: city.name,
            child: GestureDetector(
              onTap: widget.onCitySelected == null
                  ? null
                  : () => widget.onCitySelected!(city.id),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x99091522),
                  border: Border.all(color: color, width: selected ? 2 : 1),
                ),
                child: Icon(
                  city.isActive ? Icons.location_city : Icons.flag_outlined,
                  color: color,
                  size: 16,
                ),
              ),
            ),
          ),
        ),
      ),
      if (selected)
        Positioned(
          left: (screen.dx - 64).clamp(4, math.max(4, size.width - 132)),
          top: screen.dy - 42,
          child: IgnorePointer(
            child: Container(
              width: 128,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xe6091522),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                city.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _viewControls() => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xbb071321),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: const Color(0xff2a4050)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _control(
          Icons.remove,
          '惑星を縮小',
          () => setState(() => _zoom = (_zoom - 0.15).clamp(0.85, 1.65)),
        ),
        _control(
          Icons.add,
          '惑星を拡大',
          () => setState(() => _zoom = (_zoom + 0.15).clamp(0.85, 1.65)),
        ),
        _control(Icons.public, '惑星全体を表示', () => setState(_resetView)),
      ],
    ),
  );

  Widget _control(IconData icon, String tooltip, VoidCallback onPressed) =>
      IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 16),
        color: const Color(0xffa8c5cd),
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        padding: EdgeInsets.zero,
      );

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
            '再試行するか、アプリを起動し直してください。',
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
    for (var i = 0; i < 72; i++) {
      final x = ((i * 73 + 17) % 997) / 997 * size.width;
      final y = ((i * 137 + 53) % 991) / 991 * size.height;
      paint.color = Color(i % 7 == 0 ? 0x809abbc9 : 0x408ca4b5);
      canvas.drawCircle(Offset(x, y), i % 7 == 0 ? 1.1 : 0.6, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarsPainter oldDelegate) => false;
}
