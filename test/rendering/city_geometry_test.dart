import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/rendering/city_geometry.dart';
import 'package:mars_terraforming/rendering/city_snapshot.dart';

CityTerrain terrainFor(CityDefinition city) => CityTerrain(
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
  // Vector3 stores Float32 coordinates; compare geometry within 1e-5 world
  // units (far below a one-unit hex radius), not Dart double precision.
  const geometryTolerance = 1e-5;
  // Neither a Scene nor GPU resources are initialized here. These checks use
  // the same camera and land coordinates that the interactive map uses.
  for (final city in GameContent.cities.values) {
    test(
      '${city.id}: terrain, shared hex edges and domain neighbors agree',
      () {
        final terrain = terrainFor(city);
        expect(terrain.centers, hasLength(25));
        for (var index = 0; index < city.plotCount; index++) {
          final center = terrain.center(index);
          expect(
            center.y,
            closeTo(terrain.height(center.x, center.z), geometryTolerance),
          );
          final boundary = terrain.boundary(index);
          expect(boundary, hasLength(6));
          for (final corner in boundary) {
            final dx = corner.x - center.x;
            final dz = corner.z - center.z;
            expect(math.sqrt(dx * dx + dz * dz), closeTo(1, geometryTolerance));
            // Grid lines sit just above the land, not on a separate flat board.
            expect(
              corner.y - terrain.height(corner.x, corner.z),
              closeTo(.035, geometryTolerance),
            );
          }
          final neighbors = city.adjacentPlots(index).toSet();
          for (var other = 0; other < city.plotCount; other++) {
            if (other == index) continue;
            final destination = terrain.center(other);
            final dx = center.x - destination.x;
            final dz = center.z - destination.z;
            final distance = math.sqrt(dx * dx + dz * dz);
            if (neighbors.contains(other)) {
              expect(
                distance,
                closeTo(math.sqrt(3), geometryTolerance),
                reason: '$index and $other must share a hex edge',
              );
              final otherBoundary = terrain.boundary(other);
              final sharedCorners = boundary.where(
                (corner) => otherBoundary.any(
                  (candidate) =>
                      (corner - candidate).length < geometryTolerance,
                ),
              );
              expect(
                sharedCorners,
                hasLength(2),
                reason: '$index and $other must share both XZ and height',
              );
            } else {
              expect(
                distance,
                greaterThan(math.sqrt(3) + .1),
                reason: '$index must not visually touch non-neighbor $other',
              );
            }
          }
        }
      },
    );

    test(
      '${city.id}: all 25 projected centers remain selectable after orbit and resize',
      () {
        final terrain = terrainFor(city);
        for (final size in [const Size(480, 260), const Size(960, 640)]) {
          for (final view in [
            (azimuth: .18, elevation: .92, zoom: 1.0),
            (azimuth: -.9, elevation: .85, zoom: .9),
            (azimuth: 2.2, elevation: 1.12, zoom: 1.0),
          ]) {
            final projection = CityMapProjection(
              terrain: terrain,
              azimuth: view.azimuth,
              elevation: view.elevation,
              zoom: view.zoom,
            );
            for (var index = 0; index < city.plotCount; index++) {
              final position = projection.center(index, size);
              final reason = '${city.id}: plot $index, viewport $size, $view';
              expect(
                (Offset.zero & size).contains(position),
                isTrue,
                reason: reason,
              );
              expect(
                projection.camera.worldToScreen(terrain.center(index), size),
                position,
                reason: 'Picking and rendered buildings must share a camera',
              );
              expect(
                projection.polygon(index, size).contains(position),
                isTrue,
                reason: reason,
              );
              expect(
                projection.pickPlot(position, size),
                index,
                reason: reason,
              );
            }
            for (final outside in [
              const Offset(-1, 100),
              const Offset(100, -1),
              Offset(size.width + 1, size.height / 2),
              Offset(size.width / 2, size.height + 1),
            ]) {
              expect(projection.pickPlot(outside, size), isNull);
            }
            final beyondLand = projection.camera.worldToScreen(
              terrain.surfacePoint(
                terrain.halfWidth + 2,
                terrain.halfDepth + 2,
              ),
              size,
            )!;
            expect(projection.pickPlot(beyondLand, size), isNull);
          }
        }
      },
    );
  }

  test('crater rims remain continuous at the neighboring terrain boundary', () {
    final terrain = CityTerrain(
      earth: false,
      columns: 2,
      rows: 1,
      plots: const [
        ScenePlot(index: 0, terrain: 'crater', terrainName: 'クレーター'),
        ScenePlot(index: 1, terrain: 'plain', terrainName: '平地'),
      ],
    );
    final crater = terrain.center(0);
    final plain = terrain.center(1);
    final boundaryX = (crater.x + plain.x) / 2;
    // Crossing the closest-plot boundary must not switch a whole rim on/off.
    // The original discontinuity was about .29 world units here; numerical
    // sampling of a continuous slope is far smaller than .001 world units.
    final left = terrain.height(boundaryX - 1e-5, crater.z);
    final right = terrain.height(boundaryX + 1e-5, crater.z);
    expect(left, closeTo(right, .001));
  });

  test('picking rejects the rectangle corners outside a projected hex', () {
    final terrain = CityTerrain(
      earth: true,
      columns: 1,
      rows: 1,
      plots: const [ScenePlot(index: 0, terrain: 'plain', terrainName: '平地')],
    );
    const size = Size(480, 320);
    for (final azimuth in [.18, .8, 2.2]) {
      final projection = CityMapProjection(terrain: terrain, azimuth: azimuth);
      final polygon = projection.polygon(0, size);
      final bounds = polygon.getBounds();
      final center = projection.center(0, size);
      expect(projection.pickPlot(center, size), 0);
      final inset = math.min(bounds.width, bounds.height) * .02;
      final rectangularCorners = [
        bounds.topLeft + Offset(inset, inset),
        bounds.topRight + Offset(-inset, inset),
        bounds.bottomLeft + Offset(inset, -inset),
        bounds.bottomRight - Offset(inset, inset),
      ];
      final hexExterior = rectangularCorners.where(
        (point) => !polygon.contains(point),
      );
      expect(hexExterior.length, greaterThanOrEqualTo(2));
      for (final point in hexExterior) {
        expect(bounds.contains(point), isTrue);
        expect(projection.pickPlot(point, size), isNull);
      }
      final corners = projection.corners(0, size);
      for (var edge = 0; edge < corners.length; edge++) {
        final midpoint =
            (corners[edge] + corners[(edge + 1) % corners.length]) / 2;
        final direction = midpoint - center;
        expect(projection.pickPlot(center + direction * .9, size), 0);
        expect(projection.pickPlot(center + direction * 1.1, size), isNull);
      }
    }
  });

  test(
    'construction and upgrades keep the same land position and boundary',
    () {
      final city = GameContent.cities['earth_delta']!;
      final original = terrainFor(city);
      final developed = CityTerrain(
        earth: true,
        columns: city.width,
        rows: city.height,
        plots: [
          for (final plot in original.plots)
            ScenePlot(
              index: plot.index,
              terrain: plot.terrain,
              terrainName: plot.terrainName,
              districtId: plot.index == 0 ? 'housing' : null,
              districtName: plot.index == 0 ? '住宅地区' : null,
              level: plot.index == 0 ? 2 : 0,
              workState: plot.index == 1
                  ? SceneWorkState.building
                  : SceneWorkState.none,
            ),
        ],
      );
      for (var index = 0; index < city.plotCount; index++) {
        expect(developed.center(index), original.center(index));
        expect(developed.boundary(index), original.boundary(index));
      }
    },
  );
}
