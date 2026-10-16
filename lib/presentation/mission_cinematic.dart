import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../rendering/opening_cinematic_scene.dart';
import 'strategy_colors.dart';
import 'mission_sound.dart';

typedef CinematicSceneBuilder = Widget Function(
  BuildContext context,
  double progress,
  VoidCallback onReady,
  ValueChanged<Object> onError,
);

/// The film has its own clock: it never advances or awards game progress.
class MissionCinematic extends StatefulWidget {
  const MissionCinematic({
    super.key,
    required this.onFinished,
    this.renderScene = true,
    this.sceneBuilder,
    this.audioTrack,
  });

  final VoidCallback onFinished;
  final bool renderScene;
  final CinematicSceneBuilder? sceneBuilder;
  final MissionAudioTrack? audioTrack;
  static const duration = Duration(seconds: 40);
  static const chapters = [
    ('都市開発', '小さな街の灯りが、未来をつくる。', '学び、つくり、挑み続ける。'),
    ('ロケット打ち上げ', '積み重ねた知恵を、空へ。', '受け継いだ技術が、重力を越える。'),
    ('月面基地', '月に、次の足場を。', '遠くへ行くために、つながる。'),
    ('火星探査', 'まだ知らない地平を、拓く。', '一歩の探査が、未来の暮らしを支える。'),
    ('火星移住', 'いつか、この星を故郷と呼ぶ。', 'その未来は、あなたの最初の一手から。'),
  ];

  @override
  State<MissionCinematic> createState() => _MissionCinematicState();
}

class _MissionCinematicState extends State<MissionCinematic>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _film;
  bool _ready = false;
  bool _failed = false;
  bool _paused = false;
  bool _foreground = true;
  bool _enabled = true;
  bool _reduceMotion = false;
  bool _finished = false;
  MissionAudioTrack? _audio;
  bool _audioReady = false;
  bool _audioBlocked = false;
  bool _audioPlaying = false;
  int _audioRevision = 0;

  bool get _hasAudio =>
      widget.audioTrack != null ||
      (widget.renderScene && widget.sceneBuilder == null);

  Future<void> _prepareAudio() async {
    final audio =
        widget.audioTrack ??
        AssetMissionAudioTrack((await MissionAudioCatalog.load()).openingAsset);
    if (!mounted || _finished) {
      await audio.dispose();
      return;
    }
    _audio = audio;
    try {
      await audio.prepare();
      if (!mounted || _finished) return;
      setState(() => _audioReady = true);
      _syncAudio();
    } catch (_) {
      if (mounted && !_finished) setState(() => _audioBlocked = true);
    }
  }

  void _syncAudio() {
    final audio = _audio;
    if (audio == null) return;
    final shouldPlay =
        _audioReady &&
        _film.isAnimating &&
        missionSoundEnabled.value &&
        !_audioBlocked &&
        !_finished;
    if (shouldPlay == _audioPlaying) return;
    _audioPlaying = shouldPlay;
    final revision = ++_audioRevision;
    final operation = shouldPlay
        ? audio.play(
            Duration(
              microseconds:
                  (MissionCinematic.duration.inMicroseconds * _film.value)
                      .round(),
            ),
          )
        : audio.pause();
    unawaited(
      operation.catchError((Object _) {
        if (!mounted || _finished || revision != _audioRevision) return;
        setState(() {
          _audioBlocked = true;
          _audioPlaying = false;
        });
      }),
    );
  }

  void _soundPreferenceChanged() {
    if (!mounted) return;
    setState(() {});
    _syncAudio();
  }

  Future<void> _retryAudio() async {
    await _audio?.dispose();
    _audio = null;
    if (mounted && !_finished) await _prepareAudio();
  }

  void _toggleSound() {
    if (_audioBlocked) {
      // Browser autoplay needs a gesture. Replay from the first shot so the
      // player hears the complete score instead of joining half way through.
      setState(() => _audioBlocked = false);
      _film.stop();
      _film.value = 0;
      _paused = false;
      missionSoundEnabled.value = true;
      if (!_audioReady) {
        unawaited(_retryAudio());
      }
      _syncPlayback();
    } else {
      missionSoundEnabled.value = !missionSoundEnabled.value;
    }
  }

  @override
  void initState() {
    super.initState();
    _film =
        AnimationController(vsync: this, duration: MissionCinematic.duration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _finish();
          });
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    missionSoundEnabled.addListener(_soundPreferenceChanged);
    if (_hasAudio) unawaited(_prepareAudio());
    if (!widget.renderScene && widget.sceneBuilder == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onReady());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _enabled =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _syncPlayback();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncPlayback();
  }

  void _syncPlayback() {
    if (_ready &&
        !_failed &&
        !_paused &&
        !_reduceMotion &&
        _foreground &&
        _enabled &&
        !_finished) {
      _film.forward();
    } else {
      _film.stop();
    }
    _syncAudio();
  }

  void _onReady() {
    if (!mounted || _ready || _failed) return;
    setState(() => _ready = true);
    _syncPlayback();
  }

  void _onError(Object error) {
    if (!mounted || _failed) return;
    setState(() => _failed = true);
    _syncPlayback();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _film.stop();
    _syncAudio();
    widget.onFinished();
  }

  void _nextStill() {
    final chapter = (_film.value * 5).floor().clamp(0, 4);
    if (chapter == 4) {
      _finish();
    } else {
      _film.value = (chapter + 1) / 5;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    missionSoundEnabled.removeListener(_soundPreferenceChanged);
    _audioRevision++;
    unawaited(_audio?.dispose());
    _film.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const Key('opening-cinematic'),
    color: strategyBackground,
    child: AnimatedBuilder(
      animation: _film,
      builder: (context, _) {
        final chapter = (_film.value * 5).floor().clamp(0, 4);
        final local = (_film.value * 5 - chapter).clamp(0.0, 1.0);
        final caption = MissionCinematic.chapters[chapter];
        final sceneProgress = _reduceMotion ? (chapter + .4) / 5 : _film.value;
        final fade = _reduceMotion
            ? 0.0
            : math.max(
                ((.07 - local) / .07).clamp(0.0, 1.0),
                ((local - .93) / .07).clamp(0.0, 1.0),
              );
        final scene =
            widget.sceneBuilder?.call(
              context,
              sceneProgress,
              _onReady,
              _onError,
            ) ??
            (widget.renderScene
                ? OpeningCinematicScene(
                    progress: sceneProgress,
                    onReady: _onReady,
                    onError: _onError,
                  )
                : const SizedBox.expand());
        return Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(child: scene),
            IgnorePointer(
              child: ColoredBox(color: Colors.black.withValues(alpha: fade)),
            ),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, .24, .56, 1],
                    colors: [
                      Color(0xb3081424),
                      Colors.transparent,
                      Colors.transparent,
                      Color(0xe6081424),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'BLUE HORIZON  /  未来への序章',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xffb9ddff),
                              fontSize: 11,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ),
                        if (_hasAudio && !_reduceMotion)
                          IconButton(
                            key: const Key('cinematic-sound'),
                            tooltip: _audioBlocked
                                ? '音楽つきで最初から見る'
                                : missionSoundEnabled.value
                                ? '音を消す'
                                : '音を出す',
                            onPressed: _toggleSound,
                            icon: Icon(
                              missionSoundEnabled.value && !_audioBlocked
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_off_rounded,
                            ),
                          ),
                        if (_ready && !_failed && !_reduceMotion)
                          IconButton(
                            key: const Key('cinematic-pause'),
                            tooltip: _paused ? 'OPを再生' : 'OPを一時停止',
                            onPressed: () {
                              setState(() => _paused = !_paused);
                              _syncPlayback();
                            },
                            icon: Icon(
                              _paused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                            ),
                          ),
                        TextButton.icon(
                          key: const Key('opening-cinematic-skip'),
                          onPressed: _finish,
                          icon: const Icon(Icons.skip_next_rounded, size: 18),
                          label: const Text('物語へ'),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (_audioBlocked && !_reduceMotion)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: OutlinedButton.icon(
                          key: const Key('cinematic-enable-sound'),
                          onPressed: _toggleSound,
                          icon: const Icon(Icons.volume_up_rounded),
                          label: const Text('音楽つきで最初から見る'),
                        ),
                      ),
                    if (!_ready || _failed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Text(
                          _failed
                              ? '映像を読み込めませんでした。「物語へ」から始められます。'
                              : '未来への航路を準備しています…',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: strategyText),
                        ),
                      )
                    else
                      Flexible(
                        flex: 0,
                        child: SingleChildScrollView(
                          child: AnimatedSwitcher(
                            duration: Duration(
                              milliseconds: _reduceMotion ? 0 : 400,
                            ),
                            child: Column(
                              key: ValueKey(chapter),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${chapter + 1}  /  ${caption.$1}',
                                  key: const Key('cinematic-chapter'),
                                  style: const TextStyle(
                                    color: Color(0xffa6d5ff),
                                    fontSize: 11,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  caption.$2,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize:
                                        MediaQuery.sizeOf(context).width < 650
                                        ? 20
                                        : 26,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  caption.$3,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xffd5e5f5),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    if (_reduceMotion && _ready && !_failed)
                      FilledButton(
                        key: const Key('cinematic-next-still'),
                        onPressed: _nextStill,
                        child: Text(chapter < 4 ? '次の場面' : '物語を始める'),
                      )
                    else
                      Semantics(
                        label: '未来への序章、${chapter + 1}番目の場面',
                        child: ExcludeSemantics(
                          child: Row(
                            children: List.generate(
                              5,
                              (index) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                  ),
                                  child: LinearProgressIndicator(
                                    value: (_film.value * 5 - index).clamp(
                                      0.0,
                                      1.0,
                                    ),
                                    minHeight: 2,
                                    color: strategyBlue,
                                    backgroundColor: Colors.white24,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
