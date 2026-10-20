import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/research_catalog.dart';

void main() {
  const catalog = ResearchCatalog.technologies;

  test('全99技術を4分野・24枝で追跡し、98件を独立研究にする', () {
    expect(catalog, hasLength(99));
    expect(catalog.values.map((technology) => technology.catalogId).toSet(), {
      for (final (prefix, count) in [
        ('B', 24),
        ('M', 27),
        ('R', 24),
        ('E', 24),
      ])
        for (var index = 1; index <= count; index++)
          '$prefix${index.toString().padLeft(2, '0')}',
    });
    expect(
      catalog.values.map((technology) => technology.branch).toSet(),
      hasLength(24),
    );
    expect(ResearchCatalog.purchasableTechnologies, hasLength(98));
    for (final field in ResearchField.values) {
      expect(
        catalog.values.where((technology) => technology.field == field),
        hasLength(field == ResearchField.mechanics ? 27 : 24),
      );
      expect(field.label, isNotEmpty);
      expect(field.assetPath, 'assets/images/research/field_${field.name}.png');
    }
  });

  test('既存19研究の保存IDと対応を維持する', () {
    const expected = {
      'B01': 'orbital_gardens',
      'B12': 'closed_ecology',
      'M04': 'automated_fabrication',
      'M09': 'cargo_packaging',
      'M11': 'electric_tugs',
      'M15': 'orbital_logistics',
      'M20': 'industrial_network',
      'M21': 'regional_habitats',
      'M22': 'life_support',
      'M23': 'habitat_operations',
      'M25': 'reusable_launch',
      'M26': 'intercity_logistics',
      'R01': 'local_resources',
      'R10': 'oxygen_pilot',
      'R13': 'regolith_printing',
      'R15': 'process_design',
      'R17': 'radiation_shelters',
      'E05': 'surface_fission',
      'E13': 'urban_planning',
    };
    for (final entry in expected.entries) {
      expect(ResearchCatalog.idForCatalog(entry.key), entry.value);
      expect(
        ResearchCatalog.byCatalogId(entry.key),
        same(catalog[entry.value]),
      );
    }
    expect(ResearchCatalog.byCatalogId('unknown'), isNull);
    expect(() => ResearchCatalog.idForCatalog('unknown'), throwsArgumentError);
  });

  test('研究前提と代替前提が実在し、全経路に循環がない', () {
    final visited = <String>{};
    final active = <String>{};
    void visit(String id) {
      expect(active, isNot(contains(id)), reason: '研究の循環: $id');
      if (!visited.add(id)) return;
      final technology = catalog[id];
      expect(technology, isNotNull, reason: id);
      active.add(id);
      final parents = [
        ...technology!.prerequisiteIds,
        ...technology.alternativePrerequisiteIds,
      ];
      expect(parents.length, lessThanOrEqualTo(2), reason: id);
      expect(parents.toSet(), hasLength(parents.length), reason: id);
      for (final parent in parents) {
        expect(parent, isNot(id));
        visit(parent);
      }
      active.remove(id);
    }

    for (final id in catalog.keys) {
      visit(id);
    }
    expect(visited, hasLength(99));
    final biomaterials = ResearchCatalog.byCatalogId('B24')!;
    expect(biomaterials.prerequisiteIds, isEmpty);
    expect(biomaterials.alternativePrerequisiteIds, [
      ResearchCatalog.idForCatalog('B22'),
      ResearchCatalog.idForCatalog('B23'),
    ]);
  });

  test('スターリング変換機は核分裂電源へ統合し、二重の購入を要求しない', () {
    final converter = ResearchCatalog.byCatalogId('E06')!;
    final power = ResearchCatalog.byCatalogId('E05')!;
    expect(converter.isPurchasable, isFalse);
    expect(converter.integratedIntoId, power.id);
    expect(power.isPurchasable, isTrue);
    expect(power.prerequisiteIds, isEmpty);
    expect(power.unlockName, '小型核分裂発電所');
    for (final technology in ResearchCatalog.purchasableTechnologies) {
      expect(technology.prerequisiteIds, isNot(contains(converter.id)));
      expect(
        technology.alternativePrerequisiteIds,
        isNot(contains(converter.id)),
      );
    }
  });

  test('全技術に具体的な解放先・作業枠・選ぶ際の負担と一次資料を持つ', () {
    for (final entry in catalog.entries) {
      final technology = entry.value;
      expect(entry.key, technology.id);
      expect(technology.id, matches(r'^[a-z][a-z0-9_]*$'));
      expect(technology.name, isNotEmpty);
      expect(technology.description, isNotEmpty);
      expect(technology.branch, isNotEmpty);
      expect(technology.stage, inInclusiveRange(0, 2));
      expect(technology.unlockName, isNotEmpty);
      expect(technology.unlockDescription, isNotEmpty);
      expect(technology.tradeoff, isNotEmpty);
      expect(
        technology.unlockFacilityId,
        isIn(['lab', 'factory', 'launch', 'mars']),
      );
      expect(technology.unlockKind.label, isNotEmpty);
      expect(technology.sourceIds, isNotEmpty);
      expect(technology.science, contains('ゲーム上の仮定'));
      for (final sourceId in technology.sourceIds) {
        expect(ResearchCatalog.sources, contains(sourceId));
        expect(
          technology.science,
          contains(ResearchCatalog.sources[sourceId]!.url),
        );
      }
    }
    expect(
      catalog.values.map((technology) => technology.unlockKind).toSet(),
      ResearchUnlockKind.values.toSet(),
    );
    expect(
      catalog.values.map((technology) => technology.unlockEffect).toSet(),
      ResearchUnlockEffect.values.toSet(),
    );
  });

  test('48資料の確認範囲・成立条件・出典URLを個別に保持する', () {
    expect(ResearchCatalog.sources, hasLength(48));
    expect(ResearchCatalog.sources.keys.toSet(), {
      for (var index = 1; index <= 48; index++)
        'S${index.toString().padLeft(2, '0')}',
    });
    for (final source in ResearchCatalog.sources.values) {
      expect(source.citation, isNotEmpty);
      expect(source.title, isNotEmpty);
      expect(source.scope, isNotEmpty);
      expect(source.summary, isNotEmpty);
      expect(source.limit, isNotEmpty);
      final uri = Uri.parse(source.url);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
    }
    expect(ResearchCatalog.sources['S48']!.citation, contains('2018'));
    expect(ResearchCatalog.sources['S48']!.limit, contains('実証ではない'));
    expect(ResearchCatalog.sources['S46']!.scope, contains('本文・モデル係数は未確認'));
  });
}
