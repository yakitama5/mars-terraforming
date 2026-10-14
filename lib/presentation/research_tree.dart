import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/game_content.dart';
import '../domain/game_state.dart';
import 'strategy_widgets.dart';

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
  GameState get game => widget.game;
  String get selectedId => widget.selectedId;

  @override
  void dispose() {
    transformation.dispose();
    super.dispose();
  }

  void _fit() {
    final scale = math
        .min(
          (viewportSize.width - 24) / graphSize.width,
          (viewportSize.height - 16) / graphSize.height,
        )
        .clamp(.2, 1.0);
    transformation.value = Matrix4.diagonal3Values(scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) {
    final research = GameContent.tasks.values
        .where((task) => task.unique)
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
    const nodeWidth = 174.0;
    const nodeHeight = 100.0;
    const horizontalGap = 48.0;
    const verticalGap = 32.0;
    final positions = <String, Offset>{};
    // Keep related research on one horizontal route. Where several nodes share
    // a stage and route, reserve additional rows instead of hiding a node.
    var rows = branches.length;
    final occupied = <(int, int)>{};
    for (final task in research) {
      final column = stages.indexOf(depth(task));
      var row = branches.indexOf(task.researchBranch);
      while (occupied.contains((column, row))) {
        row++;
      }
      occupied.add((column, row));
      if (row + 1 > rows) rows = row + 1;
      positions[task.id] = Offset(
        20 + column * (nodeWidth + horizontalGap),
        38 + row * (nodeHeight + verticalGap),
      );
    }
    final width = stages.length * (nodeWidth + horizontalGap) + 4;
    final height = rows * (nodeHeight + verticalGap) + 40;
    graphSize = Size(width, height);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: Row(
            children: [
              const Icon(
                Icons.account_tree_outlined,
                color: strategyMint,
                size: 20,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  '技術のつながり',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                key: const Key('research-fit'),
                onPressed: _fit,
                icon: const Icon(Icons.zoom_out_map, size: 16),
                label: const Text('全体表示', style: TextStyle(fontSize: 12)),
              ),
              IconButton(
                key: const Key('research-reset-zoom'),
                tooltip: '研究ツリーを等倍表示',
                onPressed: () => transformation.value = Matrix4.identity(),
                icon: const Icon(Icons.zoom_in, size: 20),
              ),
            ],
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
                  minScale: .2,
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
          padding: EdgeInsets.fromLTRB(18, 9, 18, 12),
          child: Text(
            '${branches.length}分野 · ${game.research.length}/${research.length}研究済み · 線は前提研究 · 全体表示で俯瞰、ドラッグで移動',
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
    final color = status == '研究済み'
        ? strategyMint
        : status == '研究中' || status == '予約済み'
        ? strategyCopper
        : status == '研究可能'
        ? const Color(0xffb0d4ea)
        : strategyMuted;
    return Semantics(
      button: true,
      selected: task.id == selectedId,
      label: '${task.name}、$status',
      child: Material(
        color: task.id == selectedId ? const Color(0xff294648) : strategyPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: task.id == selectedId ? strategyMint : strategyLine,
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
                    Text(status, style: TextStyle(fontSize: 11, color: color)),
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
                Text(
                  '${dollars(task.cost)} · ${gameDuration(game.currentTaskDurationMs(task.id))}',
                  style: const TextStyle(color: strategyMuted, fontSize: 11),
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
