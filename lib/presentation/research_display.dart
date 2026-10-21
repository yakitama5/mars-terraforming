import '../domain/game_content.dart';
import '../domain/game_state.dart';

final _cityIdsByName = {
  for (final city in GameContent.cities.values) city.name: city.id,
};
final _cityNamePattern = RegExp(
  (_cityIdsByName.keys.toList()..sort((a, b) => b.length.compareTo(a.length)))
      .map(RegExp.escape)
      .join('|'),
);

/// Replace canonical names in one pass, without scanning player names again.
String researchUnlockSummary(GameState game, TaskDefinition task) {
  final districts = GameContent.districts.values.where(
    (district) =>
        (district.planet == 'moon' || district.id == 'space_elevator') &&
        (district.requiredResearch == task.id ||
            district.prerequisites.contains(task.id)),
  );
  final summary = [
    task.unlockSummary,
    for (final district in districts)
      '${district.name}の建設${district.prerequisites.isNotEmpty ? '（関連研究を組み合わせて導入）' : ''}',
  ].join('・');
  return summary.replaceAllMapped(
    _cityNamePattern,
    (match) => game.cityName(_cityIdsByName[match.group(0)!]!),
  );
}

String formatResearchPoints(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);
