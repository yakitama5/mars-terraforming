import 'game_content.dart';

/// Player-facing names never replace IDs used by plans, cities or rewards.
class MissionIdentity {
  const MissionIdentity({this.cityNames = const {}, this.rocketName = 'あかつき'});

  static const maxNameLength = 24;
  final Map<String, String> cityNames;
  final String rocketName;

  String cityName(String cityId) =>
      cityNames[cityId] ?? GameContent.cities[cityId]?.name ?? cityId;

  static String? nameError(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return '名前を入力してください';
    if (clean.runes.length > maxNameLength) {
      return '$maxNameLength文字以内で入力してください';
    }
    if (RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]').hasMatch(clean)) {
      return '改行や制御文字は使えません';
    }
    return null;
  }

  MissionIdentity renamed({Map<String, String>? cities, String? rocket}) {
    final names = {...cityNames, ...?cities};
    final nextRocket = rocket?.trim() ?? rocketName;
    if (nameError(nextRocket) != null ||
        names.entries.any(
          (entry) =>
              !GameContent.cities.containsKey(entry.key) ||
              nameError(entry.value) != null,
        )) {
      throw const FormatException('都市またはロケットの名前が不正です');
    }
    return MissionIdentity(
      cityNames: Map.unmodifiable(
        names.map((id, name) => MapEntry(id, name.trim())),
      ),
      rocketName: nextRocket,
    );
  }

  Map<String, dynamic> toJson() => {
    'cityNames': Map<String, String>.of(cityNames),
    'rocketName': rocketName,
  };

  factory MissionIdentity.fromJson(Map<String, dynamic> json) =>
      const MissionIdentity().renamed(
        cities: Map<String, String>.from(json['cityNames'] as Map),
        rocket: json['rocketName'] as String,
      );
}
