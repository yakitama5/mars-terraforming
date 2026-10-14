import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'city_geometry.dart';
import 'city_models.dart';
import 'city_snapshot.dart';

export 'city_geometry.dart' show CityTerrain, CityMapProjection;
export 'city_snapshot.dart' show ScenePlot, SceneWorkState;

/// A regional map, with terrain, developments and plot input sharing one frame.
/// No progress, cost, adjacency rules or persistence are calculated here.
class CityScene extends StatefulWidget {
  const CityScene({
    required this.cityId,
    required this.cityName,
    required this.earth,
    required this.columns,
    required this.rows,
    required this.plots,
    required this.selectedPlot,
    required this.adjacentPlots,
    required this.onPlotSelected,
    this.renderScene = true,
    super.key,
  });

  final String cityId, cityName;
  final bool earth, renderScene;
  final int columns, rows, selectedPlot;
  final List<ScenePlot> plots;
  final Set<int> adjacentPlots;
  final ValueChanged<int> onPlotSelected;

  @override
  State<CityScene> createState() => _CitySceneState();
}

class _CitySceneState extends State<CityScene> {
  late CityTerrain _terrain;
  fs.Scene? _scene;
  CityModels? _models;
  fs.Node? _landscape, _developments;
  Object? _error;
  bool _loading = false;
  int _initialization = 0;
  double _panX = 0, _panZ = 0;
  double _zoom = 1, _gestureZoom = 1, _azimuth = .18, _elevation = .92;

  @override
  void initState() {
    super.initState();
    _terrain = _makeTerrain();
    if (widget.renderScene) _initialize();
  }

  CityTerrain _makeTerrain() => CityTerrain(
    earth: widget.earth,
    columns: widget.columns,
    rows: widget.rows,
    plots: widget.plots,
  );

  Future<void> _initialize() async {
    final generation = ++_initialization;
    _loading = true;
    fs.Scene? pending;
    try {
      await fs.Scene.initializeStaticResources();
      if (!mounted || generation != _initialization || !widget.renderScene) {
        return;
      }
      pending = fs.Scene()
        ..environmentIntensity = .45
        ..directionalLight = fs.DirectionalLight(
          direction: vm.Vector3(-.4, -.85, -.30),
          intensity: 1.3,
        );
      _models = CityModels();
      _scene = pending;
      _updateModels(landscape: true);
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (error, stack) {
      pending?.dispose();
      debugPrint('City FlutterScene initialization: $error\n$stack');
      if (mounted && generation == _initialization) {
        setState(() {
          _scene = null;
          _models = null;
          _loading = false;
          _error = error;
        });
      }
    }
  }

  void _updateModels({bool landscape = false}) {
    final scene = _scene;
    final models = _models;
    if (scene == null || models == null) return;
    if (landscape) {
      if (_landscape != null) scene.remove(_landscape!);
      _landscape = models.landscape(_terrain, cityId: widget.cityId);
      scene.add(_landscape!);
    }
    if (_developments != null) scene.remove(_developments!);
    _developments = models.developments(_terrain, widget.plots);
    scene.add(_developments!);
  }

  void _resetView() {
    _zoom = 1;
    _panX = 0;
    _panZ = 0;
    _azimuth = .18;
    _elevation = .92;
  }

  void _setZoom(double value) {
    _zoom = value.clamp(.8, 1.8);
    // When the whole city is visible, keep it near the center. Zooming in
    // gradually opens a wider pan range to inspect the edge plots.
    final xLimit = _terrain.halfWidth * (_zoom - .8) * .45;
    final zLimit = _terrain.halfDepth * (_zoom - .8) * .45;
    _panX = _panX.clamp(-xLimit, xLimit);
    _panZ = _panZ.clamp(-zLimit, zLimit);
  }

  @override
  void didUpdateWidget(covariant CityScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedTerrain =
        oldWidget.cityId != widget.cityId ||
        oldWidget.earth != widget.earth ||
        oldWidget.columns != widget.columns ||
        oldWidget.rows != widget.rows ||
        oldWidget.plots.length != widget.plots.length ||
        List.generate(widget.plots.length, (i) => i).any(
          (i) =>
              oldWidget.plots[i].index != widget.plots[i].index ||
              oldWidget.plots[i].terrain != widget.plots[i].terrain,
        );
    if (changedTerrain) {
      _terrain = _makeTerrain();
      _resetView();
    }
    if (oldWidget.renderScene != widget.renderScene) {
      if (widget.renderScene) {
        _initialize();
      } else {
        _disposeScene();
        _loading = false;
        _error = null;
      }
    } else if (changedTerrain ||
        List.generate(
          widget.plots.length,
          (i) => i,
        ).any((i) => !widget.plots[i].hasSameModel(oldWidget.plots[i]))) {
      _updateModels(landscape: changedTerrain);
    }
  }

  void _disposeScene() {
    _initialization++;
    _scene?.removeAll();
    _scene?.dispose();
    _scene = null;
    _models = null;
    _landscape = null;
    _developments = null;
  }

  @override
  void dispose() {
    _disposeScene();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: ColoredBox(
      color: widget.earth ? const Color(0xff182f31) : const Color(0xff342b27),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final view = CityMapProjection(
            terrain: _terrain,
            azimuth: _azimuth,
            elevation: _elevation,
            zoom: _zoom,
            panX: _panX,
            panZ: _panZ,
          );
          final gpuReady = widget.renderScene && _scene != null && !_loading;
          return Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                GestureBinding.instance.pointerSignalResolver.register(event, (
                  event,
                ) {
                  final scroll = event as PointerScrollEvent;
                  setState(
                    () => _setZoom(_zoom - scroll.scrollDelta.dy * .0015),
                  );
                });
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) => _gestureZoom = _zoom,
              onScaleUpdate: (details) => setState(() {
                final camera = view.camera;
                final origin = camera.worldToScreen(vm.Vector3.zero(), size)!;
                final x =
                    camera.worldToScreen(vm.Vector3(1, 0, 0), size)! - origin;
                final z =
                    camera.worldToScreen(vm.Vector3(0, 0, 1), size)! - origin;
                final det = x.dx * z.dy - x.dy * z.dx;
                if (det.abs() > .001) {
                  final delta = details.focalPointDelta;
                  _panX = (_panX - (delta.dx * z.dy - delta.dy * z.dx) / det)
                      .clamp(
                        -_terrain.halfWidth * (_zoom - .8) * .45,
                        _terrain.halfWidth * (_zoom - .8) * .45,
                      );
                  _panZ = (_panZ - (x.dx * delta.dy - x.dy * delta.dx) / det)
                      .clamp(
                        -_terrain.halfDepth * (_zoom - .8) * .45,
                        _terrain.halfDepth * (_zoom - .8) * .45,
                      );
                }
                _setZoom(_gestureZoom * details.scale);
              }),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (gpuReady)
                    ExcludeSemantics(
                      child: fs.SceneView(
                        _scene!,
                        camera: view.camera,
                        maxFrameRate: 30,
                        pixelRatio: MediaQuery.devicePixelRatioOf(context)
                            .clamp(1, 2),
                      ),
                    )
                  else
                    CustomPaint(
                      painter: _MapFallbackPainter(view, widget.plots),
                    ),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _PlotBoundaryPainter(
                        view: view,
                        plots: widget.plots,
                        selected: widget.selectedPlot,
                        adjacent: widget.adjacentPlots,
                      ),
                    ),
                  ),
                  for (final plot in widget.plots)
                    _plotTarget(plot, view, size),
                  Positioned(
                    left: 10,
                    bottom: size.width >= 420 ? 10 : null,
                    top: size.width < 420 ? 10 : null,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0xb30b1820),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          child: Text(
                            size.width < 500
                                ? 'ドラッグで移動'
                                : '区画を選択 · ドラッグで移動 · ピンチ／ホイールで拡大',
                            style: const TextStyle(
                              color: Color(0xffc5d0ce),
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: _controls(size.width >= 700 ? 44 : 40),
                  ),
                  if (_loading)
                    const Positioned(
                      top: 10,
                      right: 12,
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  if (_error != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      right: 8,
                      child: Material(
                        color: const Color(0xeb15232b),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 5, 5, 5),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '3Dを開始できないため簡易地図を表示しています。',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() => _error = null);
                                  _initialize();
                                },
                                child: const Text('再試行'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _plotTarget(ScenePlot plot, CityMapProjection view, Size size) {
    final polygon = view.polygon(plot.index, size);
    final bounds = polygon.getBounds();
    final localPath = polygon.shift(-bounds.topLeft);
    final work = switch (plot.workState) {
      SceneWorkState.none => '',
      SceneWorkState.queued => '、建設予約あり',
      SceneWorkState.building => '、建設中',
    };
    return Positioned.fromRect(
      rect: bounds,
      child: ClipPath(
        clipper: _PlotClipper(localPath),
        child: Semantics(
          label:
              '${widget.cityName}の区画${plot.index + 1}、${plot.label}$work${plot.workLabel == null ? '' : '、${plot.workLabel}'}',
          button: true,
          selected: widget.selectedPlot == plot.index,
          child: GestureDetector(
            key: Key('plot-${widget.cityId}-${plot.index}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onPlotSelected(plot.index),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  Widget _controls(double targetSize) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xe6102028),
      border: Border.all(color: const Color(0xff6b7b78)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _control(
          targetSize,
          Icons.remove,
          '都市地図を縮小',
          () => setState(() => _setZoom(_zoom - .15)),
        ),
        _control(
          targetSize,
          Icons.add,
          '都市地図を拡大',
          () => setState(() => _setZoom(_zoom + .15)),
        ),
        _control(
          targetSize,
          Icons.rotate_left,
          '都市地図を左回転',
          () => setState(() => _azimuth -= math.pi / 6),
        ),
        _control(
          targetSize,
          Icons.rotate_right,
          '都市地図を右回転',
          () => setState(() => _azimuth += math.pi / 6),
        ),
        _control(
          targetSize,
          Icons.explore_outlined,
          '都市地図の視点を戻す',
          () => setState(_resetView),
        ),
      ],
    ),
  );

  Widget _control(
    double targetSize,
    IconData icon,
    String tooltip,
    VoidCallback action,
  ) => IconButton(
    tooltip: tooltip,
    onPressed: action,
    constraints: BoxConstraints.tightFor(width: targetSize, height: targetSize),
    padding: EdgeInsets.zero,
    icon: Icon(icon, size: 19, color: const Color(0xffd2dad4)),
  );
}

class _PlotClipper extends CustomClipper<Path> {
  const _PlotClipper(this.path);
  final Path path;
  @override
  Path getClip(Size size) => path;
  @override
  bool shouldReclip(covariant _PlotClipper oldClipper) => true;
}

class _PlotBoundaryPainter extends CustomPainter {
  const _PlotBoundaryPainter({
    required this.view,
    required this.plots,
    required this.selected,
    required this.adjacent,
  });
  final CityMapProjection view;
  final List<ScenePlot> plots;
  final int selected;
  final Set<int> adjacent;

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()..style = PaintingStyle.stroke;
    final text = TextPainter(textDirection: TextDirection.ltr);
    for (final plot in plots) {
      final isSelected = plot.index == selected;
      final isAdjacent = adjacent.contains(plot.index);
      final color = isSelected
          ? const Color(0xffffe3a1)
          : isAdjacent
          ? const Color(0xffcaa97a)
          : const Color(0xa6425149);
      border
        ..color = color
        ..strokeWidth = isSelected
            ? 2.4
            : isAdjacent
            ? 1.4
            : .8;
      final polygon = view.polygon(plot.index, size);
      if (isSelected) {
        canvas.drawPath(polygon, Paint()..color = const Color(0x15ffe3a1));
      }
      canvas.drawPath(polygon, border);
      final bounds = polygon.getBounds();
      final center = view.center(plot.index, size);
      if (!isSelected &&
          !plot.isDeveloped &&
          plot.workState == SceneWorkState.none) {
        continue;
      }
      final use = switch (plot.districtId) {
        'housing' => '住宅',
        'campus' || 'mars_lab' => '研究',
        'industry' => '工業',
        'solar' => '発電',
        'spaceport' => '宇宙港',
        'mars_habitat' => '居住',
        'greenhouse' => '温室',
        'extractor' => '採取',
        _ => plot.districtName ?? '',
      };
      final label = switch (plot.workState) {
        SceneWorkState.queued => '予 · $use',
        SceneWorkState.building => '工 · $use',
        SceneWorkState.none =>
          plot.isDeveloped
              ? '$use Lv.${plot.level}'
              : '${plot.index + 1} · ${plot.terrainName}',
      };
      text.text = TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'NotoSansJP',
          fontSize: bounds.width < 65 ? 8 : 10,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? const Color(0xffffe6b2) : const Color(0xffe1e8df),
        ),
      );
      text.layout();
      final labelPosition = Offset(
        center.dx - text.width / 2,
        bounds.bottom - text.height - 3,
      );
      final labelBounds = labelPosition & text.size;
      canvas.drawRect(
        labelBounds.inflate(2),
        Paint()..color = const Color(0xb3142428),
      );
      text.paint(canvas, labelPosition);
      if (plot.workState == SceneWorkState.building) {
        final progressWidth = math.min(28.0, bounds.width * .55);
        final progress = Rect.fromLTWH(
          center.dx - progressWidth / 2,
          labelPosition.dy - 4,
          progressWidth,
          2,
        );
        canvas.drawRect(progress, Paint()..color = const Color(0xc0203336));
        canvas.drawRect(
          Rect.fromLTWH(
            progress.left,
            progress.top,
            progress.width * plot.workProgress.clamp(0, 1),
            progress.height,
          ),
          Paint()..color = const Color(0xffe4b775),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PlotBoundaryPainter oldDelegate) => true;
}

/// The same map remains selectable while the GPU initializes or is unavailable.
/// Widget tests use this path without allocating any FlutterScene resources.
class _MapFallbackPainter extends CustomPainter {
  const _MapFallbackPainter(this.view, this.plots);
  final CityMapProjection view;
  final List<ScenePlot> plots;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final plot in plots) {
      final center = view.terrain.center(plot.index);
      paint.color = view.terrain.colorAt(center.x, center.z);
      canvas.drawPath(view.polygon(plot.index, size), paint);
      if (plot.isDeveloped) {
        final screen = view.center(plot.index, size);
        paint.color = const Color(0xffa8beb6);
        canvas.drawRect(
          Rect.fromCenter(
            center: screen,
            width: 8 + plot.level * 3,
            height: 7 + plot.level * 3,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapFallbackPainter oldDelegate) => true;
}
