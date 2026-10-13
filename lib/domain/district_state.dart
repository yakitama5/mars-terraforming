import 'game_content.dart';

class DistrictState {
  const DistrictState({
    required this.cityId,
    required this.plotIndex,
    required this.districtId,
    this.level = 1,
  });
  final String cityId, districtId;
  final int plotIndex, level;
  String get key => '$cityId:$plotIndex';
  Map<String, dynamic> toJson() => {
    'cityId': cityId,
    'plotIndex': plotIndex,
    'districtId': districtId,
    'level': level,
  };
  factory DistrictState.fromJson(Map<String, dynamic> json) {
    final district = DistrictState(
      cityId: json['cityId'] as String,
      plotIndex: json['plotIndex'] as int,
      districtId: json['districtId'] as String,
      level: json['level'] as int,
    );
    final city = GameContent.cities[district.cityId];
    final definition = GameContent.districts[district.districtId];
    if (city == null ||
        definition == null ||
        city.planet != definition.planet ||
        district.plotIndex < 0 ||
        district.plotIndex >= city.plotCount ||
        district.level < 1 ||
        district.level > definition.maxLevel ||
        (definition.allowedTerrain.isNotEmpty &&
            !definition.allowedTerrain.contains(
              city.terrainAt(district.plotIndex),
            ))) {
      throw const FormatException('保存された地区が不正です');
    }
    return district;
  }
}

class DistrictEffects {
  const DistrictEffects({
    this.tax = 0,
    this.upkeep = 0,
    this.research = 0,
    this.factory = 0,
    this.launch = 0,
    this.mars = 0,
  });
  final int tax, upkeep, research, factory, launch, mars;
  DistrictEffects operator +(DistrictEffects other) => DistrictEffects(
    tax: tax + other.tax,
    upkeep: upkeep + other.upkeep,
    research: research + other.research,
    factory: factory + other.factory,
    launch: launch + other.launch,
    mars: mars + other.mars,
  );
  DistrictEffects operator -(DistrictEffects other) => DistrictEffects(
    tax: tax - other.tax,
    upkeep: upkeep - other.upkeep,
    research: research - other.research,
    factory: factory - other.factory,
    launch: launch - other.launch,
    mars: mars - other.mars,
  );
}

class DistrictPreview {
  const DistrictPreview({
    required this.cost,
    required this.durationMs,
    required this.targetLevel,
    required this.taxDeltaPerMinute,
    required this.upkeepDeltaPerMinute,
    required this.researchBonusDelta,
    required this.factoryBonusDelta,
    required this.launchBonusDelta,
    required this.marsBonusDelta,
    required this.bonuses,
    this.blockedReason,
  });
  final int cost,
      durationMs,
      targetLevel,
      taxDeltaPerMinute,
      upkeepDeltaPerMinute;
  final int researchBonusDelta,
      factoryBonusDelta,
      launchBonusDelta,
      marsBonusDelta;
  final List<String> bonuses;
  final String? blockedReason;
  bool get isValid => blockedReason == null;
}
