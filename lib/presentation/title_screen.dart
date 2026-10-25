import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/game_state.dart';
import '../rendering/title_scene.dart';
import 'title_scene_data.dart';

/// 起動ごとの入口。開始の操作や演出状態はセーブしない。
class TitleScreen extends StatefulWidget {
  const TitleScreen({
    super.key,
    required this.game,
    required this.onStart,
    this.renderScene = true,
  });

  final GameState game;
  final VoidCallback onStart;
  final bool renderScene;

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _departure;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _departure = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    if (!MediaQuery.disableAnimationsOf(context)) await _departure.forward();
    if (mounted) widget.onStart();
  }

  @override
  void dispose() {
    _departure.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff030812),
    body: FocusableActionDetector(
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
        onTap: _start,
        child: GestureDetector(
          key: const Key('title-start'),
          behavior: HitTestBehavior.opaque,
          onTap: _start,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.renderScene)
                TitleScene(snapshot: buildTitleSceneSnapshot(widget.game))
              else
                const ColoredBox(color: Color(0xff030812)),
              const IgnorePointer(
                child: DecoratedBox(
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
                                          fontSize: (12 * scale).clamp(10, 18),
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
                                  kIsWeb ? 'CLICK TO START' : 'TAP TO START',
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
  );
}
