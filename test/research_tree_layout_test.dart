import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/presentation/research_tree_layout.dart';

const _nodeSize = Size(212, 144);

ResearchTechnology _technology(
  String id, {
  String branch = 'shared',
  List<String> parents = const [],
  List<String> alternatives = const [],
}) => ResearchTechnology(
  id: id,
  catalogId: id,
  name: id,
  field: ResearchField.bio,
  branch: branch,
  stage: 0,
  description: '',
  unlockName: '',
  unlockDescription: '',
  tradeoff: '',
  sourceIds: const [],
  unlockKind: ResearchUnlockKind.facility,
  unlockFacilityId: 'lab',
  unlockEffect: ResearchUnlockEffect.research,
  prerequisiteIds: parents,
  alternativePrerequisiteIds: alternatives,
);

List<ResearchTechnology> _twoBranches() => [
  _technology('foundation'),
  _technology('intro_a', branch: 'a', parents: ['foundation']),
  _technology('intro_b', branch: 'b', parents: ['foundation']),
  _technology('middle_a1', branch: 'a', parents: ['intro_a']),
  _technology('middle_a2', branch: 'a', parents: ['intro_a']),
  _technology('middle_b1', branch: 'b', parents: ['intro_b']),
  _technology('middle_b2', branch: 'b', parents: ['intro_b']),
];

Rect _nodeRect(ResearchTreeLayout layout, String id, [Size size = _nodeSize]) =>
    layout.positions[id]! & size;

bool _containsRect(Rect outer, Rect inner) =>
    outer.left <= inner.left &&
    outer.top <= inner.top &&
    outer.right >= inner.right &&
    outer.bottom >= inner.bottom;

void _expectGeometry(
  ResearchTreeLayout layout,
  Iterable<ResearchTechnology> technologies,
  Size nodeSize,
) {
  final nodes = {
    for (final technology in technologies) technology.id: technology,
  };
  expect(layout.positions.keys.toSet(), nodes.keys.toSet());
  expect(layout.primaryParentIds.keys.toSet(), nodes.keys.toSet());
  expect(layout.size.width.isFinite && layout.size.height.isFinite, isTrue);
  expect(layout.size.width, greaterThan(0));
  expect(layout.size.height, greaterThan(0));
  final canvas = Offset.zero & layout.size;
  expect(canvas.contains(layout.seed), isTrue);
  final ids = nodes.keys.toList();
  for (var i = 0; i < ids.length; i++) {
    final id = ids[i];
    final position = layout.positions[id]!;
    expect(position.dx.isFinite && position.dy.isFinite, isTrue, reason: id);
    final rect = _nodeRect(layout, id, nodeSize);
    expect(
      _containsRect(canvas, rect),
      isTrue,
      reason: '$id remains on canvas',
    );
    for (final other in ids.skip(i + 1)) {
      expect(
        rect.overlaps(_nodeRect(layout, other, nodeSize)),
        isFalse,
        reason: '$id and $other must remain separate tappable cards',
      );
    }
    final knownParents = GameContent.researchConnectionParentIds(nodes[id]!)
        .where(nodes.containsKey)
        .toSet();
    final primary = layout.primaryParentIds[id];
    expect(
      primary == null ? knownParents.isEmpty : knownParents.contains(primary),
      isTrue,
      reason: '$id only attaches to a known research connection',
    );
    for (final parent in knownParents) {
      expect(
        layout.positions[id]!.dx,
        greaterThan(layout.positions[parent]!.dx + nodeSize.width),
        reason: '$id follows every known prerequisite from left to right',
      );
    }
  }
  final roots = layout.primaryParentIds.entries
      .where((entry) => entry.value == null)
      .map((entry) => entry.key)
      .toSet();
  expect(layout.branchBounds.keys.toSet(), roots);
  for (final root in roots) {
    final bounds = layout.branchBounds[root]!;
    expect(_containsRect(canvas, bounds), isTrue);
    for (final id in ids) {
      var ancestor = id;
      while (layout.primaryParentIds[ancestor] != null) {
        ancestor = layout.primaryParentIds[ancestor]!;
      }
      if (ancestor == root) {
        expect(
          _containsRect(bounds, _nodeRect(layout, id, nodeSize)),
          isTrue,
          reason: '$root frame contains its known subtree, including $id',
        );
      }
    }
  }
}

void main() {
  test(
    'two levels grow rightward and each parent stays with its own children',
    () {
      final technologies = _twoBranches();
      final layout = ResearchTreeLayout.calculate(
        technologies: technologies,
        nodeSize: _nodeSize,
      );
      _expectGeometry(layout, technologies, _nodeSize);
      final positions = layout.positions;
      expect(positions['intro_a']!.dx, positions['intro_b']!.dx);
      for (final id in ['middle_a1', 'middle_a2', 'middle_b1', 'middle_b2']) {
        expect(positions[id]!.dx, positions['middle_a1']!.dx);
      }
      for (final group in [
        ('foundation', 'intro_a', 'intro_b'),
        ('intro_a', 'middle_a1', 'middle_a2'),
        ('intro_b', 'middle_b1', 'middle_b2'),
      ]) {
        expect(
          positions[group.$1]!.dy,
          closeTo(
            (positions[group.$2]!.dy + positions[group.$3]!.dy) / 2,
            .001,
          ),
          reason: 'parent ${group.$1} is centered on its visible child group',
        );
      }
      expect(layout.primaryParentIds['middle_a2'], 'intro_a');
      expect(layout.primaryParentIds['middle_b1'], 'intro_b');
    },
  );

  test(
    'sibling subtrees occupy separate bands and independent roots have frames',
    () {
      final technologies = [
        ..._twoBranches(),
        _technology('other_root', branch: 'other'),
        _technology('other_child', branch: 'other', parents: ['other_root']),
      ];
      final layout = ResearchTreeLayout.calculate(
        technologies: technologies,
        nodeSize: _nodeSize,
      );
      _expectGeometry(layout, technologies, _nodeSize);
      Rect groupBounds(List<String> ids) => ids
          .map((id) => _nodeRect(layout, id))
          .reduce((left, right) => left.expandToInclude(right));
      final first = groupBounds(['intro_a', 'middle_a1', 'middle_a2']);
      final second = groupBounds(['intro_b', 'middle_b1', 'middle_b2']);
      final gap = first.top < second.top
          ? second.top - first.bottom
          : first.top - second.bottom;
      expect(gap, greaterThanOrEqualTo(56));
      expect(layout.branchBounds, hasLength(2));
      expect(
        layout.branchBounds['foundation']!.overlaps(
          layout.branchBounds['other_root']!,
        ),
        isFalse,
      );
    },
  );

  test(
    'multiple prerequisites use the deepest parent, then the matching branch',
    () {
      final technologies = [
        _technology('root'),
        _technology('one', branch: 'one', parents: ['root']),
        _technology('two', branch: 'two', parents: ['root']),
        _technology('deep', branch: 'one', parents: ['one']),
        _technology('join', branch: 'two', parents: ['two', 'deep']),
        _technology('tie', branch: 'two', parents: ['one', 'two']),
        _technology('alternative', alternatives: ['two', 'deep']),
      ];
      final layout = ResearchTreeLayout.calculate(
        technologies: technologies,
        nodeSize: _nodeSize,
      );
      _expectGeometry(layout, technologies, _nodeSize);
      expect(layout.primaryParentIds['join'], 'deep');
      expect(layout.primaryParentIds['tie'], 'two');
      expect(layout.primaryParentIds['alternative'], 'deep');
      expect(layout.positions['join']!.dx, layout.positions['alternative']!.dx);
      expect(
        layout.positions['join']!.dx,
        greaterThan(layout.positions['tie']!.dx),
      );
    },
  );

  test(
    'restored knowledge and reveal input order produce the same geometry',
    () {
      final technologies = [
        ..._twoBranches(),
        _technology('other_root'),
        _technology('join', parents: ['middle_a1', 'middle_b2']),
      ];
      final expected = ResearchTreeLayout.calculate(
        technologies: technologies,
        nodeSize: _nodeSize,
      );
      final shuffled = List<ResearchTechnology>.of(technologies)
        ..shuffle(math.Random(31));
      for (final input in [technologies.reversed, shuffled]) {
        final actual = ResearchTreeLayout.calculate(
          technologies: input,
          nodeSize: _nodeSize,
        );
        expect(actual.positions, expected.positions);
        expect(actual.primaryParentIds, expected.primaryParentIds);
        expect(actual.branchBounds, expected.branchBounds);
        expect(actual.seed, expected.seed);
        expect(actual.size, expected.size);
      }
    },
  );

  test(
    'unseen prerequisite references create no nodes, frames or reserved space',
    () {
      final known = [
        _technology('root'),
        _technology('child', parents: ['root']),
        _technology('choice', alternatives: ['root']),
      ];
      final withUnseenReferences = [
        known.first,
        _technology('child', parents: ['root', 'nuclear_thermal_propulsion']),
        _technology('choice', alternatives: ['root', 'electric_tugs']),
      ];
      final expected = ResearchTreeLayout.calculate(
        technologies: known,
        nodeSize: _nodeSize,
      );
      final actual = ResearchTreeLayout.calculate(
        technologies: withUnseenReferences,
        nodeSize: _nodeSize,
      );
      _expectGeometry(actual, withUnseenReferences, _nodeSize);
      expect(actual.positions, expected.positions);
      expect(actual.primaryParentIds, expected.primaryParentIds);
      expect(actual.branchBounds, expected.branchBounds);
      expect(actual.size, expected.size);
      expect(actual.seed, expected.seed);
      expect(
        actual.positions.keys,
        isNot(contains('nuclear_thermal_propulsion')),
      );
      expect(actual.positions.keys, isNot(contains('electric_tugs')));
    },
  );

  test('all 98 playable technologies form valid per-field geometry at both text sizes', () {
    final all = ResearchCatalog.purchasableTechnologies.toList();
    expect(all, hasLength(98));
    for (final field in ResearchField.values) {
      final technologies = all
          .where((technology) => technology.field == field)
          .toList();
      for (final nodeSize in [_nodeSize, _nodeSize * 1.4]) {
        final layout = ResearchTreeLayout.calculate(
          technologies: technologies,
          nodeSize: nodeSize,
        );
        _expectGeometry(layout, technologies, nodeSize);
        final frames = layout.branchBounds.values.toList();
        for (var i = 0; i < frames.length; i++) {
          for (final other in frames.skip(i + 1)) {
            expect(
              frames[i].overlaps(other),
              isFalse,
              reason: '${field.name} keeps independent branch frames apart',
            );
          }
        }
      }
    }
  });
}
