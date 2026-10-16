import 'dart:async';

import 'package:flutter/material.dart';

import 'mission_sound.dart';

/// Recorded English dialogue follows each tutorial step, once per appearance.
/// Missing narration leaves the Japanese text fully usable offline.
class MissionSpeech extends StatefulWidget {
  const MissionSpeech({
    super.key,
    required this.audioId,
    required this.child,
    this.enabled = true,
  });
  final String audioId;
  final Widget child;
  final bool enabled;

  @override
  State<MissionSpeech> createState() => _MissionSpeechState();
}

class _MissionSpeechState extends State<MissionSpeech>
    with WidgetsBindingObserver {
  MissionAudioTrack? _track;
  final Stopwatch _clock = Stopwatch();
  bool _foreground = true;
  bool _visible = true;
  bool _ready = false;
  bool _playing = false;
  int _playRevision = 0;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    missionSoundEnabled.addListener(_sync);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(MissionSpeech oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioId != widget.audioId) {
      unawaited(_load());
    } else if (oldWidget.enabled != widget.enabled) {
      _sync();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _sync();
  }

  Future<void> _load() async {
    final revision = ++_revision;
    final oldTrack = _track;
    _track = null;
    _ready = false;
    _playing = false;
    _playRevision++;
    _clock
      ..stop()
      ..reset();
    await oldTrack?.dispose();
    final catalog = await MissionAudioCatalog.load();
    if (!mounted || revision != _revision) return;
    final asset = catalog.voices[widget.audioId];
    if (asset == null) return;
    final track = _track = AssetMissionAudioTrack(asset);
    try {
      await track.prepare();
      if (mounted && revision == _revision) {
        _ready = true;
        _sync();
      }
    } catch (_) {
      // Continue the forced tutorial even when sound cannot be decoded.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    final track = _track;
    if (track == null || !_ready) return;
    final shouldPlay =
        widget.enabled && _foreground && _visible && missionSoundEnabled.value;
    if (shouldPlay == _playing) return;
    _playing = shouldPlay;
    final revision = ++_playRevision;
    if (shouldPlay) {
      final position = _clock.elapsed;
      unawaited(
        track
            .play(position)
            .then((_) {
              if (mounted &&
                  revision == _playRevision &&
                  track == _track &&
                  _playing) {
                _clock.start();
              }
            })
            .catchError((Object _) {
              if (mounted && revision == _playRevision && track == _track) {
                _playing = false;
                _clock.stop();
              }
            }),
      );
    } else {
      _clock.stop();
      unawaited(track.pause().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    _revision++;
    _playRevision++;
    _clock.stop();
    missionSoundEnabled.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_track?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
