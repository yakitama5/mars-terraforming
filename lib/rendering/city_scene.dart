import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'city_geometry.dart';
import 'city_models.dart';
import 'city_snapshot.dart';

export 'city_geometry.dart' show CityTerrain, CityMapProjection;
export 'city_snapshot.dart' show ScenePlot, SceneBuilding, SceneWorkState;

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
    this.moon = false,
    this.constructionMode = false,
    this.buildablePlots = const {},
    this.legacyBuildings = const [],
    this.selectedBuildingId,
    this.onBuildingSelected,
    this.selectedBuildingSlot,
    this.onBuildingSlotSelected,
    this.buildingPlacementMode = false,
    this.buildingOccupiesWholePlot = false,
    this.availableBuildingSlots = const {0, 1},
    super.key,
  });

  final String cityId, cityName;
  final bool earth, moon, renderScene, constructionMode;
  final Set<int> buildablePlots;
  final int columns, rows, selectedPlot;
  final List<ScenePlot> plots;
  final Set<int> adjacentPlots;
  final ValueChanged<int> onPlotSelected;
  final List<SceneBuilding> legacyBuildings;
  final String? selectedBuildingId;
  final ValueChanged<String>? onBuildingSelected;
  final int? selectedBuildingSlot;
  final ValueChanged<int>? onBuildingSlotSelected;
  final bool buildingPlacementMode, buildingOccupiesWholePlot;
  final Set<int> availableBuildingSlots;

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
  double _zoom = CityMapProjection.overviewZoom;
  double _gestureZoom = CityMapProjection.overviewZoom;
  double _azimuth = CityMapProjection.neighborhoodAzimuth;
  double _gestureAzimuth = CityMapProjection.neighborhoodAzimuth;
  double _elevation = CityMapProjection.overviewElevation;

  @override
  void initState() {
    super.initState();
    _terrain = _makeTerrain();
    if (widget.buildingPlacementMode && widget.selectedPlot >= 0) {
      _showNeighborhood();
    }
    if (widget.selectedBuildingId != null) {
      _focusBuilding(widget.selectedBuildingId!);
    }
    if (widget.renderScene) _initialize();
  }

  CityTerrain _makeTerrain() => CityTerrain(
    earth: widget.earth,
    moon: widget.moon,
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
        ..environmentIntensity = .55
        ..directionalLight = fs.DirectionalLight(
          direction: vm.Vector3(-.6, -.78, -.42),
          color: vm.Vector3(1, .965, .90),
          intensity: 2.0,
          castsShadow: true,
          cacheStaticShadows: true,
          shadowCasterFaces: fs.ShadowCasterFaces.both,
          shadowAmbientStrength: .25,
          shadowCascadeCount: 1,
          shadowMaxDistance: 40,
          shadowMapResolution: 1024,
          shadowSoftness: .04,
          shadowDepthBias: .004,
          shadowNormalBias: .012,
        );
      // Tight contact shading grounds roofs, vegetation and walls. A half-size
      // buffer keeps the extra passes bounded on mobile and in the Web build.
      pending.ambientOcclusion
        ..enabled = true
        ..radius = .16
        ..intensity = .65
        ..power = 1.2
        ..halfResolution = true;
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
    _developments = models.developments(
      _terrain,
      widget.plots,
      legacyBuildings: widget.legacyBuildings,
    );
    scene.add(_developments!);
  }

  void _resetView() {
    _zoom = CityMapProjection.overviewZoom;
    _panX = 0;
    _panZ = 0;
    _azimuth = CityMapProjection.neighborhoodAzimuth;
    _elevation = CityMapProjection.overviewElevation;
  }

  void _showNeighborhood() {
    _resetView();
    _zoom = CityMapProjection.neighborhoodZoom;
    _elevation = CityMapProjection.neighborhoodElevation;
    if (widget.selectedPlot >= 0 && widget.selectedPlot < widget.plots.length) {
      final focus = _terrain.center(widget.selectedPlot);
      _panX = focus.x;
      _panZ = focus.z;
    }
    _clampPan();
  }

  void _showOverview() {
    _resetView();
    _zoom = CityMapProjection.overviewZoom;
    _elevation = CityMapProjection.overviewElevation;
  }

  void _setZoom(double value) {
    _zoom = value.clamp(CityMapProjection.minZoom, CityMapProjection.maxZoom);
    _clampPan();
  }

  void _clampPan() {
    // At close range every border plot can be brought into the center. At
    // overview scale the frame stays near the city instead of drifting away.
    final fraction = ((_zoom - CityMapProjection.minZoom) * .9).clamp(0.0, 1.0);
    final xLimit = _terrain.halfWidth * fraction;
    final zLimit = _terrain.halfDepth * fraction;
    _panX = _panX.clamp(-xLimit, xLimit);
    _panZ = _panZ.clamp(-zLimit, zLimit);
  }

  @override
  void didUpdateWidget(covariant CityScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedTerrain =
        oldWidget.cityId != widget.cityId ||
        oldWidget.earth != widget.earth ||
        oldWidget.moon != widget.moon ||
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
        !_sameBuildings(oldWidget.legacyBuildings, widget.legacyBuildings) ||
        List.generate(
          widget.plots.length,
          (i) => i,
        ).any((i) => !widget.plots[i].hasSameModel(oldWidget.plots[i]))) {
      _updateModels(landscape: changedTerrain);
    }
    if (widget.buildingPlacementMode &&
        widget.selectedPlot >= 0 &&
        (!oldWidget.buildingPlacementMode ||
            oldWidget.selectedPlot != widget.selectedPlot)) {
      _showNeighborhood();
    } else if (widget.selectedBuildingId != null &&
        oldWidget.selectedBuildingId != widget.selectedBuildingId) {
      _focusBuilding(widget.selectedBuildingId!);
    }
  }

  bool _sameBuildings(List<SceneBuilding> a, List<SceneBuilding> b) =>
      a.length == b.length &&
      List.generate(
        a.length,
        (i) => a[i].hasSameModel(b[i]),
      ).every((value) => value);

  void _focusBuilding(String id) {
    vm.Vector3? center;
    var reservationFound = false;
    for (final plot in widget.plots) {
      for (final building in plot.buildings) {
        if (building.id == id && (!reservationFound || !building.isBuilt)) {
          center = _terrain.buildingCenter(
            plot.index,
            building.slotIndex,
            occupiesWholePlot: building.occupiesWholePlot,
          );
          reservationFound = !building.isBuilt;
        }
      }
    }
    for (var index = 0; index < widget.legacyBuildings.length; index++) {
      final building = widget.legacyBuildings[index];
      if (building.id == id && !reservationFound) {
        center = _terrain.legacyBuildingCenter(
          index,
          baseLab: id == 'base_lab',
        );
      }
    }
    if (center == null) return;
    _showNeighborhood();
    _panX = center.x;
    _panZ = center.z;
    _clampPan();
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
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -.2),
          radius: .85,
          colors: widget.moon
              ? const [Color(0xff292e3a), Color(0xff080c14)]
              : widget.earth
              ? const [Color(0xff385654), Color(0xff122528)]
              : const [Color(0xff645047), Color(0xff241f24)],
        ),
      ),
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
              onScaleStart: (_) {
                _gestureZoom = _zoom;
                _gestureAzimuth = _azimuth;
              },
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
                  _panX -= (delta.dx * z.dy - delta.dy * z.dx) / det;
                  _panZ -= (x.dx * delta.dy - x.dy * delta.dx) / det;
                }
                if (details.pointerCount > 1) {
                  _azimuth = _gestureAzimuth - details.rotation;
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
                      painter: _MapFallbackPainter(
                        view,
                        widget.plots,
                        widget.legacyBuildings,
                      ),
                    ),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _PlotBoundaryPainter(
                        view: view,
                        plots: widget.plots,
                        selected: widget.selectedPlot,
                        adjacent: widget.adjacentPlots,
                        constructionMode: widget.constructionMode,
                        buildable: widget.buildablePlots,
                      ),
                    ),
                  ),
                  for (final plot in widget.plots)
                    _plotTarget(plot, view, size),
                  ..._buildingTargets(view, size),
                  Positioned(
                    left: 10,
                    bottom: size.width >= 700 ? 10 : null,
                    top: size.width < 700
                        ? (widget.legacyBuildings.isNotEmpty ? 52 : 10)
                        : null,
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
                            size.width < 700
                                ? 'ドラッグで移動'
                                : '地形を選択 · ドラッグで移動 · ピンチ／ホイールで拡大',
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
                    child: _controls(size.width >= 700 ? 40 : 36),
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

  List<Widget> _buildingTargets(CityMapProjection view, Size size) {
    if (_zoom < 1.15) return const [];
    final targets = <Widget>[];
    // A queued relocation keeps the completed origin and reserves its new
    // position. Both models remain visible, with one target at the destination.
    final reservedBuildingIds = {
      for (final plot in widget.plots)
        for (final building in plot.buildings)
          if (!building.isBuilt) building.id,
    };
    final plot = widget.plots
        .where((plot) => plot.index == widget.selectedPlot)
        .firstOrNull;
    if (plot != null &&
        widget.buildingPlacementMode &&
        widget.onBuildingSlotSelected != null) {
      for (final slot in widget.availableBuildingSlots) {
        final center = _terrain.buildingCenter(
          plot.index,
          slot,
          occupiesWholePlot: widget.buildingOccupiesWholePlot,
        );
        final screen = view.camera.worldToScreen(
          center + vm.Vector3(0, .18, 0),
          size,
        );
        if (screen == null) continue;
        final selected = widget.selectedBuildingSlot == slot;
        targets.add(
          Positioned(
            left: screen.dx - 24,
            top: screen.dy - 24,
            child: Semantics(
              button: true,
              selected: selected,
              label: '建設位置${slot == 0 ? 'A' : 'B'}を選ぶ',
              child: Tooltip(
                message: '建設位置 ${slot == 0 ? 'A' : 'B'}',
                child: GestureDetector(
                  key: Key(
                    'building-slot-${widget.cityId}-${plot.index}-$slot',
                  ),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onBuildingSlotSelected!(slot),
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xe61e5869)
                          : const Color(0xd00b1d26),
                      border: Border.all(
                        color: selected
                            ? const Color(0xffffd97e)
                            : const Color(0xff8ac3cf),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      slot == 0 ? 'A' : 'B',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    } else if (plot != null) {
      for (final building in plot.buildings) {
        if (building.isBuilt && reservedBuildingIds.contains(building.id)) {
          continue;
        }
        targets.addAll(
          _buildingTarget(
            building,
            _terrain.buildingCenter(
              plot.index,
              building.slotIndex,
              occupiesWholePlot: building.occupiesWholePlot,
            ),
            view,
            size,
          ),
        );
      }
    }
    if (!widget.buildingPlacementMode) {
      for (var index = 0; index < widget.legacyBuildings.length; index++) {
        final building = widget.legacyBuildings[index];
        if (reservedBuildingIds.contains(building.id)) continue;
        targets.addAll(
          _buildingTarget(
            building,
            _terrain.legacyBuildingCenter(
              index,
              baseLab: building.id == 'base_lab',
            ),
            view,
            size,
          ),
        );
      }
    }
    return targets;
  }

  List<Widget> _buildingTarget(
    SceneBuilding building,
    vm.Vector3 center,
    CityMapProjection view,
    Size size,
  ) {
    if (widget.onBuildingSelected == null) return const [];
    final screen = view.camera.worldToScreen(
      center + vm.Vector3(0, .25, 0),
      size,
    );
    if (screen == null ||
        screen.dx < 24 ||
        screen.dx > size.width - 24 ||
        screen.dy < 24 ||
        screen.dy > size.height - 24) {
      return const [];
    }
    final selected = widget.selectedBuildingId == building.id;
    final color = selected
        ? const Color(0xffffd97e)
        : building.operational
        ? const Color(0xff8cddd0)
        : const Color(0xffb8c3ca);
    return [
      Positioned(
        left: screen.dx - 24,
        top: screen.dy - 24,
        child: Semantics(
          button: true,
          selected: selected,
          label: '${building.name}を選択',
          child: Tooltip(
            message: building.name,
            child: GestureDetector(
              key: Key('scene-building-${building.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onBuildingSelected!(building.id),
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.topCenter,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: color.withValues(alpha: selected ? 1 : .35),
                    width: selected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  building.workState == SceneWorkState.building
                      ? Icons.construction
                      : building.operational
                      ? Icons.factory_outlined
                      : Icons.pause_circle_outline,
                  color: color,
                  size: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _controls(double targetSize) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xe6102028),
      border: Border.all(color: const Color(0xff6b7b78)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _viewControl('市街', '選んだ区画を近くから表示', () => setState(_showNeighborhood)),
        _viewControl('全域', '都市全体を表示', () => setState(_showOverview)),
        _control(
          targetSize,
          Icons.remove,
          '都市地図を縮小',
          () => setState(() => _setZoom(_zoom - .25)),
        ),
        _control(
          targetSize,
          Icons.add,
          '都市地図を拡大',
          () => setState(() => _setZoom(_zoom + .25)),
        ),
        PopupMenuButton<String>(
          tooltip: '都市地図の視点操作',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 180),
          icon: const Icon(Icons.threed_rotation, size: 19),
          onSelected: (action) => setState(() {
            switch (action) {
              case 'left':
                _azimuth -= math.pi / 6;
              case 'right':
                _azimuth += math.pi / 6;
              case 'reset':
                _resetView();
            }
          }),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'left', child: Text('左へ回転')),
            PopupMenuItem(value: 'right', child: Text('右へ回転')),
            PopupMenuItem(value: 'reset', child: Text('箱庭全体へ戻す')),
          ],
        ),
      ],
    ),
  );

  Widget _viewControl(String label, String tooltip, VoidCallback action) =>
      Tooltip(
        message: tooltip,
        child: TextButton(
          onPressed: action,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xffe4dcc3),
            minimumSize: const Size(44, 40),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            // ButtonStyle replaces the label style, so keep the bundled Web
            // font from the theme when changing only its size.
            textStyle: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontSize: 11),
          ),
          child: Text(label),
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
    required this.constructionMode,
    required this.buildable,
  });
  final CityMapProjection view;
  final List<ScenePlot> plots;
  final int selected;
  final Set<int> adjacent, buildable;
  final bool constructionMode;

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()..style = PaintingStyle.stroke;
    final text = TextPainter(textDirection: TextDirection.ltr);
    // This marks the existing 25-plot development area, not a new territorial
    // ownership rule. Interior shared edges are omitted from the outer line.
    final perimeter = Path();
    final camera = view.camera;
    for (final (a, b) in view.terrain.boundaryEdges(
      plots.map((plot) => plot.index).toSet(),
    )) {
      final start = camera.worldToScreen(a, size)!;
      final end = camera.worldToScreen(b, size)!;
      perimeter
        ..moveTo(start.dx, start.dy)
        ..lineTo(end.dx, end.dy);
    }
    if (constructionMode || selected >= 0) {
      canvas.drawPath(
        perimeter,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 4.0
          ..color = const Color(0x85233129),
      );
      canvas.drawPath(
        perimeter,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.6
          ..color = const Color(0xcad9d6a4),
      );
    }
    for (final plot in plots) {
      final isSelected = plot.index == selected;
      final isAdjacent = adjacent.contains(plot.index);
      final canBuild = constructionMode && buildable.contains(plot.index);
      final color = isSelected
          ? const Color(0xffffdf87)
          : canBuild
          ? const Color(0xb0c1ecbd)
          : isAdjacent
          ? const Color(0x99c6b878)
          : constructionMode
          ? const Color(0x406b7770)
          : const Color(0x182d452f);
      border
        ..color = color
        ..strokeWidth = isSelected
            ? 2.4
            : canBuild || isAdjacent
            ? 1.2
            : .65;
      final polygon = view.polygon(plot.index, size);
      if (isSelected || canBuild) {
        canvas.drawPath(
          polygon,
          Paint()
            ..color = isSelected
                ? const Color(0x20ffdd7c)
                : const Color(0x1232ba7a),
        );
      }
      canvas.drawPath(polygon, border);
      final bounds = polygon.getBounds();
      final center = view.center(plot.index, size);
      if (!isSelected &&
          plot.workState == SceneWorkState.none &&
          !plot.buildings.any(
            (building) => building.workState != SceneWorkState.none,
          )) {
        continue;
      }
      final use = switch (plot.districtId) {
        'housing' => '住宅',
        'campus' || 'mars_lab' => '研究',
        'industry' => '工業',
        'solar' || 'moon_solar' => '発電',
        'spaceport' || 'moon_spaceport' => '宇宙港',
        'moon_outpost' => '月面基地',
        'moon_extractor' => '採取',
        'space_elevator' => '軌道昇降',
        'mars_habitat' => '居住',
        'greenhouse' => '温室',
        'extractor' => '採取',
        _ =>
          plot.buildings.isNotEmpty
              ? '${plot.buildings.length}施設'
              : plot.districtName ?? '',
      };
      final label = switch (plot.workState) {
        SceneWorkState.queued => '予 · $use',
        SceneWorkState.building => '工 · $use',
        SceneWorkState.none =>
          plot.buildings.isNotEmpty
              ? (plot.isDeveloped ? '$use＋${plot.buildings.length}施設' : use)
              : plot.isDeveloped
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
  const _MapFallbackPainter(this.view, this.plots, this.legacyBuildings);
  final CityMapProjection view;
  final List<ScenePlot> plots;
  final List<SceneBuilding> legacyBuildings;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final terrain = view.terrain;
    final camera = view.camera;
    const segments = 96;
    vm.Vector3 edge(int i) {
      final angle = i / segments * math.pi * 2;
      return terrain.surfacePoint(
        math.cos(angle) * terrain.landRadius,
        math.sin(angle) * terrain.landRadius,
      );
    }

    final rim = [for (var i = 0; i < segments; i++) edge(i)];
    for (var i = 0; i < segments; i++) {
      final angle = (i + .5) / segments * math.pi * 2;
      if (math.sin(angle) * math.cos(view.azimuth) +
              math.cos(angle) * math.sin(view.azimuth) <
          0) {
        continue;
      }
      final a = rim[i], b = rim[(i + 1) % segments];
      final side = Path()
        ..addPolygon([
          camera.worldToScreen(a, size)!,
          camera.worldToScreen(b, size)!,
          camera.worldToScreen(
            vm.Vector3(b.x * .98, terrain.baseY, b.z * .98),
            size,
          )!,
          camera.worldToScreen(
            vm.Vector3(a.x * .98, terrain.baseY, a.z * .98),
            size,
          )!,
        ], true);
      canvas.drawPath(
        side,
        paint
          ..color = terrain.moon
              ? const Color(0xff60636b)
              : terrain.earth
              ? const Color(0xff80684c)
              : const Color(0xff784c36),
      );
    }
    final top = Path()
      ..addPolygon([
        for (final point in rim) camera.worldToScreen(point, size)!,
      ], true);
    canvas.drawPath(
      top,
      paint
        ..color = terrain.moon
            ? const Color(0xff9699a0)
            : terrain.earth
            ? const Color(0xff7c9654)
            : const Color(0xffa45a3a),
    );
    if (terrain.hasRiver) {
      final north = <Offset>[], south = <Offset>[];
      for (var i = 0; i <= 96; i++) {
        final x = -terrain.landRadius + terrain.landRadius * 2 * i / 96;
        final z = terrain.riverCenterZ(x);
        for (final (bank, sign) in [(north, -1), (south, 1)]) {
          bank.add(
            camera.worldToScreen(
              vm.Vector3(
                x,
                CityTerrain.waterLevel,
                z + sign * terrain.riverHalfWidth(x),
              ),
              size,
            )!,
          );
        }
      }
      canvas.save();
      canvas.clipPath(top);
      canvas.drawPath(
        Path()..addPolygon([...north, ...south.reversed], true),
        paint..color = const Color(0xff439796),
      );
      canvas.restore();
    }
    for (final plot in plots) {
      final center = view.terrain.center(plot.index);
      paint.color = view.terrain.colorAt(center.x, center.z);
      canvas.drawPath(view.polygon(plot.index, size), paint);
      if (plot.isDeveloped) {
        final screen = plot.buildings.isEmpty
            ? view.center(plot.index, size)
            : camera.worldToScreen(
                terrain.buildingCenter(plot.index, 0),
                size,
              )!;
        paint.color = const Color(0xffa8beb6);
        canvas.drawRect(
          Rect.fromCenter(
            center: screen,
            width: (8 + plot.level * 3) * (plot.buildings.isEmpty ? 1 : .55),
            height: (7 + plot.level * 3) * (plot.buildings.isEmpty ? 1 : .75),
          ),
          paint,
        );
      }
      for (final building in plot.buildings) {
        _paintBuilding(
          canvas,
          size,
          building,
          terrain.buildingCenter(
            plot.index,
            building.slotIndex,
            occupiesWholePlot: building.occupiesWholePlot,
          ),
        );
      }
    }
    for (var index = 0; index < legacyBuildings.length; index++) {
      final building = legacyBuildings[index];
      _paintBuilding(
        canvas,
        size,
        building,
        terrain.legacyBuildingCenter(index, baseLab: building.id == 'base_lab'),
        legacy: true,
      );
    }
  }

  void _paintBuilding(
    Canvas canvas,
    Size size,
    SceneBuilding building,
    vm.Vector3 center, {
    bool legacy = false,
  }) {
    final scale = legacy
        ? .48
        : building.occupiesWholePlot
        ? .90
        : .48;
    final paint = Paint();
    Offset point(double x, double y, double z) => view.camera.worldToScreen(
      center + vm.Vector3(x * scale, y * scale, z * scale),
      size,
    )!;
    void face(List<Offset> points, Color color) {
      canvas.drawPath(Path()..addPolygon(points, true), paint..color = color);
    }

    void box(
      double x,
      double z,
      double width,
      double depth,
      double height,
      Color color,
    ) {
      final l = x - width / 2,
          r = x + width / 2,
          a = z - depth / 2,
          b = z + depth / 2;
      face([
        point(l, 0, b),
        point(r, 0, b),
        point(r, height, b),
        point(l, height, b),
      ], Color.lerp(color, const Color(0xff253540), .30)!);
      face([
        point(r, 0, a),
        point(r, 0, b),
        point(r, height, b),
        point(r, height, a),
      ], Color.lerp(color, const Color(0xff253540), .45)!);
      face([
        point(l, height, a),
        point(r, height, a),
        point(r, height, b),
        point(l, height, b),
      ], color);
    }

    final active = building.operational;
    final accent = active ? const Color(0xff68c7b7) : const Color(0xff8d999d);
    if (building.workState == SceneWorkState.queued) {
      final outline = Path()
        ..addPolygon([
          point(-.6, .04, -.6),
          point(.6, .04, -.6),
          point(.6, .04, .6),
          point(-.6, .04, .6),
        ], true);
      canvas.drawPath(
        outline,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xffdda65c),
      );
      return;
    }
    if (building.workState == SceneWorkState.building) {
      box(0, 0, 1.15, 1.05, .07, const Color(0xff9ba6a6));
      box(
        0,
        0,
        .82,
        .75,
        .22 + building.constructionStage * .18,
        const Color(0xffbd9671),
      );
      for (final x in [-.52, .52]) {
        final a = point(x, 0, -.42), b = point(x, .7, -.42);
        canvas.drawLine(
          a,
          b,
          paint
            ..strokeWidth = 2
            ..color = const Color(0xffe2a55b),
        );
      }
      return;
    }
    box(0, 0, 1.3, 1.24, .04, const Color(0xffa8a694));
    switch (building.catalogId) {
      case 'B01':
        for (final x in [-.27, .27]) {
          box(x, 0, .42, 1.0, .30, const Color(0xff6daba0));
        }
        box(-.51, 0, .18, .85, .22, accent);
      case 'B13':
        box(-.15, -.10, .86, .73, .47, const Color(0xffd3e2e4));
        box(.42, -.12, .23, .56, .30, accent);
        for (final x in [-.43, -.19, .05]) {
          box(x, .36, .16, .14, .17, const Color(0xff4c7181));
        }
      case 'R01':
        box(-.19, .04, .70, .68, .36, const Color(0xff8faeab));
        box(.43, -.29, .10, .10, .88, accent);
        box(.43, -.29, .36, .22, .91, const Color(0xffdce2dd));
      case 'R05':
        box(-.29, .23, .46, .32, .25, accent);
        box(.24, -.21, .10, .10, 1.03, const Color(0xffd5aa67));
        box(-.08, -.40, .69, .18, .19, const Color(0xff8f999d));
      case 'R07':
        box(-.40, -.12, .32, .64, .37, accent);
        for (final z in [-.24, .24]) {
          box(.18, z, .44, .40, .36, const Color(0xffb1c2c9));
        }
      case 'R15':
        box(-.08, -.09, .98, .80, .41, const Color(0xff9faab1));
        for (var i = 0; i < 3; i++) {
          box(-.37 + i * .28, -.11, .22, .69, .49 + i * .03, accent);
        }
      case 'E09':
        for (final x in [-.38, 0.0, .38]) {
          box(x, -.10, .28, .86, .33, accent);
        }
      case 'E10':
        box(-.37, 0, .38, .83, .42, accent);
        box(.14, -.25, .28, .28, .72, const Color(0xffc4d4d6));
        box(.45, .22, .31, .31, .48, const Color(0xffb6b1a4));
      case 'E13':
        box(-.42, -.14, .27, .65, .37, accent);
        for (final z in [-.26, .25]) {
          box(.17, z, .58, .25, .29, const Color(0xff7f969e));
        }
      case 'M08':
        box(0, -.07, 1.03, .76, .61, accent);
        box(.11, .30, .43, .23, .18, const Color(0xffcf9151));
      case 'M25':
        box(-.13, -.19, .96, .80, .60, const Color(0xff9dabb1));
        if (building.vehiclePresent) box(.12, .41, .75, .19, .21, accent);
      case 'M13':
        box(-.15, -.19, .95, .80, .60, const Color(0xffa5b0b8));
        if (building.vehiclePresent) box(.29, .40, .28, .28, .37, accent);
      default:
        box(0, 0, .70, .65, .43, accent);
    }
    final lamp = point(.56, .36, .53);
    canvas.drawCircle(
      lamp,
      1.8,
      paint..color = active ? const Color(0xffc8fff0) : const Color(0xff59636a),
    );
  }

  @override
  bool shouldRepaint(covariant _MapFallbackPainter oldDelegate) => true;
}
