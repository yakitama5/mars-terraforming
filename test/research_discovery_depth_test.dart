import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/presentation/research_tree_layout.dart';

const _nodeSize = Size(212, 164);
final _epoch = DateTime.utc(2026, 10, 20);

String _id(String catalogId) => ResearchCatalog.idForCatalog(catalogId);

GameEngine _fresh({int points = 100000000}) {
  final state = GameState.initial(_epoch)
    ..openingSeen = true
    ..firstRunTutorial = FirstRunTutorialStep.completed
    ..population = 12000
    ..money = 100000000
    ..marsHabitats = 2
    ..marsResidents = 48
    ..researchPointUnits = points * GameState.researchPointScale;
  state.achievements.addAll(GameContent.achievementNames.keys);
  for (final entry in {
    0: 'housing',
    1: 'housing',
    2: 'industry',
    3: 'industry',
    4: 'spaceport',
    5: 'spaceport',
    6: 'solar',
    7: 'solar',
    8: 'solar',
    9: 'solar',
  }.entries) {
    final district = DistrictState(
      cityId: 'earth_delta',
      plotIndex: entry.key,
      districtId: entry.value,
    );
    state.districts[district.key] = district;
  }
  final moon = DistrictState(
    cityId: 'moon_south_pole',
    plotIndex: 2,
    districtId: 'moon_outpost',
  );
  state.districts[moon.key] = moon;
  final moonPort = DistrictState(
    cityId: 'moon_south_pole',
    plotIndex: 3,
    districtId: 'moon_spaceport',
  );
  state.districts[moonPort.key] = moonPort;
  state.surveyedSites.addAll([
    'earth_delta:0',
    'earth_delta:1',
    'earth_delta:2',
  ]);
  state.connectedGridCities.add('earth_delta');
  state.facilities.updateAll((_, _) => true);
  return GameEngine(state);
}

// These are layout fixtures, not a funded playthrough. Complete the physical
// application only after its knowledge was unlocked; reload remains valid and
// the layout still has to grow from legal, exposed research choices.
void _prepareApplications(GameEngine engine) {
  final state = engine.state;
  for (final technologyId in state.research) {
    state.developments.add(technologyId);
    state.developmentCityIds[technologyId] =
        GameContent.developmentPlanet(technologyId) == 'mars'
        ? 'mars_arcadia'
        : 'earth_delta';
    state.developmentEnabled[technologyId] =
        GameContent.developmentEffect(technologyId) ==
            ResearchUnlockEffect.research ||
        technologyId == 'urban_planning';
    if (GameContent.mapBuildingDefinitions.containsKey(technologyId)) {
      state.buildingLocations[technologyId] = BuildingLocation(
        cityId: state.developmentCityIds[technologyId]!,
        plotIndex: -1,
        legacySite: true,
      );
    }
  }
}

GameEngine _reload(GameEngine engine) => GameEngine(
  GameState.fromJson(
    jsonDecode(jsonEncode(engine.state.toJson())) as Map<String, dynamic>,
  ),
);

Iterable<ResearchTechnology> _eligible(GameEngine engine) =>
    ResearchCatalog.purchasableTechnologies.where(
      (technology) =>
          engine.state.isResearchDiscovered(technology.id) &&
          !engine.state.research.contains(technology.id) &&
          engine.researchRequirementReasons(technology.id).isEmpty,
    );

Map<String, int> _logicalDepths(Set<String> known) {
  final depths = <String, int>{};
  final active = <String>{};
  int visit(String id) {
    if (depths.containsKey(id)) return depths[id]!;
    expect(active.add(id), isTrue, reason: '接続が循環しています: $id');
    var depth = 0;
    for (final parent in GameContent.researchConnectionParentIds(
      GameContent.technology(id),
    ).where(known.contains)) {
      depth = math.max(depth, visit(parent) + 1);
    }
    active.remove(id);
    return depths[id] = depth;
  }

  for (final id in known) {
    visit(id);
  }
  return depths;
}

void _expectGrowthToRight(
  Set<String> before,
  GameState after,
  String unlocked, {
  required String reason,
}) {
  final known = after.discoveredResearchIds;
  expect(known, containsAll(before), reason: '$reason: 発見済み候補が消えません');
  final discoveries = known.difference(before);
  final source = GameContent.technology(unlocked);
  final logical = _logicalDepths(known);
  final layouts = <ResearchField, ResearchTreeLayout>{};
  for (final id in discoveries) {
    final technology = GameContent.technology(id);
    expect(
      GameContent.researchConnectionParentIds(technology),
      contains(unlocked),
      reason: '$reason: $idは解放した研究から生える候補です',
    );
    expect(
      logical[id],
      greaterThan(logical[unlocked]!),
      reason: '$reason: $unlocked → $idの論理階層',
    );
    if (technology.field != source.field) continue;
    final layout = layouts.putIfAbsent(
      technology.field,
      () => ResearchTreeLayout.calculate(
        technologies: known
            .map(GameContent.technology)
            .where((candidate) => candidate.field == source.field),
        nodeSize: _nodeSize,
      ),
    );
    expect(layout.positions.keys, containsAll([unlocked, id]));
    // This is the same layout coordinate consumed by the product canvas,
    // rather than a second UI-specific depth formula in the test.
    expect(
      layout.positions[id]!.dx,
      greaterThan(layout.positions[unlocked]!.dx),
      reason: '$reason: $idの実際のカード位置が$unlockedより右です',
    );
  }
}

void _unlock(GameEngine engine, String catalogId) {
  final id = _id(catalogId);
  expect(engine.unlockResearch(id), isNull, reason: '$catalogIdを公開操作で解放');
  _prepareApplications(engine);
}

void main() {
  test('33個の独立入口だけに実在する同分野の発見親を持たせる', () {
    final technologies = ResearchCatalog.purchasableTechnologies.toList();
    final starters = GameContent.starterResearchCatalogIds.toSet();
    final roots = technologies.where(
      (technology) =>
          technology.prerequisiteIds.isEmpty &&
          technology.alternativePrerequisiteIds.isEmpty &&
          !starters.contains(technology.catalogId),
    );
    final rootedIds = roots.map((technology) => technology.id).toSet();
    expect(rootedIds, hasLength(33));
    expect(
      technologies
          .where(
            (technology) =>
                GameContent.researchDiscoveryParentIds(technology.id)
                    .isNotEmpty,
          )
          .map((technology) => technology.id)
          .toSet(),
      rootedIds,
    );
    for (final root in roots) {
      final parents = GameContent.researchDiscoveryParentIds(root.id);
      expect(parents, isNotEmpty, reason: root.catalogId);
      expect(parents.toSet(), hasLength(parents.length));
      for (final parentId in parents) {
        final parent = GameContent.researchTechnologies[parentId];
        expect(parent, isNotNull, reason: '${root.catalogId}の発見親');
        expect(parent!.isPurchasable, isTrue);
        expect(parent.id, isNot(root.id));
        expect(parent.field, root.field);
      }
    }
    expect(
      GameContent.researchDiscoveryParentIds(_id('R07')),
      unorderedEquals([_id('R05'), _id('R06')]),
    );
  });

  test('発見親と技術前提の合併は循環せず4入口から98研究へ到達できる', () {
    final technologies = ResearchCatalog.purchasableTechnologies.toList();
    final ids = technologies.map((technology) => technology.id).toSet();
    final starters = GameContent.starterResearchCatalogIds.map(_id).toSet();
    for (final technology in technologies) {
      final parents = GameContent.researchConnectionParentIds(technology);
      expect(parents.toSet(), hasLength(parents.length));
      expect(
        parents,
        containsAll([
          ...technology.prerequisiteIds,
          ...technology.alternativePrerequisiteIds,
          ...GameContent.researchDiscoveryParentIds(technology.id),
        ]),
      );
      expect(ids, containsAll(parents));
    }
    final depths = _logicalDepths(ids);
    expect(
      depths.entries
          .where((entry) => entry.value == 0)
          .map((entry) => entry.key)
          .toSet(),
      starters,
    );
    final engine = _fresh();
    expect(engine.state.discoveredResearchIds, starters);
    for (var step = 0; step < technologies.length; step++) {
      final candidates = _eligible(engine).toList();
      expect(candidates, isNotEmpty, reason: '$step件解放後にも選べる研究があります');
      expect(engine.unlockResearch(candidates.first.id), isNull);
      _prepareApplications(engine);
    }
    expect(engine.state.research, ids);
  });

  test('20通りの合法な順序と途中再読込で新候補は毎回解放元より右へ生える', () {
    final total = ResearchCatalog.purchasableTechnologies.length;
    for (var seed = 0; seed < 20; seed++) {
      final random = math.Random(seed);
      var engine = _fresh();
      for (var step = 0; step < total; step++) {
        final candidates = _eligible(engine).toList()
          ..sort((a, b) => a.catalogId.compareTo(b.catalogId));
        expect(candidates, isNotEmpty, reason: 'seed=$seed step=$step');
        final selected = candidates[random.nextInt(candidates.length)];
        final before = Set<String>.of(engine.state.discoveredResearchIds);
        expect(engine.unlockResearch(selected.id), isNull);
        _prepareApplications(engine);
        _expectGrowthToRight(
          before,
          engine.state,
          selected.id,
          reason: 'seed=$seed step=$step ${selected.catalogId}',
        );
        if (step % 13 == 7) {
          final known = Set<String>.of(engine.state.discoveredResearchIds);
          final unlocked = Set<String>.of(engine.state.research);
          engine = _reload(engine);
          expect(engine.state.discoveredResearchIds, known);
          expect(engine.state.research, unlocked);
        }
      }
      expect(engine.state.research, hasLength(total));
    }

    // E19 is the existing cross-field application. Complete its energy side
    // first, so the last mechanical prerequisite itself causes its discovery.
    final crossing = _fresh();
    for (final catalogId in ['R01', 'R02', 'E01', 'E13', 'E17', 'M22']) {
      _unlock(crossing, catalogId);
    }
    expect(crossing.state.isResearchDiscovered(_id('E19')), isFalse);
    final before = Set<String>.of(crossing.state.discoveredResearchIds);
    _unlock(crossing, 'M17');
    expect(crossing.state.isResearchDiscovered(_id('E19')), isTrue);
    _expectGrowthToRight(
      before,
      crossing.state,
      _id('M17'),
      reason: 'M17 → E19の分野横断',
    );
  });

  test('RPが貯まっても手動解放まで枝は増えず途中保存後も深さ規則を守る', () {
    var engine = _fresh(points: 0);
    for (final catalogId in ['B01', 'B05']) {
      final id = _id(catalogId);
      final before = Set<String>.of(engine.state.discoveredResearchIds);
      expect(engine.enqueue(id), contains('研究ポイント不足'));
      expect(engine.state.plans.where((plan) => !plan.isFinished), isEmpty);
      expect(engine.state.research, isNot(contains(id)));
      final wait = engine.state.researchWaitMs(id)!;
      expect(wait, greaterThan(1));
      final firstHalf = wait ~/ 2;
      engine.advanceBy(Duration(milliseconds: firstHalf));
      expect(engine.state.research, isNot(contains(id)));
      expect(engine.state.discoveredResearchIds, before);
      engine = _reload(engine);
      expect(engine.state.research, isNot(contains(id)));
      engine.advanceBy(Duration(milliseconds: wait - firstHalf + 1));
      expect(engine.state.research, isNot(contains(id)));
      expect(engine.state.discoveredResearchIds, before);
      expect(engine.unlockResearch(id), isNull);
      _prepareApplications(engine);
      expect(engine.state.research, contains(id));
      _expectGrowthToRight(before, engine.state, id, reason: '$catalogIdの手動解放');
      final after = Set<String>.of(engine.state.discoveredResearchIds);
      engine = _reload(engine);
      expect(engine.state.discoveredResearchIds, after);
    }
  });

  test('同じ階層の噴霧栽培を解放しても無関係の処理棟の着想は出ない', () {
    final engine = _fresh();
    _unlock(engine, 'B01');
    expect(engine.state.isResearchDiscovered(_id('B02')), isTrue);
    expect(engine.state.isResearchDiscovered(_id('B05')), isTrue);
    expect(engine.state.isResearchDiscovered(_id('B09')), isFalse);
    final before = Set<String>.of(engine.state.discoveredResearchIds);
    _unlock(engine, 'B02');
    expect(engine.state.discoveredResearchIds, before);
    expect(engine.state.isResearchDiscovered(_id('B09')), isFalse);
    expect(engine.state.isResearchDiscovered(_id('B17')), isFalse);
    expect(engine.state.isResearchDiscovered(_id('B22')), isFalse);
  });

  test('水の精製は採氷と加熱抽出のどちらか一方から発見して解放できる', () {
    for (final source in ['R05', 'R06']) {
      final engine = _fresh();
      _unlock(engine, 'E01');
      _unlock(engine, 'E13');
      _unlock(engine, 'R01');
      _unlock(engine, 'R02');
      expect(engine.state.isResearchDiscovered(_id('R07')), isFalse);
      final before = Set<String>.of(engine.state.discoveredResearchIds);
      _unlock(engine, source);
      expect(engine.state.isResearchDiscovered(_id('R07')), isTrue);
      _expectGrowthToRight(
        before,
        engine.state,
        _id(source),
        reason: '$sourceから精製の着想を発見',
      );
      final alternative = source == 'R05' ? 'R06' : 'R05';
      expect(engine.state.research, isNot(contains(_id(alternative))));
      expect(engine.researchRequirementReasons(_id('R07')), isEmpty);
      _unlock(engine, 'R07');
    }
  });
}
