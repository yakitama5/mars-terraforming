import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/game_content.dart';
import '../domain/game_state.dart';
import '../domain/research_frontiers.dart';
import 'strategy_widgets.dart';
import 'research_display.dart';

/// Every edge is sourced from a playable research prerequisite.
class ResearchTree extends StatefulWidget {
  const ResearchTree({
    super.key,
    required this.game,
    required this.selectedId,
    required this.onSelected,
    required this.requirementReasons,
  });
  final GameState game;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final List<String> Function(String) requirementReasons;

  @override
  State<ResearchTree> createState() => _ResearchTreeState();
}

class _ResearchTreeState extends State<ResearchTree> {
  final transformation = TransformationController();
  Size viewportSize = Size.zero;
  Size graphSize = Size.zero;
  String? branchFilter;
  Map<String, Offset> nodePositions = const {};
  Size nodeSize = Size.zero;
  GameState get game => widget.game;
  String get selectedId => widget.selectedId;

  @override
  void initState() {
    super.initState();
    branchFilter = GameContent.tasks[selectedId]!.researchBranch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode(selectedId);
    });
  }

  @override
  void didUpdateWidget(covariant ResearchTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != selectedId &&
        !nodePositions.containsKey(selectedId)) {
      branchFilter = GameContent.tasks[selectedId]!.researchBranch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode(selectedId);
      });
    }
  }

  void _focusNode(String id) {
    final position = nodePositions[id];
    if (position == null || viewportSize.isEmpty || nodeSize.isEmpty) return;
    final scale = ((viewportSize.width - 24) / nodeSize.width).clamp(.8, 1.0);
    transformation.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
        (viewportSize.width - nodeSize.width * scale) / 2 - position.dx * scale,
        (viewportSize.height - nodeSize.height * scale) / 2 -
            position.dy * scale,
        0,
      );
  }

  @override
  void dispose() {
    transformation.dispose();
    super.dispose();
  }

  void _fit() {
    if (viewportSize.width <= 24 || viewportSize.height <= 16) return;
    final scale = math
        .min(
          (viewportSize.width - 24) / graphSize.width,
          (viewportSize.height - 16) / graphSize.height,
        )
        .clamp(.01, 1.0);
    transformation.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
        (viewportSize.width - graphSize.width * scale) / 2,
        (viewportSize.height - graphSize.height * scale) / 2,
        0,
      );
  }

  @override
  Widget build(BuildContext context) {
    final allResearch = GameContent.tasks.values
        .where((task) => task.unique)
        .toList();
    final visibleIds = <String>{};
    void includePrerequisites(TaskDefinition task) {
      if (!visibleIds.add(task.id)) return;
      for (final id in task.prerequisiteIds) {
        includePrerequisites(GameContent.tasks[id]!);
      }
    }

    for (final task in allResearch) {
      if (branchFilter == null || task.researchBranch == branchFilter) {
        includePrerequisites(task);
      }
    }
    final research = allResearch
        .where((task) => visibleIds.contains(task.id))
        .toList();
    final depths = <String, int>{};
    int depth(TaskDefinition task) => depths.putIfAbsent(task.id, () {
      var result = 0;
      for (final id in task.prerequisiteIds) {
        final candidate = depth(GameContent.tasks[id]!) + 1;
        if (candidate > result) result = candidate;
      }
      return result;
    });
    final stages = research.map(depth).toSet().toList()..sort();
    final branches = research
        .map((task) => task.researchBranch)
        .toSet()
        .toList();
    final textScale = MediaQuery.textScalerOf(context).scale(13) / 13;
    final nodeWidth = 24.0 + 150.0 * math.max(1.0, textScale);
    final nodeHeight = 24.0 + 102.0 * math.max(1.0, textScale);
    const horizontalGap = 48.0;
    const verticalGap = 32.0;
    final positions = <String, Offset>{};
    // Reserve complete bands per discipline. Optional nodes no longer push
    // themselves into the next discipline's row as the tree grows.
    var rows = 0;
    final bandRows = <String, int>{};
    for (final branch in branches) {
      bandRows[branch] = rows;
      final columnCounts = <int, int>{};
      for (final task in research.where((t) => t.researchBranch == branch)) {
        final column = stages.indexOf(depth(task));
        final slot = columnCounts[column] ?? 0;
        columnCounts[column] = slot + 1;
        positions[task.id] = Offset(
          20 + column * (nodeWidth + horizontalGap),
          60 + (rows + slot) * (nodeHeight + verticalGap),
        );
      }
      rows += columnCounts.values.fold(1, math.max);
      // The extra row gives each discipline its own readable heading.
      rows++;
    }
    final width = stages.length * (nodeWidth + horizontalGap) + 4;
    final height = (rows - 1) * (nodeHeight + verticalGap) + 68;
    graphSize = Size(width, height);
    nodePositions = positions;
    nodeSize = Size(nodeWidth, nodeHeight);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '研究航路',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                key: const Key('research-futures'),
                tooltip: '居住編のその先',
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => const _ResearchFuturesDialog(),
                ),
                icon: const Icon(Icons.auto_awesome_outlined, size: 20),
              ),
              TextButton.icon(
                key: const Key('research-fit'),
                onPressed: () {
                  setState(() => branchFilter = null);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _fit();
                  });
                },
                icon: const Icon(Icons.zoom_out_map, size: 16),
                label: const Text(
                  '全体',
                  semanticsLabel: '全体表示',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              IconButton(
                key: const Key('research-reset-zoom'),
                tooltip: '選択した研究を読みやすい大きさで表示',
                onPressed: () => _focusNode(selectedId),
                icon: const Icon(Icons.center_focus_strong, size: 20),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 38,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final entry in const <String?, String>{
                  null: 'すべて',
                  '都市・産業': '産業',
                  '輸送': '輸送',
                  '居住・現地生産': '暮らし',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      key: Key('research-filter-${entry.key ?? 'all'}'),
                      label: Text(entry.value),
                      selected: branchFilter == entry.key,
                      onSelected: (_) {
                        final target =
                            entry.key == null ||
                                GameContent.tasks[selectedId]!.researchBranch ==
                                    entry.key
                            ? selectedId
                            : allResearch
                                  .firstWhere(
                                    (task) => task.researchBranch == entry.key,
                                  )
                                  .id;
                        setState(() => branchFilter = entry.key);
                        widget.onSelected(target);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _focusNode(target);
                        });
                      },
                      visualDensity: VisualDensity.compact,
                      labelStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              viewportSize = constraints.biggest;
              return ClipRect(
                child: InteractiveViewer(
                  key: const Key('research-tree-canvas'),
                  transformationController: transformation,
                  constrained: false,
                  minScale: .01,
                  maxScale: 1.6,
                  boundaryMargin: const EdgeInsets.all(30),
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: CustomPaint(
                      painter: _ResearchConnections(
                        research,
                        positions,
                        game.research,
                        nodeWidth,
                        nodeHeight,
                      ),
                      child: Stack(
                        children: [
                          for (final (index, stage) in stages.indexed)
                            Positioned(
                              left: 20 + index * (nodeWidth + horizontalGap),
                              top: 8,
                              child: Text(
                                '段階 ${stage + 1}',
                                style: const TextStyle(
                                  color: strategyMuted,
                                  fontSize: 11,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          for (final entry in bandRows.entries)
                            Positioned(
                              left: 20,
                              top:
                                  36 + entry.value * (nodeHeight + verticalGap),
                              child: Text(
                                entry.key,
                                style: const TextStyle(
                                  color: strategyBlue,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          for (final task in research)
                            Positioned(
                              left: positions[task.id]!.dx,
                              top: positions[task.id]!.dy,
                              width: nodeWidth,
                              height: nodeHeight,
                              child: _node(task),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Text(
            '${game.research.length}/${allResearch.length}研究済み · 線は前提研究${branchFilter == null ? ' · ドラッグで移動' : ' · 前提分野も表示'}',
            style: const TextStyle(color: strategyMuted, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _node(TaskDefinition task) {
    final status = researchStatus(
      game,
      task,
      widget.requirementReasons(task.id),
    );
    final plan = game.plans
        .where((plan) => plan.taskId == task.id && !plan.isFinished)
        .firstOrNull;
    final paused = plan != null && !game.facilities[task.facilityId]!;
    final displayStatus = paused ? '$status・休止' : status;
    final queue = game.upcomingPlansFor(task.facilityId);
    final queueIndex = plan == null ? -1 : queue.indexOf(plan);
    final detail = plan?.status == 'running'
        ? '残り ${gameDuration(plan!.remainingMs)}${paused ? ' · 再開待ち' : ''}'
        : plan != null
        ? '予約 ${queueIndex + 1}番目 · ${plan.stopReason.isEmpty ? '開始待ち' : plan.stopReason}'
        : task.researchPromise.isNotEmpty
        ? task.researchPromise
        : researchUnlockSummary(game, task);
    final color = status == '研究済み'
        ? strategyBenefit
        : status == '研究中' || status == '予約済み'
        ? strategyWarning
        : status == '研究可能'
        ? strategyBlue
        : strategyMuted;
    return Semantics(
      key: Key('research-semantics-${task.id}'),
      container: true,
      excludeSemantics: true,
      button: true,
      selected: task.id == selectedId,
      label: '${task.name}、$displayStatus、$detail',
      onTap: () => widget.onSelected(task.id),
      child: Material(
        color: task.id == selectedId ? strategySelected : strategyPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: task.id == selectedId ? strategyBlue : strategyLine,
            width: task.id == selectedId ? 2 : 1,
          ),
        ),
        child: InkWell(
          key: Key('research-node-${task.id}'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => widget.onSelected(task.id),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      status == '研究済み'
                          ? Icons.check_circle_outline
                          : status == '未解放'
                          ? Icons.lock_outline
                          : Icons.science_outlined,
                      size: 15,
                      color: color,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        displayStatus,
                        style: TextStyle(fontSize: 11, color: color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Expanded(
                  child: Text(
                    task.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                  ),
                ),
                Tooltip(
                  message: detail,
                  child: Text(
                    detail,
                    key: Key('research-progress-${task.id}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: paused ? strategyCopper : strategyMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
  if (plans.isNotEmpty) return '予約済み';
  if (unmetRequirements.isNotEmpty ||
      task.prerequisiteIds.any((id) => !game.research.contains(id))) {
    return '未解放';
  }
  return '研究可能';
}

class _ResearchConnections extends CustomPainter {
  _ResearchConnections(
    this.tasks,
    this.positions,
    this.completed,
    this.nodeWidth,
    this.nodeHeight,
  );
  final List<TaskDefinition> tasks;
  final Map<String, Offset> positions;
  final Set<String> completed;
  final double nodeWidth;
  final double nodeHeight;

  @override
  void paint(Canvas canvas, Size size) {
    for (final task in tasks) {
      final target = positions[task.id]! + Offset(0, nodeHeight / 2);
      for (final prerequisite in task.prerequisiteIds) {
        final position = positions[prerequisite];
        if (position == null) continue;
        final source = position + Offset(nodeWidth, nodeHeight / 2);
        final paint = Paint()
          ..color = completed.contains(prerequisite)
              ? strategyMint.withValues(alpha: .65)
              : strategyLine
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        final middle = (source.dx + target.dx) / 2;
        canvas.drawPath(
          Path()
            ..moveTo(source.dx, source.dy)
            ..cubicTo(
              middle,
              source.dy,
              middle,
              target.dy,
              target.dx,
              target.dy,
            ),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(target.dx - 5, target.dy - 4)
            ..lineTo(target.dx, target.dy)
            ..lineTo(target.dx - 5, target.dy + 4),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ResearchConnections oldDelegate) => true;
}

class _ResearchFuturesDialog extends StatelessWidget {
  const _ResearchFuturesDialog();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('居住編のその先'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ドームや地下都市の物語から、さらに遠い未来へ。'
              'いま育てる技術が、どんな暮らしにつながるか。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            const Text(
              '以下は将来の物語案です。到達判定・報酬はまだありません。',
              style: TextStyle(fontSize: 12, color: strategyMuted),
            ),
            const SizedBox(height: 12),
            for (final frontier in ResearchFrontiers.destinations)
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
                    '関連する研究：${frontier.researchIds.map((id) => GameContent.tasks[id]!.name).join('・')}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: strategyBenefit,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    frontier.nextChallenge,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    frontier.scientificBoundary,
                    style: const TextStyle(fontSize: 11, color: strategyMuted),
                  ),
                ],
              ),
            const SizedBox(height: 4),
            const Text(
              '全球の屋外居住には、気温だけでなく大気・水・放射線への防護と維持能力が必要です。'
              '閉鎖居住の完成や、この研究の完了だけでは達成しません。',
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
