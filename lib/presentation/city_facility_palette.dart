import 'package:flutter/material.dart';

import '../domain/game_content.dart';
import 'research_theme.dart';
import 'strategy_widgets.dart';

// Visual association with the research fields only. A district's RP, effects,
// and unlock rules still come from GameContent and the domain state.
ResearchField? districtResearchField(String id) => switch (id) {
  'campus' || 'mars_lab' || 'greenhouse' => ResearchField.bio,
  'industry' ||
  'spaceport' ||
  'mars_habitat' ||
  'moon_outpost' ||
  'moon_spaceport' => ResearchField.mechanics,
  'extractor' ||
  'moon_extractor' ||
  'space_elevator' => ResearchField.materials,
  'solar' || 'moon_solar' => ResearchField.energy,
  _ => null,
};

Color districtAccent(String id) =>
    districtResearchField(id)?.color ?? const Color(0xffb7c9db);

Color districtPanelTint(String id) =>
    Color.alphaBlend(districtAccent(id).withValues(alpha: .09), strategyPanel);

String districtCategoryLabel(String id) =>
    districtResearchField(id)?.label ?? '都市基盤';

class DistrictSelectionHeading extends StatelessWidget {
  const DistrictSelectionHeading({
    super.key,
    required this.districtId,
    required this.title,
    this.fontSize = 16,
  });

  final String districtId, title;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('district-selection-$districtId'),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: districtPanelTint(districtId),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: districtAccent(districtId).withValues(alpha: .45),
      ),
    ),
    child: Row(
      children: [
        Icon(
          districtIcon(districtId),
          color: districtAccent(districtId),
          size: 24,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                districtCategoryLabel(districtId),
                style: TextStyle(
                  fontSize: 10,
                  color: districtAccent(districtId),
                ),
              ),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

IconData districtIcon(String id) => switch (id) {
  'housing' => Icons.apartment,
  'campus' || 'mars_lab' => Icons.science_outlined,
  'industry' => Icons.factory_outlined,
  'solar' || 'moon_solar' => Icons.solar_power_outlined,
  'spaceport' || 'moon_spaceport' => Icons.rocket_launch_outlined,
  'mars_habitat' || 'moon_outpost' => Icons.home_work_outlined,
  'space_elevator' => Icons.elevator_outlined,
  'greenhouse' => Icons.eco_outlined,
  'extractor' || 'moon_extractor' => Icons.landscape_outlined,
  _ => Icons.construction,
};

String districtPurpose(String id) => switch (id) {
  'housing' => '人口と税収を増やす',
  'campus' || 'mars_lab' => '研究を速める',
  'industry' => '製造を速める',
  'solar' => '周辺施設を支える',
  'spaceport' => '輸送を速める',
  'mars_habitat' => '火星での居住を広げる',
  'greenhouse' => '居住と現地生産を支える',
  'extractor' => '現地の資源を活用する',
  'moon_outpost' => '月面開発と火星探査を支える',
  'moon_spaceport' => '火星への打ち上げを解放する',
  'moon_solar' => '月面設備と推進剤補給を支える',
  'moon_extractor' => '月面資源で輸送費を抑える',
  'space_elevator' => '軌道へ運ぶ費用を抑える',
  _ => '都市の能力を高める',
};

class CityFacilityPalette extends StatelessWidget {
  const CityFacilityPalette({
    super.key,
    required this.districts,
    required this.selectedId,
    required this.onSelected,
    required this.lockReason,
    this.additionalChoices = const [],
  });
  final List<DistrictDefinition> districts;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final String? Function(DistrictDefinition) lockReason;
  final List<Widget> additionalChoices;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _palette(compact: constraints.maxHeight < 300),
  );

  Widget _palette({required bool compact}) => ListView(
    key: const Key('city-facility-palette'),
    padding: const EdgeInsets.all(10),
    children: [
      Text(
        '1  施設を選ぶ',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      if (!compact) ...[
        const SizedBox(height: 5),
        const Text(
          '施設 → 区画 → 建設予約',
          style: TextStyle(fontSize: 11, color: strategyMuted),
        ),
      ],
      const SizedBox(height: 10),
      if (districts.isEmpty && additionalChoices.isEmpty)
        const Text(
          '研究ツリーで技術を解放すると、建設できる施設がここに現れます。',
          key: Key('city-facility-empty'),
          style: TextStyle(fontSize: 13, color: strategyMuted),
        ),
      for (final district in districts) ...[
        Semantics(
          selected: district.id == selectedId,
          hint:
              '${districtCategoryLabel(district.id)}。${districtPurpose(district.id)}。基準費用${dollars(district.cost)}${lockReason(district) == null ? '' : '。${lockReason(district)}'}',
          child: TextButton(
            key: Key('district-option-${district.id}'),
            onPressed: () => onSelected(district.id),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: compact ? 9 : 12,
              ),
              foregroundColor: strategyText,
              backgroundColor: district.id == selectedId
                  ? Color.alphaBlend(
                      districtAccent(district.id).withValues(alpha: .14),
                      districtPanelTint(district.id),
                    )
                  : districtPanelTint(district.id),
              side: BorderSide(
                color: districtAccent(district.id)
                    .withValues(alpha: district.id == selectedId ? 1 : .32),
                width: district.id == selectedId ? 1.5 : 1,
              ),
              alignment: Alignment.centerLeft,
            ),
            child: Row(
              children: [
                Icon(
                  districtIcon(district.id),
                  size: 25,
                  color: districtAccent(district.id),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        district.name,
                        semanticsLabel: '${district.name}を選ぶ',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              districtCategoryLabel(district.id),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: districtAccent(district.id),
                              ),
                            ),
                            Text(
                              districtPurpose(district.id),
                              maxLines: compact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: strategyMuted,
                              ),
                            ),
                            Text(
                              '${dollars(district.cost)}〜',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: strategyMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (district.id == selectedId)
                  Icon(
                    Icons.check_circle,
                    size: 18,
                    color: districtAccent(district.id),
                  )
                else if (lockReason(district) != null)
                  const Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: strategyMuted,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
      ],
      ...additionalChoices,
      if (!compact && (districts.isNotEmpty || additionalChoices.isNotEmpty))
        const Text(
          '研究で技術を解放すると、新しい施設が増えます。',
          style: TextStyle(fontSize: 11, color: strategyMuted),
        ),
    ],
  );
}
