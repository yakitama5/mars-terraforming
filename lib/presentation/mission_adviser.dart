import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'strategy_colors.dart';

enum MinaExpression {
  normal('assets/images/mission_control.png'),
  joy('assets/images/mina_joy.png'),
  anger('assets/images/mina_anger.png'),
  sorrow('assets/images/mina_sorrow.png'),
  delight('assets/images/mina_delight.png');

  const MinaExpression(this.assetPath);
  final String assetPath;
}

/// Short, intermittent portrait gestures never animate the frame or background.
/// Timers leave the frame scheduler idle between gestures, including in tests.
class MinaAvatar extends StatefulWidget {
  const MinaAvatar({
    super.key,
    this.size = 40,
    this.semanticLabel,
    this.expression = MinaExpression.normal,
  });

  final double size;
  final String? semanticLabel;
  final MinaExpression expression;

  @override
  State<MinaAvatar> createState() => _MinaAvatarState();
}

class _MinaAvatarState extends State<MinaAvatar>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _blinkAsset = 'assets/images/mina_blink.png';
  static const _idleInterval = Duration(seconds: 5);
  static const _blinkDuration = Duration(milliseconds: 120);
  late final AnimationController _motion;
  Timer? _idleTimer, _blinkTimer;
  bool _blinking = false;
  bool _active = false;
  bool _attached = true;
  bool _environmentAllowsMotion = false;
  bool _foreground = true;
  ImageProvider<Object>? _blinkProvider;
  double? _blinkPixelRatio;
  int _blinkLoadGeneration = 0;
  bool _blinkReady = false;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _environmentAllowsMotion =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true) &&
        !MediaQuery.disableAnimationsOf(context);
    _precacheBlink();
    _syncPlayback();
  }

  @override
  void didUpdateWidget(covariant MinaAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.size != widget.size ||
        oldWidget.expression != widget.expression) {
      _precacheBlink();
    }
    if (oldWidget.expression == widget.expression) return;
    _blinkTimer?.cancel();
    _blinking = false;
    if (_active) {
      _motion.forward(from: 0);
      _scheduleIdle();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncPlayback();
  }

  @override
  void deactivate() {
    _attached = false;
    _syncPlayback(resetMotion: false);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _attached = true;
    _syncPlayback();
  }

  void _syncPlayback({bool resetMotion = true}) {
    final active = _attached && _foreground && _environmentAllowsMotion;
    if (active == _active) return;
    _active = active;
    _idleTimer?.cancel();
    _blinkTimer?.cancel();
    if (active) {
      _motion.forward(from: 0);
      _scheduleIdle();
    } else {
      _motion.stop();
      if (resetMotion) _motion.value = 0;
      if (_blinking) {
        _blinking = false;
        // During deactivation the next build, if any, already sees open eyes.
        if (_attached) setState(() {});
      }
    }
  }

  void _scheduleIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleInterval, () {
      if (!mounted || !_active) return;
      _motion.forward(from: 0);
      if (widget.expression == MinaExpression.normal && _blinkReady) {
        setState(() => _blinking = true);
        _blinkTimer = Timer(_blinkDuration, () {
          if (!mounted || !_active) return;
          setState(() => _blinking = false);
        });
      }
      _scheduleIdle();
    });
  }

  ImageProvider<Object> _imageProvider(String asset) =>
      ResizeImage.resizeIfNeeded(
        (widget.size * 3).round(),
        null,
        AssetImage(asset, bundle: DefaultAssetBundle.of(context)),
      );

  void _precacheBlink() {
    if (widget.expression != MinaExpression.normal ||
        !_environmentAllowsMotion) {
      return;
    }
    final provider = _imageProvider(_blinkAsset);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    if (provider == _blinkProvider && pixelRatio == _blinkPixelRatio) return;
    _blinkProvider = provider;
    _blinkPixelRatio = pixelRatio;
    _blinkReady = false;
    final generation = ++_blinkLoadGeneration;
    var failed = false;
    unawaited(
      precacheImage(provider, context, onError: (_, _) => failed = true).then((
        _,
      ) {
        if (mounted && generation == _blinkLoadGeneration) {
          _blinkReady = !failed;
        }
      }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    _blinkTimer?.cancel();
    _motion.dispose();
    super.dispose();
  }

  Widget _portrait(String asset, {Key? key}) => Image(
    image: _imageProvider(asset),
    key: key,
    fit: BoxFit.cover,
    alignment: Alignment.center,
    gaplessPlayback: true,
    excludeFromSemantics: true,
    errorBuilder: (_, _, _) => asset != MinaExpression.normal.assetPath
        ? _portrait(
            MinaExpression.normal.assetPath,
            key: const Key('mina-normal-fallback'),
          )
        : Icon(
            Icons.support_agent,
            size: widget.size * 0.6,
            color: strategyBlue,
          ),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.semanticLabel,
    excludeSemantics: true,
    child: Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: strategySelected,
        shape: BoxShape.circle,
        border: Border.all(color: strategyBlue.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _motion,
          child: _portrait(
            _blinking ? _blinkAsset : widget.expression.assetPath,
            key: const Key('mina-portrait'),
          ),
          builder: (context, child) {
            final phase = _motion.value;
            final sway = math.sin(phase * math.pi * 2);
            return Transform.translate(
              key: const Key('mina-portrait-motion'),
              offset: Offset(
                sway * widget.size * .012,
                math.sin(phase * math.pi) * widget.size * .025,
              ),
              child: Transform.rotate(
                angle: sway * .025,
                alignment: const Alignment(0, .5),
                child: child,
              ),
            );
          },
        ),
      ),
    ),
  );
}
