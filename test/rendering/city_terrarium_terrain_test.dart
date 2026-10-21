import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/rendering/city_geometry.dart';
import 'package:mars_terraforming/rendering/city_snapshot.dart';

CityTerrain _terrain(CityDefinition city) => CityTerrain(
  earth: city.planet == 'earth',
  moon: city.planet == 'moon',
  columns: city.width,
  rows: city.height,
  plots: [
    for (var index = 0; index < city.plotCount; index++)
      ScenePlot(
        index: index,
        terrain: city.terrainAt(index),
        terrainName: GameContent.terrainNames[city.terrainAt(index)]!,
      ),
  ],
);

void main() {
  test('月面は河川を掘らず、灰色の乾燥したレゴリスで描画する', () {
    final terrain = CityTerrain(
      earth: false,
      moon: true,
      columns: 1,
      rows: 1,
      plots: const [ScenePlot(index: 0, terrain: 'plain', terrainName: '平地')],
    );
    expect(terrain.hasRiver, isFalse);
    expect(terrain.hasCoast, isFalse);
    final x = 0.0;
    final z = terrain.riverCenterZ(x);
    expect(terrain.isWater(x, z), isFalse);
    expect(terrain.waterDistance(x, z), double.infinity);
    // The old Martian dry channel must not appear on the Moon either.
    expect(terrain.height(x, z), greaterThan(.08));
    for (final point in [(0.0, 0.0), (x, z)]) {
      final color = terrain.colorAt(point.$1, point.$2);
      expect((color.r - color.g).abs(), lessThan(.025));
      expect((color.r - color.b).abs(), lessThan(.06));
    }
  });

  for (final city in GameContent.cities.values) {
    test(
      '${city.id}: circular slice contains every buildable hex and thick rim',
      () {
        final terrain = _terrain(city);
        for (final plot in terrain.plots) {
          for (final corner in terrain.boundary(plot.index)) {
            expect(
              terrain.containsLand(corner.x, corner.z, inset: .90),
              isTrue,
            );
            expect(
              terrain.riverDistance(corner.x, corner.z),
              greaterThan(.04),
              reason:
                  'The new scenic river must stay outside construction hexes',
            );
          }
        }
        for (var i = 0; i < 72; i++) {
          final angle = i / 72 * math.pi * 2;
          final x = math.cos(angle) * terrain.landRadius;
          final z = math.sin(angle) * terrain.landRadius;
          expect(terrain.containsLand(x * .99999, z * .99999), isTrue);
          expect(terrain.containsLand(x * 1.00001, z * 1.00001), isFalse);
          expect(
            terrain.height(x, z) - terrain.baseY,
            greaterThan(.9),
            reason:
                'The terrain must have a visible, closed soil cross-section',
          );
        }
      },
    );

    test('${city.id}: river never floods or tilts a facility footprint', () {
      final terrain = _terrain(city);
      for (final plot in terrain.plots) {
        final center = terrain.center(plot.index);
        for (var i = 0; i < 24; i++) {
          final angle = i / 24 * math.pi * 2;
          final x = center.x + math.cos(angle) * .43;
          final z = center.z + math.sin(angle) * .43;
          expect(terrain.isWater(x, z), isFalse);
          expect(terrain.height(x, z), closeTo(center.y, 1e-5));
        }
      }
    });
  }

  test('Earth stream has continuous banks, a submerged bed and round water boundary', () {
    final terrain = _terrain(GameContent.cities['earth_delta']!);
    expect(terrain.hasRiver, isTrue);
    for (var i = 0; i <= 24; i++) {
      final x = -3.0 + i * .25;
      final z = terrain.riverCenterZ(x);
      final width = terrain.riverHalfWidth(x);
      expect(terrain.isWater(x, z), isTrue);
      expect(terrain.height(x, z), lessThan(CityTerrain.waterLevel - .1));
      for (final direction in [-1, 1]) {
        final shore = z + direction * width;
        expect(terrain.height(x, shore), closeTo(CityTerrain.waterLevel, 1e-5));
        expect(
          terrain.height(x, shore - 1e-5),
          closeTo(terrain.height(x, shore + 1e-5), .001),
        );
        expect(terrain.isWater(x, shore + direction * .04), isFalse);
      }
    }
    expect(terrain.isWater(-terrain.landRadius - .1, 0), isFalse);
    expect(terrain.isWater(-terrain.landRadius + .1, 0), isTrue);
  });

  test('the coastal ridge never raises ground above the visible water', () {
    final terrain = _terrain(GameContent.cities['earth_delta']!);
    var checked = 0;
    for (var x = -terrain.landRadius; x < 0; x += .12) {
      for (var z = -terrain.landRadius; z < terrain.landRadius; z += .12) {
        if (!terrain.isWater(x, z)) continue;
        checked++;
        expect(
          terrain.height(x, z),
          lessThanOrEqualTo(CityTerrain.waterLevel + 1e-5),
          reason:
              'Water at ($x, $z) must cover a submerged bed, not a blue cliff',
        );
      }
    }
    expect(checked, greaterThan(100));
  });

  test('Mars valley remains dry and has no implied liquid river', () {
    for (final city in GameContent.cities.values.where(
      (city) => city.planet == 'mars',
    )) {
      final terrain = _terrain(city);
      expect(terrain.hasRiver, isFalse);
      for (var i = 0; i <= 24; i++) {
        final x = -3.0 + i * .25;
        final z = terrain.riverCenterZ(x);
        expect(terrain.containsLand(x, z), isTrue);
        expect(terrain.isWater(x, z), isFalse);
        expect(terrain.waterDistance(x, z), double.infinity);
        expect(terrain.height(x, z), lessThan(.08));
        final color = terrain.colorAt(x, z);
        expect(
          color.r,
          greaterThan(color.b),
          reason:
              'The dry streambed must read as rust/soil rather than blue water',
        );
      }
    }
  });
}
