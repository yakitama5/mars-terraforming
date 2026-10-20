import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/research_catalog.dart';
import 'package:mars_terraforming/domain/research_flavor.dart';

void main() {
  test('購入できる全研究に固有の短い未来の一景がある', () {
    final ids = ResearchCatalog.purchasableTechnologies.map(
      (technology) => technology.id,
    );
    expect(ResearchFlavor.passages.keys.toSet(), ids.toSet());
    expect(ResearchFlavor.passages.values.toSet(), hasLength(ids.length));
    for (final id in ids) {
      final passage = ResearchFlavor.forTechnology(id);
      expect(
        passage.split('。').where((sentence) => sentence.isNotEmpty),
        hasLength(2),
        reason: id,
      );
      expect(
        passage,
        isNot(contains(RegExp(r'https?://|出典|[0-9]'))),
        reason: id,
      );
    }
  });

  test('統合した構成技術は主研究の文章を使い、未知IDは受け付けない', () {
    expect(
      ResearchFlavor.forTechnology('stirling_conversion'),
      ResearchFlavor.forTechnology('surface_fission'),
    );
    expect(() => ResearchFlavor.forTechnology('unknown'), throwsArgumentError);
  });
}
