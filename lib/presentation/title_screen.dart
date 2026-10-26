import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/game_state.dart';
import '../rendering/title_scene.dart';
import 'title_scene_data.dart';

typedef TitleSceneBuilder = Widget Function(
  BuildContext context,
  VoidCallback onReady,
  ValueChanged<Object> onError,
);

/// 起動ごとの入口。開始の操作や演出状態はセーブしない。
class TitleScreen extends StatefulWidget {
  const TitleScreen({
    super.key,
    required this.game,
    required this.onStart,
    this.renderScene = true,
    this.sceneBuilder,
  });

  final GameState game;
  final VoidCallback onStart;
  final bool renderScene;
  @visibleForTesting
  final TitleSceneBuilder? sceneBuilder;

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _departure;
  bool _starting = false;
  bool _backgroundReady = false;

  @override
  void initState() {
    super.initState();
    _backgroundReady = !widget.renderScene && widget.sceneBuilder == null;
    _departure = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    if (!MediaQuery.disableAnimationsOf(context)) {
      try {
        await _departure.forward().orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (mounted) widget.onStart();
  }

  void _revealBackground() {
    if (!mounted || _starting || _backgroundReady) return;
    setState(() => _backgroundReady = true);
  }

  @override
  void dispose() {
    _departure.dispose();
    super.dispose();
  }

  void _showCredits() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('素材のクレジット'),
        content: const SingleChildScrollView(
          child: SelectableText(
            '星空\nESO/S. Brunier\n'
            'https://www.eso.org/public/images/eso0932a/\n'
            'Creative Commons Attribution 4.0\nhttps://creativecommons.org/licenses/by/4.0/\n'
            '全天の遠景として使用し、縮小・露光・色の調整を行っています。\n\n'
            '火星\nNASA/JPL/USGS・Arizona State University\nNASA/MGS/MOLA Science Team・NASA PDS\n\n'
            '地球\nNASA Earth Observatory・NASA Goddard Space Flight Center\n'
            'Reto Stöckli・Robert Simmon・Joshua Stevens・Miguel Román\n\n'
            '木星・土星\nNASA Visualization Technology Applications and Development (VTAD)\n'
            '雲画像を球面へ再投影し、環の半径方向画像を使用しています。\n\n'
            '宇宙機・小惑星\nNASA / NASA 3D Resources\n'
            'NASA / Michael D. Carbajal\nNASA / Christopher R. Meaney\n'
            'NASA/Goddard/University of Arizona\n\n'
            '天体の配置・運動の速さ・飛行経路と未来の開発は本作の演出です。'
            'NASA・ESOによる本作の推薦や公認を意味しません。',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        FocusableActionDetector(
          autofocus: true,
          mouseCursor: SystemMouseCursors.click,
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _start();
                return null;
              },
            ),
          },
          child: Semantics(
            excludeSemantics: true,
            button: true,
            label: 'タップまたはクリックしてスタート',
            enabled: !_starting,
            onTap: _starting ? null : _start,
            child: GestureDetector(
              key: const Key('title-start'),
              behavior: HitTestBehavior.opaque,
              onTap: _starting ? null : _start,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.renderScene || widget.sceneBuilder != null)
                    AnimatedOpacity(
                      key: const Key('title-background-fade'),
                      opacity: _backgroundReady ? 1 : 0,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 900),
                      curve: Curves.easeOut,
                      child: IgnorePointer(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            widget.sceneBuilder?.call(
                                  context,
                                  _revealBackground,
                                  (_) => _revealBackground(),
                                ) ??
                                TitleScene(
                                  snapshot: buildTitleSceneSnapshot(
                                    widget.game,
                                  ),
                                  onReady: _revealBackground,
                                  onError: (_) => _revealBackground(),
                                ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x55020710),
                                    Color(0x00020710),
                                    Color(0x00020710),
                                    Color(0x55020710),
                                  ],
                                  stops: [0, .32, .77, 1],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  IgnorePointer(
                    child: SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final height = constraints.maxHeight;
                          final scale = math
                              .min(height / 620, constraints.maxWidth / 1050)
                              .clamp(.48, 1.5);
                          return Stack(
                            children: [
                              Positioned(
                                top: height * .105,
                                left: 20,
                                right: 20,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'A WORLD BEYOND THE HORIZON',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: (10 * scale).clamp(8, 15),
                                        letterSpacing: 4.5 * scale,
                                        color: const Color(0xffa5bfce),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    SizedBox(height: 13 * scale),
                                    Text(
                                      'DEAR MARS',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 77 * scale,
                                        height: 1.05,
                                        letterSpacing: 12 * scale,
                                        fontWeight: FontWeight.w300,
                                        color: const Color(0xfff5f1e9),
                                        shadows: const [
                                          Shadow(
                                            color: Color(0xaa030812),
                                            blurRadius: 24,
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(height: 13 * scale),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 42 * scale,
                                          child: const Divider(
                                            color: Color(0xffbb8c63),
                                            thickness: .6,
                                          ),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 18 * scale,
                                          ),
                                          child: Text(
                                            '火星開発計画',
                                            style: TextStyle(
                                              fontSize: (12 * scale).clamp(
                                                10,
                                                18,
                                              ),
                                              letterSpacing: 6 * scale,
                                              color: const Color(0xffc2b9ac),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 42 * scale,
                                          child: const Divider(
                                            color: Color(0xffbb8c63),
                                            thickness: .6,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Positioned(
                                top: height * .47,
                                left: 12,
                                right: 12,
                                child: Column(
                                  children: [
                                    Text(
                                      kIsWeb
                                          ? 'CLICK TO START'
                                          : 'TAP TO START',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: (12 * scale).clamp(11, 18),
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 4 * scale,
                                        color: const Color(0xfff0e9dc),
                                        shadows: const [
                                          Shadow(
                                            color: Color(0xff030812),
                                            blurRadius: 12,
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(height: 8 * scale),
                                    Text(
                                      kIsWeb ? 'クリックしてはじめる' : 'タップしてはじめる',
                                      style: TextStyle(
                                        fontSize: (9 * scale).clamp(10, 14),
                                        letterSpacing: 1.5 * scale,
                                        color: const Color(0xffb3b9bf),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _departure,
                      builder: (_, _) => ColoredBox(
                        color: Colors.black.withValues(alpha: _departure.value),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Sky: ESO/S. Brunier',
                    style: TextStyle(fontSize: 10, color: Color(0xffb2bdc9)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _starting ? null : _showCredits,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xffc8d2dd),
                      textStyle: const TextStyle(fontSize: 10),
                    ),
                    child: const Text('Credits'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
