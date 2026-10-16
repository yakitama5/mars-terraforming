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
String researchUnlockSummary(GameState game, TaskDefinition task) =>
    task.unlockSummary.replaceAllMapped(
      _cityNamePattern,
      (match) => game.cityName(_cityIdsByName[match.group(0)!]!),
    );
