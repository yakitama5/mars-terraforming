import 'dart:math' as math;
import 'dart:ui';

import '../domain/game_content.dart';

/// A left-to-right forest of the knowledge passed by the caller.
/// No undiscovered technology is consulted to reserve space for future leaves.
class ResearchTreeLayout {
  const ResearchTreeLayout._({
    required this.positions,
    required this.primaryParentIds,
    required this.branchBounds,
    required this.seed,
    required this.size,
  });

  final Map<String, Offset> positions;
  final Map<String, String?> primaryParentIds;
  final Map<String, Rect> branchBounds;
  final Offset seed;
  final Size size;

  static const horizontalGap = 112.0;
  static const siblingGap = 56.0;
  static const branchGap = 104.0;
  static const _left = 112.0;
  static const _top = 44.0;
  static const _padding = 24.0;

  factory ResearchTreeLayout.calculate({
    required Iterable<ResearchTechnology> technologies,
    required Size nodeSize,
  }) {
    final known = {
      for (final technology in technologies) technology.id: technology,
    };
    if (known.isEmpty) {
      return const ResearchTreeLayout._(
        positions: {},
        primaryParentIds: {},
        branchBounds: {},
        seed: Offset(40, 44),
        size: Size(80, 88),
      );
    }
    int compare(String a, String b) =>
        known[a]!.catalogId.compareTo(known[b]!.catalogId);
    final ids = known.keys.toList()..sort(compare);
    final parents = {
      for (final id in ids)
        id: GameContent.researchConnectionParentIds(
          known[id]!,
        ).where(known.containsKey).toList()..sort(compare),
    };
    final depths = <String, int>{};
    final visiting = <String>{};
    int depth(String id) {
      if (depths.containsKey(id)) return depths[id]!;
      if (!visiting.add(id)) {
        throw StateError('研究の前提が循環しています: $id');
      }
      var result = 0;
      for (final parent in parents[id]!) {
        result = math.max(result, depth(parent) + 1);
      }
      visiting.remove(id);
      return depths[id] = result;
    }

    final primaryParents = <String, String?>{};
    final children = {for (final id in ids) id: <String>[]};
    for (final id in ids) {
      depth(id);
      final candidates = parents[id]!.toList()
        ..sort((a, b) {
          final byDepth = depths[b]!.compareTo(depths[a]!);
          if (byDepth != 0) return byDepth;
          final branch = known[id]!.branch;
          final byBranch = (known[a]!.branch == branch ? 0 : 1).compareTo(
            known[b]!.branch == branch ? 0 : 1,
          );
          return byBranch != 0 ? byBranch : compare(a, b);
        });
      final parent = candidates.firstOrNull;
      primaryParents[id] = parent;
      if (parent != null) children[parent]!.add(id);
    }
    final roots = ids.where((id) => primaryParents[id] == null).toList()
      ..sort((a, b) {
        final field = known[a]!.field;
        if (field != known[b]!.field) return compare(a, b);
        final order = GameContent.researchRootOrderByField[field]!;
        int rank(String id) {
          final index = order.indexOf(known[id]!.catalogId);
          return index < 0 ? order.length : index;
        }

        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : compare(a, b);
      });

    // Each sibling owns its whole subtree, rather than one slot in a column.
    final heights = <String, double>{};
    double measure(String id) {
      final descendants = children[id]!;
      final height = descendants.isEmpty
          ? nodeSize.height
          : descendants.map(measure).reduce((a, b) => a + b) +
                siblingGap * (descendants.length - 1);
      return heights[id] = math.max(nodeSize.height, height);
    }

    for (final root in roots) {
      measure(root);
    }
    final positions = <String, Offset>{};
    Rect place(String id, double top) {
      final descendants = children[id]!;
      var cursor = top;
      Rect? bounds;
      for (final child in descendants) {
        final childBounds = place(child, cursor);
        bounds = bounds?.expandToInclude(childBounds) ?? childBounds;
        cursor += heights[child]! + siblingGap;
      }
      final centerY = descendants.isEmpty
          ? top + nodeSize.height / 2
          : (positions[descendants.first]!.dy +
                    positions[descendants.last]!.dy +
                    nodeSize.height) /
                2;
      final position = Offset(
        _left + depths[id]! * (nodeSize.width + horizontalGap),
        centerY - nodeSize.height / 2,
      );
      positions[id] = position;
      final rect = position & nodeSize;
      return bounds?.expandToInclude(rect) ?? rect;
    }

    final branchBounds = <String, Rect>{};
    var cursor = _top;
    var right = _left;
    for (final root in roots) {
      final bounds = place(root, cursor).inflate(_padding);
      branchBounds[root] = bounds;
      cursor += heights[root]! + branchGap;
      right = math.max(right, bounds.right);
    }
    final seedY =
        (positions[roots.first]!.dy +
            positions[roots.last]!.dy +
            nodeSize.height) /
        2;
    return ResearchTreeLayout._(
      positions: Map.unmodifiable({
        for (final root in roots) root: positions[root]!,
        for (final id in ids)
          if (primaryParents[id] != null) id: positions[id]!,
      }),
      primaryParentIds: Map.unmodifiable(primaryParents),
      branchBounds: Map.unmodifiable(branchBounds),
      seed: Offset(40, seedY),
      size: Size(right + _padding, cursor - branchGap + _top),
    );
  }
}
