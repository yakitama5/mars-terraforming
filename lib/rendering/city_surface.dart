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

  late final fs.PhysicallyBasedMaterial ground, water;

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

  /// A smooth surface over the seabed, following the same authored coast.
  /// It lies outside the coastal plots' construction pads.
  fs.MeshGeometry waterGeometry(CityTerrain terrain) {
    final positions = <double>[];
    final normals = <double>[];
    final colors = <double>[];
    final uvs = <double>[];
    final indices = <int>[];
    const columns = 7;
    final rows = ((terrain.halfDepth + 10) * 2 / .3).ceil();
    final west = -terrain.halfWidth - 10;
    for (var row = 0; row <= rows; row++) {
      final z = -terrain.halfDepth - 10 + row * .3;
      // coastDistance is x - shorelineX.
      final shore = -terrain.coastDistance(0, z) - .20;
      for (var col = 0; col < columns; col++) {
        final t = col / (columns - 1);
        final x = shore + (west - shore) * t;
        final color = Color.lerp(
          const Color(0xff6aa899),
          const Color(0xff20526e),
          math.sqrt(t),
        )!;
        positions.addAll([x, -.045, z]);
        normals.addAll([0, 1, 0]);
        uvs.addAll([x / 3, z / 3]);
        colors.addAll([
          CityTerrain.linearChannel(color.r),
          CityTerrain.linearChannel(color.g),
          CityTerrain.linearChannel(color.b),
          1,
        ]);
      }
    }
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns - 1; col++) {
        final a = row * columns + col;
        final b = a + columns;
        indices.addAll([a, a + 1, b + 1, a, b + 1, b]);
      }
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
}
