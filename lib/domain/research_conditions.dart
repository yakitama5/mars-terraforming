import 'game_content.dart';
import 'game_state.dart';

/// Read-only checks shared by the research details and the purchase command.
/// Research capacity remains measurable when the stored RP reserve is full.
List<ResearchRequirementStatus> cityResearchRequirements(
  GameState state,
  String technologyId,
) {
  final technology = GameContent.researchTechnologies[technologyId];
  if (technology == null || !technology.isPurchasable) return const [];
  final conditions = GameContent.cityResearchRequirements(technologyId);
  final population = GameContent.researchPopulationRequirement(technologyId);
  final power = GameContent.cities.values
      .where((city) => state.cityUnlocked(city.id))
      .fold(0, (sum, city) => sum + state.cityPowerSupply(city.id));
  ResearchRequirementStatus status(String label, int current, int required) =>
      ResearchRequirementStatus(
        label: label,
        current: current,
        required: required,
        unmetReason: '都市条件：$label $current/$required',
      );
  return [
    status('総人口', state.totalPopulation, population),
    for (final entry in conditions.developmentCatalogCounts.entries)
      _developmentStatus(state, entry.key, entry.value),
    for (final entry in conditions.districtCounts.entries)
      status(
        '完成した${GameContent.districts[entry.key]!.name}',
        state.districtCount(entry.key),
        entry.value,
      ),
    for (final achievement in conditions.achievements)
      status(
        GameContent.achievementNames[achievement]!,
        state.achievements.contains(achievement) ? 1 : 0,
        1,
      ),
    if (conditions.minimumPower > 0)
      status('電力供給能力', power, conditions.minimumPower),
    if (conditions.minimumResearchPointsPerHour > 0)
      status(
        '研究能力（RP/時）',
        state.researchPointsPerHour.floor(),
        conditions.minimumResearchPointsPerHour,
      ),
    if (conditions.minimumSurveyedSites > 0)
      status(
        '調査を完了した区画',
        state.surveyedSites.length,
        conditions.minimumSurveyedSites,
      ),
    if (conditions.minimumMarsHabitats > 0)
      status('完成した火星居住施設', state.marsHabitats, conditions.minimumMarsHabitats),
  ];
}

ResearchRequirementStatus _developmentStatus(
  GameState state,
  String catalogId,
  int required,
) {
  final technology = ResearchCatalog.byCatalogId(catalogId)!;
  final current = state.developments
      .where((id) => state.developmentTechnologyId(id) == technology.id)
      .length;
  final name = state.isResearchDiscovered(technology.id)
      ? GameContent.mapBuildingDefinitions[technology.id]?.name ??
            technology.unlockName
      : '関連施設（研究を進めて発見）';
  return ResearchRequirementStatus(
    label: '完成した$name',
    current: current,
    required: required,
    unmetReason: '都市条件：完成した$name $current/$required基',
  );
}
