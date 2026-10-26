import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/research_conditions.dart';

void main() {
  GameState fresh() => GameState.initial(DateTime.utc(2026, 10, 26))
    ..openingSeen = true
    ..firstRunTutorial = FirstRunTutorialStep.completed;
  String id(String catalog) => ResearchCatalog.idForCatalog(catalog);

  test(
    'all 98 technologies have explicit city conditions and no self facility',
    () {
      final technologies = ResearchCatalog.purchasableTechnologies;
      expect(technologies, hasLength(98));
      expect(
        GameContent.cityResearchRequirementsByCatalog.keys.toSet(),
        technologies.map((technology) => technology.catalogId).toSet(),
      );
      for (final technology in technologies) {
        final requirements = GameContent.cityResearchRequirements(
          technology.id,
        );
        expect(
          requirements.developmentCatalogCounts,
          isNot(contains(technology.catalogId)),
          reason: technology.catalogId,
        );
        for (final entry in requirements.developmentCatalogCounts.entries) {
          expect(ResearchCatalog.byCatalogId(entry.key)?.isPurchasable, isTrue);
          expect(entry.value, greaterThan(0));
        }
        for (final entry in requirements.districtCounts.entries) {
          expect(GameContent.districts, contains(entry.key));
          expect(entry.value, greaterThan(0));
        }
        for (final achievement in requirements.achievements) {
          expect(GameContent.achievementNames, contains(achievement));
        }
      }
    },
  );

  test('combined research, discovery and facility dependencies reach all nodes', () {
    // This is a constructive dependency audit. No research or city facilities
    // are pre-granted: each idea enters only after its prerequisites can exist.
    // Population and unlocked generic districts may be expanded with normal
    // construction. RP-rate facilities can use the accessible R01 analysis lab.
    final reached = <String>{};
    final pending = ResearchCatalog.purchasableTechnologies.toList();
    var progressed = true;
    while (progressed && pending.isNotEmpty) {
      progressed = false;
      for (final technology in pending.toList()) {
        if (!technology.prerequisiteIds.every(reached.contains)) continue;
        if (technology.alternativePrerequisiteIds.isNotEmpty &&
            !technology.alternativePrerequisiteIds.any(reached.contains)) {
          continue;
        }
        final parents = GameContent.researchDiscoveryParentIds(technology.id);
        if (parents.isNotEmpty && !parents.any(reached.contains)) continue;
        final requirements = GameContent.cityResearchRequirements(
          technology.id,
        );
        final physicalDependencies = <String>{
          for (final catalog in requirements.developmentCatalogCounts.keys)
            id(catalog),
          for (final districtId in requirements.districtCounts.keys) ...[
            ?GameContent.districts[districtId]!.requiredResearch,
            ...GameContent.districts[districtId]!.prerequisites,
          ],
          if (requirements.minimumSurveyedSites > 0 ||
              requirements.minimumResearchPointsPerHour >
                  GameContent.baseResearchPointsPerMinute * 60)
            id('R01'),
          if (requirements.minimumPower > GameContent.baseCityPower) id('E13'),
          if (requirements.minimumMarsHabitats > 0 ||
              requirements.achievements.contains('first_landing') ||
              requirements.districtCounts.keys.any(
                (district) =>
                    GameContent.districts[district]!.planet != 'earth',
              ))
            id('M22'),
        };
        if (!physicalDependencies.every(reached.contains)) continue;
        reached.add(technology.id);
        pending.remove(technology);
        progressed = true;
      }
    }
    expect(
      pending.map((technology) => technology.catalogId),
      isEmpty,
      reason: 'A facility, discovery or research dependency creates a dead end',
    );
    expect(reached, hasLength(98));
  });

  test(
    'population tier capacity can pay its research and first installation',
    () {
      for (final technology in ResearchCatalog.purchasableTechnologies) {
        final population = GameContent.researchPopulationRequirement(
          technology.id,
        );
        final points =
            GameContent.researchPointBaseCapacity +
            population * GameContent.researchPointCapacityPerResident;
        final money =
            GameContent.moneyBaseCapacity +
            population * GameContent.moneyCapacityPerResident;
        expect(
          points,
          greaterThanOrEqualTo(GameContent.researchPointCost(technology.id)),
          reason: technology.catalogId,
        );
        expect(
          money,
          greaterThan(GameContent.developmentCost(technology.id)),
          reason: '${technology.catalogId} must retain operating funds',
        );
      }
      final largeResearch = id('M14');
      final population = GameContent.researchPopulationRequirement(
        largeResearch,
      );
      final budget =
          GameContent.moneyBaseCapacity +
          population * GameContent.moneyCapacityPerResident;
      expect(
        budget,
        greaterThan(GameContent.districts['space_elevator']!.cost),
      );
    },
  );

  test('the initial population meets every starter foundation', () {
    final state = fresh();
    for (final catalog in GameContent.starterResearchCatalogIds) {
      expect(
        cityResearchRequirements(state, id(catalog)).every((r) => r.isMet),
        isTrue,
      );
    }
  });

  test('RP cannot replace the completed facility required by cultivation', () {
    final state = fresh()
      ..population = 240
      ..money = 100000
      ..research.add(id('B01'))
      ..researchPointUnits = 2400 * GameState.researchPointScale;
    final engine = GameEngine(state);
    expect(engine.unlockResearch(id('B02')), contains('都市条件'));
    expect(state.researchPointUnits, 2400 * GameState.researchPointScale);
    expect(state.research, isNot(contains(id('B02'))));
    state.developments.add(id('B01'));
    state.developmentCityIds[id('B01')] = 'earth_delta';
    expect(engine.unlockResearch(id('B02')), isNull);
    expect(state.research, contains(id('B02')));
    expect(state.researchPointUnits, 0);
    expect(state.simulatedMs, 0);
  });

  test('research branches retain different city investments', () {
    final crops = GameContent.cityResearchRequirements(id('B02'));
    final rocket = GameContent.cityResearchRequirements(id('M25'));
    final solar = GameContent.cityResearchRequirements(id('E02'));
    expect(crops.developmentCatalogCounts, {'B01': 1});
    expect(rocket.districtCounts, {'industry': 1});
    expect(rocket.achievements, ['first_launch']);
    expect(solar.districtCounts, {'solar': 2});
    expect(solar.achievements, isEmpty);
  });

  test(
    'only research installations gain passive RP without assigned staff',
    () {
      expect(GameContent.developmentResearchPointsPerMinute(id('R01')), 8);
      expect(GameContent.developmentResearchPointsPerMinute(id('B14')), 18);
      expect(GameContent.developmentResearchPointsPerMinute(id('R24')), 36);
      expect(GameContent.developmentResearchPointsPerMinute(id('B01')), 0);
      expect(GameContent.developmentResearchPointsPerMinute(id('R15')), 0);
      expect(GameContent.developmentResearchPointsPerMinute(id('M25')), 0);
    },
  );
}
