import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A session preference, shared by the film and Luna's guided dialogue.
final missionSoundEnabled = ValueNotifier<bool>(true);

class MissionAudioCatalog {
  const MissionAudioCatalog(this.openingAsset, this.voices);
  final String openingAsset;
  final Map<String, String> voices;
  static Future<MissionAudioCatalog>? _loading;

  static Future<MissionAudioCatalog> load() => _loading ??= _read();

  static Future<MissionAudioCatalog> _read() async {
    try {
      final json = jsonDecode(
        await rootBundle.loadString('assets/audio/catalog.json'),
      ) as Map<String, dynamic>;
      return MissionAudioCatalog(
        json['openingAsset'] as String,
        Map<String, String>.from(json['voices'] as Map),
      );
    } catch (_) {
      // Audio availability must never prevent opening a saved world.
      return const MissionAudioCatalog('audio/opening_music.wav', {});
    }
  }
}

abstract interface class MissionAudioTrack {
  Future<void> prepare();
  Future<void> play(Duration position);
  Future<void> pause();
  Future<void> dispose();
}

/// The caller owns the visual clock. Resume always seeks to that clock, while
/// superseded loads/seeks cannot resurrect sound after a skip or route change.
class AssetMissionAudioTrack implements MissionAudioTrack {
  AssetMissionAudioTrack(this.asset);
  final String asset;
  AudioPlayer? _player;
  Future<void>? _preparing;
  Future<void> _pending = Future<void>.value();
  int _revision = 0;
  bool _disposed = false;

  @override
  Future<void> prepare() => _preparing ??= _prepare();

  Future<void> _prepare() async {
    if (_disposed) return;
    final player = _player = AudioPlayer();
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setSource(AssetSource(asset, mimeType: 'audio/wav'));
  }

  @override
  Future<void> play(Duration position) {
    final revision = ++_revision;
    final operation = _pending.catchError((Object _) {}).then((_) async {
      if (_disposed || revision != _revision) return;
      await prepare();
      if (_disposed || revision != _revision) return;
      await _player!.seek(position);
      if (_disposed || revision != _revision) return;
      await _player!.resume();
      if (_disposed || revision != _revision) await _player!.pause();
    });
    _pending = operation;
    return operation;
  }

  @override
  Future<void> pause() async {
    _revision++;
    final player = _player;
    if (player != null && !_disposed) await player.pause();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _revision++;
    try {
      await _player?.pause();
      await _pending;
      await _preparing;
    } catch (_) {
      // Even a rejected autoplay or failed source still owns native resources.
    } finally {
      try {
        await _player?.dispose();
      } catch (_) {
        // A failed native player can already have released its handle.
      }
      _player = null;
    }
  }
}
