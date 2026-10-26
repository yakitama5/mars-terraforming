import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/game_content.dart';
import '../domain/game_state.dart';
import '../domain/research_frontiers.dart';
import 'research_display.dart';
import 'research_theme.dart';
import 'research_tree_layout.dart';
import 'strategy_widgets.dart';

/// Hidden technology never affects canvas bounds, connections, semantics, or
/// the fit operation. Only domain-discovered technology enters this widget.
class ResearchTree extends StatefulWidget {
  const ResearchTree({
    super.key,
    required this.game,
    required this.selectedId,
    required this.onSelected,
    required this.requirementReasons,
    this.controlsVisible = true,
    this.onSelectionCleared,
  });

  final GameState game;
  final bool controlsVisible;
  final String? selectedId;
  final VoidCallback? onSelectionCleared;
  final ValueChanged<String> onSelected;
  final List<String> Function(String) requirementReasons;

  @override
  State<ResearchTree> createState() => _ResearchTreeState();
}

class _ResearchTreeState extends State<ResearchTree>
    with TickerProviderStateMixin {
  final transformation = TransformationController();
  late final _growth = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
    value: 1,
  );
  late final _camera = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  Animation<Matrix4>? _cameraPath;
  late ResearchField _field;
  late Set<String> _knownResearch;
  late Set<String> _knownDiscovered;
  late String _worldId;
  final List<String> _revealOrder = [];
  Set<String> _newNodes = {};
  Set<String> _unlockedNodes = {};
  Size _viewportSize = Size.zero;
  Size _graphSize = Size.zero;
  Size _nodeSize = Size.zero;
  Map<String, Offset> _positions = const {};
  String? _cameraAnchorId;

  GameState get game => widget.game;
  ResearchTechnology? _technology(String? id) =>
      ResearchCatalog.technologies[id];

  @override
  void initState() {
    super.initState();
    _captureWorld();
    _field = _technology(widget.selectedId)?.field ?? ResearchField.mechanics;
    _camera.addListener(_moveCamera);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusSelection(animate: false);
      }
    });
  }

  void _captureWorld() {
    _cameraAnchorId = null;
    _worldId = game.worldId;
    _knownResearch = Set.of(game.research);
    _knownDiscovered = Set.of(game.discoveredResearchIds);
    _revealOrder
      ..clear()
      ..addAll(_knownDiscovered);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _growth.value = 1;
      if (_camera.isAnimating && _cameraPath != null) {
        _camera.value = 1;
      }
    }
  }

  @override
  void didUpdateWidget(covariant ResearchTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_worldId != game.worldId) {
      _captureWorld();
      _newNodes = {};
      _unlockedNodes = {};
      _growth.value = 1;
    } else {
      final discovered = game.discoveredResearchIds;
      final newNodes = discovered.difference(_knownDiscovered);
      final unlocked = game.research.difference(_knownResearch);
      if (newNodes.isNotEmpty || unlocked.isNotEmpty) {
        _newNodes = newNodes;
        _unlockedNodes = unlocked;
        _revealOrder.addAll(newNodes);
        if (MediaQuery.disableAnimationsOf(context)) {
          _growth.value = 1;
        } else {
          _growth.forward(from: 0);
        }
        if (newNodes.isNotEmpty && unlocked.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _focusGrowth();
          });
        }
      }
      _knownDiscovered = Set.of(discovered);
      _knownResearch = Set.of(game.research);
    }
    final selection = _technology(widget.selectedId);
    if (oldWidget.selectedId != widget.selectedId &&
        selection != null &&
        game.isResearchDiscovered(selection.id)) {
      _field = selection.field;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusSelection();
      });
    }
  }

  @override
  void dispose() {
    _camera.removeListener(_moveCamera);
    _camera.dispose();
    _growth.dispose();
    transformation.dispose();
    super.dispose();
  }

  void _moveCamera() {
    final path = _cameraPath;
    if (path != null) transformation.value = path.value;
  }

  void _setCamera(Matrix4 target, {bool animate = true}) {
    if (!animate || MediaQuery.disableAnimationsOf(context)) {
      _camera.stop();
      transformation.value = target;
      return;
    }
    _cameraPath = Matrix4Tween(
      begin: transformation.value.clone(),
      end: target,
    ).animate(CurvedAnimation(parent: _camera, curve: Curves.easeInOutCubic));
    _camera.forward(from: 0);
  }

  void _focusSelection({bool animate = true}) {
    if (_positions.isEmpty) return;
    _focusNode(
      _positions.containsKey(widget.selectedId)
          ? widget.selectedId!
          : _positions.keys.first,
      animate: animate,
    );
  }

  void _focusNode(String id, {bool animate = true}) {
    final position = _positions[id];
    if (position == null || _viewportSize.isEmpty || _nodeSize.isEmpty) return;
    _cameraAnchorId = id;
    final scale = math
        .min(
          (_viewportSize.width - 36) / _nodeSize.width,
          (_viewportSize.height - 28) / _nodeSize.height,
        )
        .clamp(.85, 1.0);
    _setCamera(
      Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(
        (_viewportSize.width - _nodeSize.width * scale) / 2 -
            position.dx * scale,
        (_viewportSize.height - _nodeSize.height * scale) / 2 -
            position.dy * scale,
        0,
      ),
      animate: animate,
    );
  }

  void _fitDiscovered() {
    if (_viewportSize.isEmpty || _graphSize.isEmpty) return;
    final scale = math
        .min(
          (_viewportSize.width - 28) / _graphSize.width,
          (_viewportSize.height - 24) / _graphSize.height,
        )
        .clamp(.01, 1.0);
    _setCamera(
      Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(
        (_viewportSize.width - _graphSize.width * scale) / 2,
        (_viewportSize.height - _graphSize.height * scale) / 2,
        0,
      ),
    );
  }

  void _focusGrowth() {
    final sources = _unlockedNodes.where(_positions.containsKey).toList();
    final targets = _newNodes.where(_positions.containsKey).toList();
    if (sources.isEmpty || targets.isEmpty || _viewportSize.isEmpty) return;
    final source = sources.contains(widget.selectedId)
        ? widget.selectedId!
        : sources.first;
    final target = targets.firstWhere(
      (id) =>
          GameContent.researchConnectionParentIds(_technology(id)!)
              .contains(source),
      orElse: () => targets.first,
    );
    final bounds =
        (Rect.fromLTWH(
              _positions[source]!.dx,
              _positions[source]!.dy,
              _nodeSize.width,
              _nodeSize.height,
            ).expandToInclude(
              Rect.fromLTWH(
                _positions[target]!.dx,
                _positions[target]!.dy,
                _nodeSize.width,
                _nodeSize.height,
              ),
            ))
            .inflate(18);
    final scale = math
        .min(
          _viewportSize.width / bounds.width,
          _viewportSize.height / bounds.height,
        )
        .clamp(.85, 1.0);
    if (bounds.width * scale > _viewportSize.width ||
        bounds.height * scale > _viewportSize.height) {
      _focusNode(target);
      return;
    }
    _setCamera(
      Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(
        _viewportSize.width / 2 - bounds.center.dx * scale,
        _viewportSize.height / 2 - bounds.center.dy * scale,
        0,
      ),
    );
  }

  List<ResearchTechnology> _visibleTechnologies(ResearchField field) =>
      _revealOrder
          .where(game.discoveredResearchIds.contains)
          .map(_technology)
          .whereType<ResearchTechnology>()
          .where(
            (technology) =>
                technology.field == field && technology.isPurchasable,
          )
          .toList();

  void _selectField(ResearchField field) {
    final candidates = _visibleTechnologies(field);
    if (candidates.isEmpty) return;
    final changed = _field != field;
    setState(() => _field = field);
    if (changed) widget.onSelectionCleared?.call();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusSelection();
    });
  }

  @override
  Widget build(BuildContext context) {
    final technologies = _visibleTechnologies(_field);
    final textScale = MediaQuery.textScalerOf(context).scale(13) / 13;
    final nodeWidth = 212.0 * math.max(1.0, textScale);
    final compact = MediaQuery.sizeOf(context).height < 450;
    final nodeHeight = (compact ? 144.0 : 164.0) * math.max(1.0, textScale);
    final layout = ResearchTreeLayout.calculate(
      technologies: technologies,
      nodeSize: Size(nodeWidth, nodeHeight),
    );
    final positions = layout.positions;
    _graphSize = layout.size;
    _positions = positions;
    _nodeSize = Size(nodeWidth, nodeHeight);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: _field.shadowColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.controlsVisible) _header(),
            if (widget.controlsVisible) _fieldPicker(),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ResearchArtwork(
                    key: ValueKey('research-background-${_field.name}'),
                    field: _field,
                    alignment: Alignment.centerRight,
                    opacity: .42,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xe6081728), Color(0xb3081728)],
                      ),
                    ),
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final previousSize = _viewportSize;
                      _viewportSize = constraints.biggest;
                      if (previousSize != _viewportSize) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            final anchor = widget.selectedId ?? _cameraAnchorId;
                            if (anchor != null &&
                                _positions.containsKey(anchor)) {
                              _focusNode(anchor, animate: false);
                            } else {
                              _focusSelection(animate: false);
                            }
                          }
                        });
                      }
                      return ClipRect(
                        child: InteractiveViewer(
                          key: const Key('research-tree-canvas'),
                          transformationController: transformation,
                          constrained: false,
                          minScale: .01,
                          maxScale: 1.8,
                          boundaryMargin: const EdgeInsets.all(140),
                          onInteractionStart: (_) => _camera.stop(),
                          child: SizedBox.fromSize(
                            size: _graphSize,
                            child: AnimatedBuilder(
                              animation: _growth,
                              builder: (context, _) => CustomPaint(
                                painter: _ResearchConnections(
                                  technologies: technologies,
                                  layout: layout,
                                  completed: game.research,
                                  newNodes: _newNodes,
                                  unlockedNodes: _unlockedNodes,
                                  nodeSize: _nodeSize,
                                  field: _field,
                                  progress: _growth.value,
                                ),
                                child: Stack(
                                  children: [
                                    Positioned(
                                      left: layout.seed.dx - 20,
                                      top: layout.seed.dy - 20,
                                      child: _knowledgeSeed(),
                                    ),
                                    for (final technology in technologies)
                                      Positioned(
                                        key: ValueKey(
                                          'research-position-${technology.id}',
                                        ),
                                        left: positions[technology.id]!.dx,
                                        top: positions[technology.id]!.dy,
                                        width: nodeWidth,
                                        height: nodeHeight,
                                        child: _growingNode(technology),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  _unlockAnnouncement(),
                ],
              ),
            ),
            if (widget.controlsVisible)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  compact ? 3 : 6,
                  12,
                  compact ? 3 : 8,
                ),
                child: Text(
                  '右へ研究が深まる · ドラッグで枝をたどる',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _field.color.withValues(alpha: .8),
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header() => SizedBox(
    height: MediaQuery.sizeOf(context).height < 450
        ? MediaQuery.textScalerOf(context).scale(14) > 18
              ? 64
              : 48
        : 69,
    child: Stack(
      fit: StackFit.expand,
      children: [
        ResearchArtwork(
          field: _field,
          alignment: Alignment.centerRight,
          opacity: .74,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xff081728),
                _field.shadowColor.withValues(alpha: .5),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12, right: 4),
          child: Row(
            children: [
              Icon(_field.icon, size: 25, color: _field.color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _field.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        color: _field.color,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${formatResearchPoints(game.researchPoints)} RP · '
                      '${formatResearchPoints(game.researchPointsPerMinute)} RP/分',
                      key: const Key('research-point-balance'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: strategyText),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('research-futures'),
                tooltip: 'いまの知見から描く未来',
                visualDensity: VisualDensity.compact,
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => _ResearchFuturesDialog(game: game),
                ),
                icon: const Icon(Icons.auto_awesome_outlined, size: 19),
              ),
              IconButton(
                key: const Key('research-fit'),
                tooltip: '発見した範囲を表示',
                visualDensity: VisualDensity.compact,
                onPressed: _fitDiscovered,
                icon: const Icon(Icons.zoom_out_map, size: 19),
              ),
              IconButton(
                key: const Key('research-reset-zoom'),
                tooltip: widget.selectedId == null ? '入口の研究へ寄る' : '選択した研究へ戻る',
                visualDensity: VisualDensity.compact,
                onPressed: _focusSelection,
                icon: const Icon(Icons.center_focus_strong, size: 19),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _fieldPicker() => SizedBox(
    height: 44,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          for (final field in ResearchField.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: Key('research-filter-${field.name}'),
                avatar: ClipOval(
                  child: SizedBox.square(
                    dimension: 22,
                    child: ResearchArtwork(field: field),
                  ),
                ),
                label: Text(field.label),
                selected: _field == field,
                onSelected: (_) => _selectField(field),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                selectedColor: field.shadowColor,
                side: BorderSide(
                  color: _field == field ? field.color : strategyLine,
                ),
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _field == field ? field.color : strategyMuted,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _knowledgeSeed() => ExcludeSemantics(
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _field.shadowColor,
        border: Border.all(color: _field.color.withValues(alpha: .6)),
        boxShadow: [
          BoxShadow(color: _field.color.withValues(alpha: .15), blurRadius: 20),
        ],
      ),
      child: Icon(_field.icon, size: 21, color: _field.color),
    ),
  );

  Widget _growingNode(ResearchTechnology technology) {
    final progress = _newNodes.contains(technology.id)
        ? Curves.easeOutCubic.transform(
            ((_growth.value - .23) / .77).clamp(0.0, 1.0),
          )
        : 1.0;
    return Opacity(
      opacity: progress,
      child: Transform.translate(
        offset: Offset(-24 * (1 - progress), 8 * (1 - progress)),
        child: Transform.scale(
          scale: .82 + .18 * progress,
          alignment: Alignment.centerLeft,
          child: _node(technology),
        ),
      ),
    );
  }

  Widget _node(ResearchTechnology technology) {
    final task = GameContent.tasks[technology.id]!;
    final status = researchStatus(
      game,
      task,
      widget.requirementReasons(task.id),
    );
    final complete = game.research.contains(task.id);
    final selected = task.id == widget.selectedId;
    final cost = GameContent.researchPointCost(task.id);
    final color = complete ? strategyBenefit : _field.color;
    final pulse = _unlockedNodes.contains(task.id)
        ? math.sin(_growth.value * math.pi) * (1 - _growth.value)
        : 0.0;
    final plan = game.plans
        .where((plan) => plan.taskId == task.id && !plan.isFinished)
        .firstOrNull;
    final paused = plan != null && !game.facilities[task.facilityId]!;
    final displayStatus = paused ? '$status・休止' : status;
    final queueIndex = plan == null
        ? -1
        : game.upcomingPlansFor(task.facilityId).indexOf(plan);
    final detail = plan?.status == 'running'
        ? '残り ${gameDuration(plan!.remainingMs)}${paused ? ' · 再開待ち' : ''}'
        : plan != null
        ? plan.requiresManualStart
              ? '要着手 · 条件を確認して解放'
              : '待機 ${queueIndex + 1}番目 · ${plan.stopReason}'
        : researchUnlockSummary(game, task);
    return Semantics(
      key: Key('research-semantics-${task.id}'),
      container: true,
      excludeSemantics: true,
      button: true,
      selected: selected,
      label: plan != null
          ? '${task.name}、$displayStatus、$detail'
          : '${task.name}、$status、${complete ? '解放済み' : '$cost RP'}、$detail',
      onTap: () => widget.onSelected(task.id),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            if (selected || pulse > 0)
              BoxShadow(
                color: color.withValues(alpha: .16 + pulse * .4),
                blurRadius: 18 + pulse * 30,
                spreadRadius: pulse * 5,
              ),
          ],
        ),
        child: Material(
          color: strategyPanel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(
              color: selected
                  ? color
                  : color.withValues(alpha: complete ? .55 : .28),
              width: selected ? 1.8 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: Key('research-node-${task.id}'),
            onTap: () => widget.onSelected(task.id),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ResearchArtwork(
                  key: Key('research-card-art-${task.id}'),
                  field: technology.field,
                  alignment: technology.field.cardAlignment,
                  opacity: complete ? .4 : .28,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xe6102639),
                        technology.field.shadowColor.withValues(alpha: .72),
                        const Color(0xe3081728),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              technology.branch,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: technology.field.color,
                                fontSize: 9,
                                letterSpacing: .5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            complete
                                ? Icons.check_circle_rounded
                                : Icons.science_outlined,
                            color: color,
                            size: 15,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        task.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: strategyText,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        detail,
                        key: Key('research-progress-${task.id}'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: strategyMuted,
                          fontSize: 10,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayStatus,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: color, fontSize: 10),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            complete ? '解放済み' : '$cost RP',
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _unlockAnnouncement() {
    final unlocked = _unlockedNodes
        .map(_technology)
        .whereType<ResearchTechnology>()
        .where((technology) => technology.field == _field)
        .toList();
    if (unlocked.isEmpty) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _growth,
      builder: (context, _) {
        final t = _growth.value;
        if (t >= 1) return const SizedBox.shrink();
        final opacity = math.min(t * 8, (1 - t) * 5).clamp(0.0, 1.0);
        return Positioned(
          top: 10,
          left: 12,
          right: 12,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: Semantics(
                liveRegion: true,
                label: '${unlocked.last.name}を解放しました',
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xf20b2334),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _field.color.withValues(alpha: .6),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome, color: _field.color, size: 20),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            '${unlocked.last.name}を解放',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _field.color,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String researchStatus(
  GameState game,
  TaskDefinition task, [
  List<String> unmetRequirements = const [],
]) {
  if (game.research.contains(task.id)) return '研究済み';
  final plans = game.plans.where(
    (plan) => plan.taskId == task.id && !plan.isFinished,
  );
  if (plans.any((plan) => plan.status == 'running')) return '研究中';
  if (plans.any((plan) => plan.requiresManualStart)) return '要着手';
  if (plans.isNotEmpty) return '待機中';
  if (!game.isResearchDiscovered(task.id)) return '未発見';
  if (unmetRequirements.isNotEmpty) return '条件未達';
  return game.researchWaitMs(task.id) == 0 ? '研究可能' : 'RP待ち';
}

class _ResearchConnections extends CustomPainter {
  _ResearchConnections({
    required this.technologies,
    required this.layout,
    required this.completed,
    required this.newNodes,
    required this.unlockedNodes,
    required this.nodeSize,
    required this.field,
    required this.progress,
  });

  final List<ResearchTechnology> technologies;
  final ResearchTreeLayout layout;
  Map<String, Offset> get positions => layout.positions;
  final Set<String> completed, newNodes, unlockedNodes;
  final Size nodeSize;
  final ResearchField field;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    for (final bounds in layout.branchBounds.values) {
      final frame = RRect.fromRectAndRadius(bounds, const Radius.circular(24));
      canvas.drawRRect(
        frame,
        Paint()..color = field.color.withValues(alpha: .025),
      );
      canvas.drawRRect(
        frame,
        Paint()
          ..color = field.color.withValues(alpha: .13)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );
    }
    final seed = layout.seed + const Offset(20, 0);
    for (final technology in technologies) {
      final position = positions[technology.id]!;
      final target = position + Offset(0, nodeSize.height / 2);
      final parents = [...GameContent.researchConnectionParentIds(technology)]
          .where(positions.containsKey)
          .toList();
      if (parents.isEmpty) {
        _drawBranch(canvas, seed, target, technology.id, true);
      } else {
        for (final parent in parents) {
          _drawBranch(
            canvas,
            positions[parent]! + Offset(nodeSize.width, nodeSize.height / 2),
            target,
            technology.id,
            completed.contains(parent),
            primary: layout.primaryParentIds[technology.id] == parent,
          );
        }
      }
      if (unlockedNodes.contains(technology.id) && progress < 1) {
        _drawUnlock(
          canvas,
          position + Offset(nodeSize.width / 2, nodeSize.height / 2),
        );
      }
    }
  }

  void _drawBranch(
    Canvas canvas,
    Offset source,
    Offset target,
    String targetId,
    bool activated, {
    bool primary = true,
  }) {
    final middle = (source.dx + target.dx) / 2;
    final path = Path()..moveTo(source.dx, source.dy);
    if (primary) {
      // Horizontal shoulders share a stem before opening toward each leaf.
      final dy = target.dy - source.dy;
      final bend = math.min(18.0, dy.abs() / 2);
      final direction = dy.sign;
      path
        ..lineTo(middle - bend, source.dy)
        ..quadraticBezierTo(
          middle,
          source.dy,
          middle,
          source.dy + bend * direction,
        )
        ..lineTo(middle, target.dy - bend * direction)
        ..quadraticBezierTo(middle, target.dy, middle + bend, target.dy)
        ..lineTo(target.dx, target.dy);
    } else {
      // Additional prerequisites travel through the gaps outside branch frames.
      final sourceFrame = layout.branchBounds.values.firstWhere(
        (bounds) => bounds.contains(source),
      );
      final targetFrame = layout.branchBounds.values.firstWhere(
        (bounds) => bounds.contains(target),
      );
      final lane = math.min(sourceFrame.top, targetFrame.top) - 10;
      path
        ..lineTo(source.dx + 24, source.dy)
        ..lineTo(source.dx + 24, lane)
        ..lineTo(target.dx - 24, lane)
        ..lineTo(target.dx - 24, target.dy)
        ..lineTo(target.dx, target.dy);
    }
    final growth = newNodes.contains(targetId)
        ? Curves.easeInOutCubic.transform((progress / .8).clamp(0.0, 1.0))
        : 1.0;
    for (final metric in path.computeMetrics()) {
      final length = metric.length * growth;
      if (length <= 0) continue;
      final grownPath = metric.extractPath(0, length);
      if (activated && primary) {
        canvas.drawPath(
          grownPath,
          Paint()
            ..color = field.color.withValues(alpha: .12)
            ..strokeWidth = 7
            ..style = PaintingStyle.stroke
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      final paint = Paint()
        ..color = activated
            ? field.color.withValues(alpha: primary ? .7 : .35)
            : strategyLine
        ..strokeWidth = primary ? (activated ? 3 : 2) : 1
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      if (primary) {
        canvas.drawPath(grownPath, paint);
      } else {
        for (final section in grownPath.computeMetrics()) {
          for (var offset = 0.0; offset < section.length; offset += 12) {
            canvas.drawPath(
              section.extractPath(offset, math.min(offset + 6, section.length)),
              paint,
            );
          }
        }
      }
      if (newNodes.contains(targetId) && progress < .8) {
        final tip = metric.getTangentForOffset(length)?.position;
        if (tip != null) {
          canvas.drawCircle(tip, 4, Paint()..color = field.color);
          canvas.drawCircle(
            tip,
            10,
            Paint()
              ..color = field.color.withValues(alpha: .35)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
          );
        }
      }
    }
  }

  void _drawUnlock(Canvas canvas, Offset center) {
    final t = Curves.easeOut.transform(progress);
    final radius = nodeSize.width * (.35 + t * .42);
    final opacity = (1 - progress) * .5;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = field.color.withValues(alpha: opacity)
        ..strokeWidth = 2 * (1 - progress) + .5
        ..style = PaintingStyle.stroke,
    );
    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi / 6 + .2;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(
        point,
        1 + (1 - progress) * 2,
        Paint()..color = field.color.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ResearchConnections oldDelegate) => true;
}

class _ResearchFuturesDialog extends StatelessWidget {
  const _ResearchFuturesDialog({required this.game});
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final discovered = game.discoveredResearchIds;
    final frontiers = ResearchFrontiers.destinations.where(
      (frontier) => frontier.researchIds.any(game.research.contains),
    );
    return AlertDialog(
      title: const Text('いまの知見から描く未来'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ひとつの発見から、次の可能性へ。研究を進めると、新しい道筋が姿を現します。',
                style: TextStyle(fontSize: 13),
              ),
              if (frontiers.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    'まだ見ぬ未来は、これからの研究の中に。まずは気になる分野の小さな一歩を選びましょう。',
                    style: TextStyle(fontSize: 12, color: strategyMuted),
                  ),
                ),
              for (final frontier in frontiers)
                ExpansionTile(
                  key: Key('research-future-${frontier.id}'),
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    frontier.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: strategyBlue,
                    ),
                  ),
                  subtitle: Text(
                    frontier.promise,
                    style: const TextStyle(fontSize: 12),
                  ),
                  childrenPadding: const EdgeInsets.only(bottom: 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(frontier.scene, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 12),
                    Text(
                      '発見した関連研究：${frontier.researchIds.where(discovered.contains).map((id) => GameContent.tasks[id]!.name).join('・')}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: strategyBenefit,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 14),
              const Text(
                '物語は、ひとつの技術から想像する未来の風景です。',
                style: TextStyle(fontSize: 11, color: strategyMuted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('研究に戻る'),
        ),
      ],
    );
  }
}
