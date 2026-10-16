import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mission_adviser.dart';
import 'strategy_colors.dart';

/// A bounded conversation surface. The parent owns progression and actions;
/// tapping the speech only reveals its text and never advances the story.
class MissionDialogue extends StatefulWidget {
  const MissionDialogue({
    super.key,
    required this.text,
    this.expression = MinaExpression.normal,
    this.speaker = 'ルナ',
    this.title,
    this.actions,
    this.dialogueKey,
    this.portraitSize,
  });

  final String text;
  final MinaExpression expression;
  final String speaker;
  final String? title;
  final Widget? actions;
  final Object? dialogueKey;
  final double? portraitSize;

  @override
  State<MissionDialogue> createState() => _MissionDialogueState();
}

class _MissionDialogueState extends State<MissionDialogue>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _reveal;
  late final AnimationController _entrance;
  final _scroll = ScrollController();
  late List<String> _characters;
  bool _reduceMotion = false;
  bool _environmentEnabled = false;
  bool _foreground = true;
  bool _attached = true;

  @override
  void initState() {
    super.initState();
    _characters = widget.text.characters.toList();
    _reveal = AnimationController(vsync: this, duration: _readingDuration);
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  Duration get _readingDuration => Duration(
    milliseconds: (_characters.length * 26).clamp(240, 2400).toInt(),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _environmentEnabled =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant MissionDialogue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dialogueKey == widget.dialogueKey &&
        oldWidget.text == widget.text &&
        oldWidget.title == widget.title &&
        oldWidget.speaker == widget.speaker) {
      return;
    }
    _characters = widget.text.characters.toList();
    _reveal.duration = _readingDuration;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _reveal.value = _reduceMotion ? 1 : 0;
    _entrance.value = _reduceMotion ? 1 : 0;
    _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncMotion();
  }

  @override
  void deactivate() {
    _attached = false;
    _reveal.stop();
    _entrance.stop();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _attached = true;
    _syncMotion();
  }

  void _syncMotion() {
    if (_reduceMotion) {
      if (_reveal.value != 1) _reveal.value = 1;
      if (_entrance.value != 1) _entrance.value = 1;
      return;
    }
    if (!_attached || !_foreground || !_environmentEnabled) {
      _reveal.stop();
      _entrance.stop();
      return;
    }
    if (_reveal.value < 1) _reveal.forward();
    if (_entrance.value < 1) _entrance.forward();
  }

  void _showAll() {
    if (_reveal.value < 1) _reveal.value = 1;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _reveal.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.hasBoundedHeight
          ? math.min(constraints.maxHeight, 360.0)
          : 260.0;
      final compact = constraints.maxWidth < 650;
      final requestedSize = widget.portraitSize ?? (compact ? 160.0 : 220.0);
      final portraitSize = math.min(
        math.min(requestedSize, height),
        constraints.maxWidth * .4,
      );
      return SizedBox(
        height: height,
        child: AnimatedBuilder(
          animation: Listenable.merge([_reveal, _entrance]),
          builder: (context, _) {
            final progress = Curves.easeOutCubic.transform(_entrance.value);
            final visible = (_characters.length * _reveal.value).ceil();
            return Opacity(
              key: const Key('mission-dialogue-entrance'),
              opacity: .65 + progress * .35,
              child: Transform.translate(
                offset: Offset(0, (1 - progress) * 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MinaPortrait(
                      key: const Key('mission-dialogue-portrait'),
                      size: portraitSize,
                      expression: widget.expression,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _bubble(visible, compact)),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );

  Widget _bubble(int visible, bool compact) {
    final panelColor = strategyPanel.withValues(alpha: .82);
    final borderColor = strategyBlue.withValues(alpha: .65);
    final label = [
      widget.speaker,
      if (widget.title != null) widget.title!,
      widget.text,
    ].join('。');
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -10,
          bottom: 26,
          child: CustomPaint(
            size: const Size(12, 24),
            painter: _SpeechTail(fill: panelColor, border: borderColor),
          ),
        ),
        Positioned.fill(
          child: Material(
            color: panelColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: borderColor),
            ),
            child: Padding(
              padding: EdgeInsets.all(compact ? 12 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      widget.speaker,
                      style: const TextStyle(
                        color: strategyBlue,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Semantics(
                      key: const Key('mission-dialogue-announcement'),
                      container: true,
                      liveRegion: true,
                      label: label,
                      onTap: _showAll,
                      child: ExcludeSemantics(
                        child: GestureDetector(
                          key: const Key('mission-dialogue-reveal'),
                          behavior: HitTestBehavior.opaque,
                          excludeFromSemantics: true,
                          onTap: _showAll,
                          child: Scrollbar(
                            controller: _scroll,
                            child: SingleChildScrollView(
                              key: const Key('mission-dialogue-scroll'),
                              controller: _scroll,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (widget.title != null) ...[
                                    Text(
                                      widget.title!,
                                      style: const TextStyle(
                                        color: strategyText,
                                        fontSize: 19,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  Text.rich(
                                    key: const Key('mission-dialogue-text'),
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: _characters
                                              .take(visible)
                                              .join(),
                                        ),
                                        TextSpan(
                                          text: _characters
                                              .skip(visible)
                                              .join(),
                                          style: const TextStyle(
                                            color: Colors.transparent,
                                          ),
                                        ),
                                      ],
                                    ),
                                    style: const TextStyle(
                                      color: strategyText,
                                      fontSize: 16,
                                      height: 1.55,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.actions != null) ...[
                    const SizedBox(height: 10),
                    widget.actions!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SpeechTail extends CustomPainter {
  const _SpeechTail({required this.fill, required this.border});
  final Color fill, border;

  @override
  void paint(Canvas canvas, Size size) {
    final tail = Path()
      ..moveTo(size.width, 0)
      ..lineTo(0, size.height / 2)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(tail, Paint()..color = fill);
    canvas.drawPath(
      Path()
        ..moveTo(size.width, 0)
        ..lineTo(0, size.height / 2)
        ..lineTo(size.width, size.height),
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_SpeechTail oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.border != border;
}
