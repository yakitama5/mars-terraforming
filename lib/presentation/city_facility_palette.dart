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
        compact ? '施設を選ぶ' : '1  建設する施設を選ぶ',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      if (!compact) ...[
        const SizedBox(height: 5),
        const Text(
          '施設 → 地図の区画 → 建設予約。空地から選んでも構いません。',
          style: TextStyle(fontSize: 11, color: strategyMuted),
        ),
      ],
      const SizedBox(height: 10),
      for (final district in districts) ...[
        Semantics(
          selected: district.id == selectedId,
          child: TextButton(
            key: Key('district-option-${district.id}'),
            onPressed: () => onSelected(district.id),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              foregroundColor: const Color(0xffe2ebe3),
              backgroundColor: district.id == selectedId
                  ? const Color(0xff304940)
                  : const Color(0xff1b3034),
              side: BorderSide(
                color: district.id == selectedId
                    ? strategyCopper
                    : strategyLine,
              ),
              alignment: Alignment.centerLeft,
            ),
            child: Row(
              children: [
                Icon(
                  districtIcon(district.id),
                  size: 25,
                  color: strategyCopper,
                ),
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
                          '${districtPurpose(district.id)}\n基準 ${dollars(district.cost)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: strategyMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (lockReason(district) != null)
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
      const Text(
        '区画を選ぶと実際の費用と効果が分かります。鍵付きの施設は解放条件を確認できます。',
        style: TextStyle(fontSize: 11, color: strategyMuted),
      ),
    ],
  );
}
