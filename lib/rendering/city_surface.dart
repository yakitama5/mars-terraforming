import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'city_geometry.dart';

/// Small, deterministic surface maps generated once per scene. They ship as
/// code and need neither remote assets nor an image decode during offline play.
/// Broad terrain colors remain in CityTerrain; this adds fine albedo/normal
/// detail without generating extra grass geometry or changing buildable land.
class CitySurface {
  CitySurface() {
    const size = 256;
    final heights = Float32List(size * size);
    final color = Uint8List(size * size * 4);
    final normal = Uint8List(size * size * 4);
    final waves = Uint8List(size * size * 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        // Periodic value noise with several scales: no seams when UV repeats.
        final broad = _noise(x / size * 8, y / size * 8, 8);
        final grain = _noise(x / size * 64, y / size * 64, 64);
        final fine = _hash(x, y);
        final blade = _noise(x / size * 128, y / size * 32, 32);
        final value = .82 + broad * .10 + grain * .035 + fine * .035;
        final index = (y * size + x) * 4;
        color[index] = (255 * value).round();
        color[index + 1] = (255 * (value + blade * .025)).round();
        color[index + 2] = (255 * (value - .025)).round();
        color[index + 3] = 255;
        heights[y * size + x] = grain * .55 + fine * .15 + blade * .3;
        final wave = math.sin(
          x / size * math.pi * 16 + math.sin(y / size * math.pi * 8) * .8,
        );
        final crossWave = math.cos(
          y / size * math.pi * 24 + math.sin(x / size * math.pi * 4) * .6,
        );
        final n = vm.Vector3(wave * .22, crossWave * .13, 1).normalized();
        waves[index] = (128 + n.x * 127).round();
        waves[index + 1] = (128 + n.y * 127).round();
        waves[index + 2] = (128 + n.z * 127).round();
        waves[index + 3] = 255;
      }
    }
    double sample(int x, int y) => heights[(y % size) * size + x % size];
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final n = vm.Vector3(
          (sample(x - 1, y) - sample(x + 1, y)) * 1.8,
          (sample(x, y - 1) - sample(x, y + 1)) * 1.8,
          1,
        ).normalized();
        final index = (y * size + x) * 4;
        normal[index] = (128 + n.x * 127).round();
        normal[index + 1] = (128 + n.y * 127).round();
        normal[index + 2] = (128 + n.z * 127).round();
        normal[index + 3] = 255;
      }
    }
    ground =
        fs.PhysicallyBasedMaterial(
            baseColorTexture: fs.Texture2D.fromPixels(color, size, size),
            normalTexture: fs.Texture2D.fromPixels(
              normal,
              size,
              size,
              content: fs.TextureContent.normal,
            ),
          )
          ..metallicFactor = 0
          ..roughnessFactor = .94
          ..normalScale = .28;
    soil =
        fs.PhysicallyBasedMaterial(
            normalTexture: fs.Texture2D.fromPixels(
              normal,
              size,
              size,
              content: fs.TextureContent.normal,
            ),
          )
          ..metallicFactor = 0
          ..roughnessFactor = 1
          ..normalScale = .32;
    water =
        fs.PhysicallyBasedMaterial(
            normalTexture: fs.Texture2D.fromPixels(
              waves,
              size,
              size,
              content: fs.TextureContent.normal,
            ),
          )
          ..metallicFactor = .18
          ..roughnessFactor = .28
          ..normalScale = .55;
  }

  late final fs.PhysicallyBasedMaterial ground, water, soil;

  static double _hash(int x, int y) {
    // Integer arithmetic stays exactly reproducible in native Dart and JS.
    var n = (x * 374761393 + y * 668265263 + 9517) & 0x7fffffff;
    n = ((n ^ (n >> 13)) * 127412) & 0x7fffffff;
    n ^= n >> 16;
    return (n & 65535) / 65535;
  }

  static double _noise(double x, double y, int period) {
    final ix = x.floor(), iy = y.floor();
    final tx = x - ix, ty = y - iy;
    final sx = tx * tx * (3 - 2 * tx);
    final sy = ty * ty * (3 - 2 * ty);
    final a = _hash(ix % period, iy % period);
    final b = _hash((ix + 1) % period, iy % period);
    final c = _hash(ix % period, (iy + 1) % period);
    final d = _hash((ix + 1) % period, (iy + 1) % period);
    return (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy;
  }

  /// River and coast share one level, clipped to the same finite circular
  /// boundary as the terrain. Marching polygons follow each bank continuously.
  fs.MeshGeometry waterGeometry(CityTerrain terrain) {
    final positions = <double>[];
    final normals = <double>[];
    final colors = <double>[];
    final uvs = <double>[];
    final indices = <int>[];
    int vertex(double x, double y, double z, vm.Vector3 normal, Color color) {
      final index = positions.length ~/ 3;
      positions.addAll([x, y, z]);
      normals.addAll([normal.x, normal.y, normal.z]);
      uvs.addAll([x / 2.4, z / 2.4]);
      colors.addAll([
        CityTerrain.linearChannel(color.r),
        CityTerrain.linearChannel(color.g),
        CityTerrain.linearChannel(color.b),
        1,
      ]);
      return index;
    }

    Color colorAt(double x, double z) {
      final riverDepth =
          (-terrain.riverDistance(x, z) / terrain.riverHalfWidth(x)).clamp(
            0.0,
            1.0,
          );
      final seaDepth = terrain.hasCoast
          ? (-terrain.coastDistance(x, z) - .20).clamp(0.0, 1.0)
          : 0.0;
      final depth = math.max(riverDepth * .65, seaDepth);
      return Color.lerp(
        const Color(0xff63b6ac),
        const Color(0xff246b83),
        depth,
      )!;
    }

    final up = vm.Vector3(0, 1, 0);
    final radius = terrain.landRadius;
    final steps = (radius * 2 / .16).ceil();
    final step = radius * 2 / steps;
    for (var row = 0; row < steps; row++) {
      final z = -radius + row * step;
      for (var col = 0; col < steps; col++) {
        final x = -radius + col * step;
        var polygon = [
          vm.Vector2(x, z),
          vm.Vector2(x, z + step),
          vm.Vector2(x + step, z + step),
          vm.Vector2(x + step, z),
        ];
        polygon = _clip(polygon, (p) => terrain.waterDistance(p.x, p.y));
        if (polygon.length < 3) continue;
        polygon = _clip(
          polygon,
          (p) => math.sqrt(p.x * p.x + p.y * p.y) - radius,
        );
        if (polygon.length < 3) continue;
        final first = positions.length ~/ 3;
        for (final p in polygon) {
          vertex(
            p.x,
            CityTerrain.waterLevel + .008,
            p.y,
            up,
            colorAt(p.x, p.y),
          );
        }
        for (var i = 1; i < polygon.length - 1; i++) {
          indices.addAll([first, first + i, first + i + 1]);
        }
      }
    }
    // Close the visible cut where a stream or the coast reaches the glass rim.
    // This is the water's cross-section, not a waterfall or infinite sea plane.
    const segments = 384;
    for (var i = 0; i < segments; i++) {
      final angle = i / segments * math.pi * 2;
      final nextAngle = (i + 1) / segments * math.pi * 2;
      var a = vm.Vector2(math.cos(angle) * radius, math.sin(angle) * radius);
      var b = vm.Vector2(
        math.cos(nextAngle) * radius,
        math.sin(nextAngle) * radius,
      );
      final da = terrain.waterDistance(a.x, a.y);
      final db = terrain.waterDistance(b.x, b.y);
      if (da >= 0 && db >= 0) continue;
      if (da >= 0 || db >= 0) {
        final t = da / (da - db);
        final crossing = a + (b - a) * t;
        if (da >= 0) {
          a = crossing;
        } else {
          b = crossing;
        }
      }
      final normal = vm.Vector3(math.cos(angle), 0, math.sin(angle));
      final first = vertex(
        a.x,
        CityTerrain.waterLevel + .008,
        a.y,
        normal,
        colorAt(a.x, a.y),
      );
      vertex(
        b.x,
        CityTerrain.waterLevel + .008,
        b.y,
        normal,
        colorAt(b.x, b.y),
      );
      vertex(
        b.x,
        math.min(terrain.height(b.x, b.y), CityTerrain.waterLevel),
        b.y,
        normal,
        const Color(0xff1a6476),
      );
      vertex(
        a.x,
        math.min(terrain.height(a.x, a.y), CityTerrain.waterLevel),
        a.y,
        normal,
        const Color(0xff1a6476),
      );
      indices.addAll([
        first,
        first + 1,
        first + 2,
        first,
        first + 2,
        first + 3,
      ]);
    }
    return fs.MeshGeometry.fromArrays(
      positions: Float32List.fromList(positions),
      normals: Float32List.fromList(normals),
      colors: Float32List.fromList(colors),
      texCoords: Float32List.fromList(uvs),
      indices: indices,
      retainCpuData: false,
    );
  }

  static List<vm.Vector2> _clip(
    List<vm.Vector2> polygon,
    double Function(vm.Vector2) distance,
  ) {
    if (polygon.isEmpty) return polygon;
    final result = <vm.Vector2>[];
    var previous = polygon.last;
    var previousDistance = distance(previous);
    for (final current in polygon) {
      final currentDistance = distance(current);
      if ((previousDistance <= 0) != (currentDistance <= 0)) {
        final t = previousDistance / (previousDistance - currentDistance);
        result.add(previous + (current - previous) * t);
      }
      if (currentDistance <= 0) result.add(current);
      previous = current;
      previousDistance = currentDistance;
    }
    return result;
  }
}
