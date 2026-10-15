import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/rendering/city_geometry.dart';
import 'package:mars_terraforming/rendering/city_snapshot.dart';
import 'package:vector_math/vector_math.dart' as vm;

CityTerrain _terrainFor(CityDefinition city) => CityTerrain(
  earth: city.planet == 'earth',
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
  // A camera can include every playable center while cutting off the circular
  // land or its soil base. Check the actual silhouette independently of plots.
  // Scene initialization and GPU resources are not required for projection.
  for (final city in GameContent.cities.values) {
    test('${city.id}: overview keeps the circular land and base in frame', () {
      final terrain = _terrainFor(city);
      for (final size in [
        const Size(360, 180),
        const Size(480, 260),
        const Size(960, 640),
      ]) {
        for (final zoom in [
          CityMapProjection.overviewZoom,
          CityMapProjection.minZoom,
        ]) {
          // Test a complete orbit at the same steps as the rotation control.
          for (var rotation = 0; rotation < 12; rotation++) {
            final view = CityMapProjection(
              terrain: terrain,
              azimuth:
                  CityMapProjection.neighborhoodAzimuth +
                  rotation * math.pi / 6,
              elevation: CityMapProjection.overviewElevation,
              zoom: zoom,
            );
            final camera = view.camera;
            final viewport = Offset.zero & size;
            for (var sample = 0; sample < 72; sample++) {
              final angle = sample * math.pi / 36;
              final x = math.cos(angle) * terrain.landRadius;
              final z = math.sin(angle) * terrain.landRadius;
              for (final surface in [
                (name: 'land', y: terrain.height(x, z)),
                (name: 'base', y: terrain.baseY),
              ]) {
                final point = camera.worldToScreen(
                  vm.Vector3(x, surface.y, z),
                  size,
                );
                final reason =
                    '${city.id}, ${surface.name} sample $sample, '
                    'viewport $size, zoom $zoom, rotation $rotation';
                expect(point, isNotNull, reason: reason);
                expect(point!.dx.isFinite, isTrue, reason: reason);
                expect(point.dy.isFinite, isTrue, reason: reason);
                expect(viewport.contains(point), isTrue, reason: reason);
              }
            }
          }
        }
      }
    });
  }
}
