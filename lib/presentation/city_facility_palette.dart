import 'package:flutter/material.dart';

import '../domain/game_content.dart';
import 'strategy_widgets.dart';

IconData districtIcon(String id) => switch (id) {
  'housing' => Icons.apartment,
  'campus' || 'mars_lab' => Icons.science_outlined,
  'industry' => Icons.factory_outlined,
  'solar' => Icons.solar_power_outlined,
  'spaceport' => Icons.rocket_launch_outlined,
  'mars_habitat' => Icons.home_work_outlined,
  'greenhouse' => Icons.eco_outlined,
  'extractor' => Icons.landscape_outlined,
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
  _ => '都市の能力を高める',
};

class CityFacilityPalette extends StatelessWidget {
  const CityFacilityPalette({
    super.key,
    required this.districts,
    required this.selectedId,
    required this.onSelected,
    required this.lockReason,
  });
  final List<DistrictDefinition> districts;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final String? Function(DistrictDefinition) lockReason;

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
      for (final district in districts) ...[
        Semantics(
          selected: district.id == selectedId,
          hint:
              '${districtPurpose(district.id)}。基準費用${dollars(district.cost)}${lockReason(district) == null ? '' : '。${lockReason(district)}'}',
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
                  ? strategySelected
                  : strategyPanel,
              side: BorderSide(
                color: district.id == selectedId ? strategyBlue : strategyLine,
              ),
              alignment: Alignment.centerLeft,
            ),
            child: Row(
              children: [
                Icon(districtIcon(district.id), size: 25, color: strategyBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        district.name,
                        semanticsLabel: '${district.name}を選ぶ',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      ExcludeSemantics(
                        child: Text(
                          '${districtPurpose(district.id)} · ${dollars(district.cost)}〜',
                          style: const TextStyle(
                            fontSize: 11,
                            color: strategyMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (district.id == selectedId)
                  const Icon(Icons.check_circle, size: 18, color: strategyBlue)
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
      if (!compact)
        const Text(
          '鍵のある施設を押すと、解放条件を確認できます。',
          style: TextStyle(fontSize: 11, color: strategyMuted),
        ),
    ],
  );
}
