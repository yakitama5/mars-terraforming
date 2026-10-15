import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/mission_identity.dart';
import 'strategy_widgets.dart';
import 'mission_adviser.dart';

const missionOpeningAsset = 'assets/images/blue_horizon.png';

/// Offline opening: generated key art with gentle, finite camera motion.
/// Story pages only advance on a tap; there is no reading time limit.
class MissionOpening extends StatefulWidget {
  const MissionOpening({
    super.key,
    required this.controller,
    this.replay = false,
    this.onClose,
  });

  final GameController controller;
  final bool replay;
  final VoidCallback? onClose;

  @override
  State<MissionOpening> createState() => _MissionOpeningState();
}

class _MissionOpeningState extends State<MissionOpening>
    with SingleTickerProviderStateMixin {
  late final AnimationController camera;
  final storyScroll = ScrollController(keepScrollOffset: false);
  int chapter = 0;
  bool naming = false;
  static const stories = [
    (
      '青い星から、次の故郷へ',
      '地球の空を見上げるたび、人類は問い続けてきました。\nあの赤い星にも、いつか日常をつくれるだろうか。',
      '地球で育てた技術を、火星の暮らしへ。',
    ),
    (
      'あなたは、計画の指揮官',
      '国際宇宙開発機関に託されたのは、小さな街と最初の研究所。\n街の収入で研究を進め、工場でつくり、ロケットで届けましょう。',
      '街を育てる → 研究する → つくる → 届ける',
    ),
    (
      '最初の灯りを、火星に',
      '最初の目標は、人が暮らす閉鎖居住区。\nその先に、空気も水も守られた屋外の暮らしを目指す長い開発計画が待っています。',
      '最初の約1時間は、秘書ミナが一歩ずつ案内します。',
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (!widget.replay) widget.controller.beginOpening();
    camera = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..forward();
  }

  @override
  void dispose() {
    camera.dispose();
    storyScroll.dispose();
    super.dispose();
  }

  void _setChapter(int value) {
    if (storyScroll.hasClients) storyScroll.jumpTo(0);
    setState(() => chapter = value);
    camera.forward(from: 0);
  }

  void _next() {
    if (chapter < stories.length - 1) {
      _setChapter(chapter + 1);
    } else if (widget.replay) {
      widget.onClose?.call();
    } else {
      setState(() => naming = true);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      if (controller.engine == null) {
        return Scaffold(
          body: Center(child: Text(controller.error ?? '保存状態を確認しています')),
        );
      }
      if (naming) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: MissionNameForm(
                  controller: controller,
                  finishOpening: true,
                  onDone: () {},
                  onCancel: controller.busy ? null : controller.skipOpening,
                ),
              ),
            ),
          ),
        );
      }
      final story = stories[chapter];
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      return Scaffold(
        key: const Key('mission-opening'),
        body: Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: AnimatedBuilder(
                animation: camera,
                builder: (context, child) => Transform.scale(
                  scale: reduceMotion ? 1 : 1 + camera.value * .055,
                  alignment: chapter == 0
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: child,
                ),
                child: Image.asset(
                  missionOpeningAsset,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xff193f72), Color(0xff081321)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xf5081424),
                    Color(0xcc081424),
                    Color(0x44081424),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'BLUE HORIZON',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xffadd8ff),
                              fontSize: 11,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${chapter + 1} / ${stories.length}',
                          style: const TextStyle(
                            color: Color(0xffadd8ff),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          key: const Key('opening-skip'),
                          onPressed: controller.busy
                              ? null
                              : widget.replay
                              ? widget.onClose
                              : () => setState(() => naming = true),
                          child: Text(widget.replay ? '閉じる' : '物語をスキップ'),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 630),
                          child: SingleChildScrollView(
                            key: const Key('opening-story-scroll'),
                            controller: storyScroll,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  story.$1,
                                  key: const Key('opening-title'),
                                  style: TextStyle(
                                    fontSize:
                                        MediaQuery.sizeOf(context).height < 400
                                        ? 25
                                        : 34,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  story.$2,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.8,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    const MinaAvatar(size: 40),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        story.$3,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          height: 1.6,
                                          color: Color(0xffbbdefb),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        if (chapter > 0)
                          TextButton(
                            key: const Key('opening-back'),
                            onPressed: () => _setChapter(chapter - 1),
                            child: const Text('戻る'),
                          ),
                        const Spacer(),
                        FilledButton.icon(
                          key: const Key('opening-next'),
                          onPressed: _next,
                          icon: Icon(
                            chapter == stories.length - 1
                                ? Icons.rocket_launch_outlined
                                : Icons.arrow_forward,
                          ),
                          label: Text(
                            chapter < stories.length - 1
                                ? '次へ'
                                : widget.replay
                                ? '開発に戻る'
                                : '計画に名前をつける',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> showMissionNames(
  BuildContext context,
  GameController controller,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: MissionNameForm(
        controller: controller,
        onDone: () => Navigator.pop(context),
        onCancel: () => Navigator.pop(context),
      ),
    ),
  ),
);

class MissionNameForm extends StatefulWidget {
  const MissionNameForm({
    super.key,
    required this.controller,
    required this.onDone,
    this.onCancel,
    this.finishOpening = false,
  });
  final GameController controller;
  final VoidCallback onDone;
  final VoidCallback? onCancel;
  final bool finishOpening;

  @override
  State<MissionNameForm> createState() => _MissionNameFormState();
}

class _MissionNameFormState extends State<MissionNameForm> {
  final form = GlobalKey<FormState>();
  bool submitting = false;
  late final Map<String, TextEditingController> cities;
  late final TextEditingController rocket;

  @override
  void initState() {
    super.initState();
    cities = {
      for (final id in GameContent.cities.keys)
        id: TextEditingController(text: widget.controller.state.cityName(id)),
    };
    rocket = TextEditingController(text: widget.controller.state.rocketName);
  }

  @override
  void dispose() {
    for (final city in cities.values) {
      city.dispose();
    }
    rocket.dispose();
    super.dispose();
  }

  Widget _field(String key, String label, TextEditingController controller) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          key: Key(key),
          controller: controller,
          enabled: !submitting,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.next,
          maxLength: MissionIdentity.maxNameLength,
          validator: (value) => MissionIdentity.nameError(value ?? ''),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      return LayoutBuilder(
        builder: (context, constraints) => PopScope(
          canPop: !submitting,
          child: Padding(
            // Scaffold removes the keyboard inset from its body MediaQuery.
            // The remaining height also identifies a compressed dialog correctly.
            padding: EdgeInsets.all(constraints.maxHeight < 280 ? 12 : 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    key: const Key('mission-names-scroll'),
                    child: Form(
                      key: form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            widget.finishOpening
                                ? 'あなたの計画に、名前を。'
                                : '都市・ロケットの名前',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '名前は後から変更できます。',
                            style: TextStyle(
                              color: strategyMuted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _field(
                            'mission-city-earth_delta',
                            '地球の最初の街',
                            cities['earth_delta']!,
                          ),
                          _field('mission-rocket', '輸送ロケット', rocket),
                          _field(
                            'mission-city-mars_arcadia',
                            '火星の最初の街',
                            cities['mars_arcadia']!,
                          ),
                          if (!widget.finishOpening)
                            for (final entry in cities.entries.where(
                              (e) => ![
                                'earth_delta',
                                'mars_arcadia',
                              ].contains(e.key),
                            ))
                              _field(
                                'mission-city-${entry.key}',
                                GameContent.cities[entry.key]!.name,
                                entry.value,
                              ),
                          if (controller.error != null)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                '保存できませんでした。名前を残したまま再試行できます。',
                                style: TextStyle(color: strategyCopper),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  children: [
                    TextButton(
                      key: const Key('mission-names-cancel'),
                      onPressed: controller.busy || submitting
                          ? null
                          : widget.onCancel,
                      child: Text(widget.finishOpening ? '名前は後で決める' : 'キャンセル'),
                    ),
                    FilledButton(
                      key: const Key('mission-names-save'),
                      onPressed:
                          controller.busy ||
                              submitting ||
                              controller.engine == null
                          ? null
                          : () async {
                              if (submitting ||
                                  !form.currentState!.validate()) {
                                return;
                              }
                              FocusScope.of(context).unfocus();
                              setState(() => submitting = true);
                              try {
                                final saved = await controller
                                    .updateMissionIdentity(
                                      cities: {
                                        for (final entry in cities.entries)
                                          entry.key: entry.value.text,
                                      },
                                      rocket: rocket.text,
                                      finishOpening: widget.finishOpening,
                                    );
                                if (mounted && saved) widget.onDone();
                              } finally {
                                if (mounted) setState(() => submitting = false);
                              }
                            },
                      child: Text(widget.finishOpening ? '火星開発を始める' : '名前を保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
