import 'dart:async';

import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/game_state.dart';
import '../rendering/base_scene.dart';
import 'facility_queue_card.dart';

const _mint = Color(0xffa2dfc8);
const _muted = Color(0xff98adb9);
const _copper = Color(0xffe8a57c);

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.controller, this.sceneBuilder});
  final GameController controller;
  final Widget Function(bool, int, int, bool)? sceneBuilder;
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  bool earth = false;
  int tab = 0;
  GameController get controller => widget.controller;
  GameState get game => controller.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(controller.resume());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(controller.save());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.engine == null) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: controller.error == null
                  ? const CircularProgressIndicator()
                  : Semantics(liveRegion: true, child: Text(controller.error!)),
            ),
          ),
        );
      }
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _header(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final panel = _panel();
                    if (tab == 1) return panel;
                    final scene = _world();
                    if (constraints.maxWidth < 620) {
                      return Column(
                        children: [
                          Expanded(flex: 2, child: scene),
                          Expanded(flex: 3, child: panel),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: constraints.maxWidth > 1000 ? 6 : 5,
                          child: scene,
                        ),
                        const VerticalDivider(
                          width: 1,
                          color: Color(0xff2a3c48),
                        ),
                        Expanded(flex: 5, child: panel),
                      ],
                    );
                  },
                ),
              ),
              _footer(),
            ],
          ),
        ),
      );
    },
  );

  Widget _header() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xff2a3c48))),
    ),
    child: Row(
      children: [
        const Icon(Icons.public, color: _copper, size: 24),
        const SizedBox(width: 10),
        const Text(
          '火星開発計画',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const Spacer(),
        Text(
          '資金  ${game.money} Cr',
          key: const Key('money'),
          style: const TextStyle(
            color: _mint,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        const SizedBox(width: 16),
        if (controller.devTools)
          OutlinedButton.icon(
            key: const Key('advance-time'),
            onPressed: controller.busy
                ? null
                : controller.advanceForDevelopment,
            icon: const Icon(Icons.fast_forward, size: 16),
            label: const Text('開発 +5分'),
          )
        else
          const Text('オフライン', style: TextStyle(color: _muted, fontSize: 11)),
      ],
    ),
  );

  Widget _world() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(
          children: [
            _worldButton('地球', true),
            const SizedBox(width: 8),
            _worldButton('火星', false),
            const Spacer(),
            Text(
              earth ? '産業拠点 Lv.${game.earthLevel}' : 'アレス平原 / 仮称',
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
      ),
      Expanded(
        child: Stack(
          children: [
            Positioned.fill(
              child:
                  widget.sceneBuilder?.call(
                    earth,
                    game.earthLevel,
                    game.marsHabitats,
                    game.marsKits > 0,
                  ) ??
                  BaseScene(
                    earth: earth,
                    earthLevel: game.earthLevel,
                    marsHabitats: game.marsHabitats,
                    hasCargo: game.marsKits > 0,
                  ),
            ),
            Positioned(
              left: 18,
              top: 12,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      earth
                          ? '開発を支える、小さな国家。'
                          : game.marsHabitats > 0
                          ? '火星に、人の居場所を。'
                          : '最初の居住拠点へ。',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      earth ? '研究所・工場・宇宙港を配分する' : '研究 → 製造 → 輸送 → 居住',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 18,
              bottom: 8,
              right: 18,
              child: IgnorePointer(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _tag(
                      earth
                          ? '人口 ${game.population} 人'
                          : '居住者 ${game.marsResidents} 人',
                    ),
                    _tag(
                      earth
                          ? '地球の設備キット ${game.earthKits}'
                          : '到着キット ${game.marsKits}',
                    ),
                    _tag(earth ? '3つの共用設備' : '居住施設 ${game.marsHabitats}'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
        child: Text(
          game.achievements.isNotEmpty
              ? '達成記録  ${game.achievements.length} 件  ·  屋外はまだ居住できません'
              : '国際宇宙開発機関  ·  地球の産業を、次の一歩へ',
          style: const TextStyle(color: _muted, fontSize: 11),
        ),
      ),
    ],
  );

  Widget _worldButton(String label, bool value) => ChoiceChip(
    label: Text(label),
    selected: earth == value,
    onSelected: (_) => setState(() => earth = value),
    showCheckmark: false,
  );
  Widget _tag(String text) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xe614212b),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    ),
  );

  Widget _panel() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(
          children: [
            for (final (index, label) in ['計画をつくる', '設備・進行', '開発記録'].indexed)
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() => tab = index),
                  style: TextButton.styleFrom(
                    foregroundColor: tab == index ? _mint : _muted,
                    backgroundColor: tab == index
                        ? const Color(0xff223a3c)
                        : Colors.transparent,
                  ),
                  child: Text(label, style: const TextStyle(fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: ListView(
          key: ValueKey(tab),
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
          children: tab == 0
              ? _planning()
              : tab == 1
              ? _facilities()
              : _journal(),
        ),
      ),
    ],
  );

  List<Widget> _planning() => [
    _section('01 / 地球から火星へ', '最初は外部受注で運転資金を確保。研究 → 製造 → 輸送を予約して、居住方式を選びます。'),
    _taskCard('life_support', Icons.science_outlined),
    _taskCard('habitat_kit', Icons.precision_manufacturing_outlined),
    _taskCard('mars_delivery', Icons.rocket_launch_outlined),
    if (game.habitatChoice == null) _branch(),
    _taskCard('build_habitat', Icons.holiday_village_outlined),
    const SizedBox(height: 10),
    _section('02 / 計画を支える財政', '外部受注も自分の計画と同じ工場・宇宙港を使います。'),
    _taskCard('factory_contract', Icons.handshake_outlined),
    _taskCard('launch_contract', Icons.satellite_alt_outlined),
    _taskCard('earth_expansion', Icons.location_city_outlined),
  ];

  Widget _section(String title, String description) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _mint,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        Text(description, style: const TextStyle(color: _muted, fontSize: 11)),
      ],
    ),
  );

  Widget _taskCard(String id, IconData icon) {
    final definition = GameContent.tasks[id]!;
    final completed = id == 'life_support' && game.research.contains(id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xff172731),
        border: Border.all(color: const Color(0xff2a3c48)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: _copper),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  definition.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (completed)
                const Icon(Icons.check_circle, color: _mint, size: 18),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${definition.cost} Cr / ${_duration(definition.durationMs)} / ${_facilityName(definition.facilityId)}',
            style: const TextStyle(color: _muted, fontSize: 11),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              definition.description,
              style: const TextStyle(fontSize: 11, color: _muted),
            ),
          ),
          if (id == 'life_support')
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Text(
                '実証のある水再生技術を参考に、火星での運用を研究。火星への展開はゲーム上の仮定です。',
                style: TextStyle(fontSize: 11, color: _muted),
              ),
            ),
          if (id == 'factory_contract' || id == 'launch_contract')
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                '完成時に ${definition.reward} Cr を受領。予約順に設備を占有します。',
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (id == 'life_support')
                TextButton(
                  onPressed: _science,
                  child: const Text('科学メモ', style: TextStyle(fontSize: 11)),
                ),
              const Spacer(),
              FilledButton.tonal(
                key: Key('queue-$id'),
                onPressed: completed || controller.busy
                    ? null
                    : () => _reserve(id),
                child: Text(
                  completed ? '研究済み' : '予約する',
                  semanticsLabel: completed
                      ? '${definition.name}・研究済み'
                      : '${definition.name}を予約',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _reserve(String id) async {
    int? repeats = 1;
    if (id == 'factory_contract' ||
        id == 'launch_contract' ||
        id == 'habitat_kit' ||
        id == 'mars_delivery' ||
        id == 'build_habitat') {
      final result = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('反復回数'),
          children: [
            for (final (value, label) in [
              (1, '1回'),
              (3, '3回'),
              (-1, '無期限・分岐まで'),
            ])
              SimpleDialogOption(
                key: Key('repeat-$value'),
                onPressed: () => Navigator.pop(context, value),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(label),
                ),
              ),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('資金・資材不足では待機します。無期限の受注は設備を使い続けるため、設備・進行から終了できます。'),
            ),
          ],
        ),
      );
      if (result == null) return;
      repeats = result == -1 ? null : result;
    }
    await controller.command((engine) => engine.enqueue(id, repeats: repeats));
    if (mounted) setState(() => tab = 1);
  }

  Widget _branch() => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xff302b27),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '次の判断 / 居住方式',
          style: TextStyle(color: _copper, fontWeight: FontWeight.bold),
        ),
        const Text(
          '初輸送後に選択できます。未選択なら建設だけが分岐で止まります。この試作では方式は一度選択・性能は同じです。',
          style: TextStyle(fontSize: 11),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              key: const Key('choose-dome'),
              onPressed: !game.achievements.contains('first_landing')
                  ? null
                  : () => controller.command(
                      (engine) => engine.chooseHabitat('dome'),
                    ),
              child: const Text('ドーム居住'),
            ),
            TextButton(
              key: const Key('choose-underground'),
              onPressed: !game.achievements.contains('first_landing')
                  ? null
                  : () => controller.command(
                      (engine) => engine.chooseHabitat('underground'),
                    ),
              child: const Text('地下居住'),
            ),
          ],
        ),
      ],
    ),
  );

  List<Widget> _facilities() => [
    Text(
      '税収 +${game.taxPerMinute} / 維持費 −${game.upkeepPerMinute} / 差引 ${game.netPerMinute} Cr/分',
      style: const TextStyle(color: _mint, fontSize: 12),
    ),
    const SizedBox(height: 10),
    _section(
      '共用設備の稼働計画',
      '↑↓で次の予約を並べ替えます。実行中の1回は続行し、その後に新しい順番で着手します。先頭が条件待ちなら後続も待ちます。',
    ),
    LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000 ? 2 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final id in GameContent.facilities.keys)
              SizedBox(
                width: width,
                child: FacilityQueueCard(
                  controller: controller,
                  facilityId: id,
                ),
              ),
          ],
        );
      },
    ),
    const SizedBox(height: 12),
    if (game.habitatChoice == null) _branch(),
    Text(
      controller.notice,
      style: const TextStyle(color: _muted, fontSize: 11),
    ),
  ];

  List<Widget> _journal() => [
    _section('開発の記録', '成果は端末内に保存されます。閉鎖居住の実績と全球の居住可能化は別の到達点です。'),
    Text(
      '地球人口 ${game.population} 人 / 火星居住者 ${game.marsResidents} 人',
      style: const TextStyle(color: _mint),
    ),
    const SizedBox(height: 12),
    if (game.log.isEmpty) const Text('まだ記録はありません。まず開発計画を予約しましょう。'),
    for (final entry in game.log.reversed)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text('· $entry'),
      ),
    const SizedBox(height: 16),
    const Text(
      '試作 v0.1 / 費用・期間・配置は仮値\n全球環境・ED・周回・火星復元は未実装',
      style: TextStyle(color: _muted, fontSize: 11),
    ),
  ];

  Widget _footer() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    color: const Color(0xff14212b),
    child: Text(
      controller.error ??
          (controller.devTools
              ? '開発モード · 通常プレイとは別の保存枠  |  ${controller.notice}'
              : controller.notice),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 10,
        color: controller.error == null ? _muted : Colors.orangeAccent,
      ),
    ),
  );

  void _science() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('生命維持 / 科学メモ'),
      content: SingleChildScrollView(
        child: SelectableText(GameContent.tasks['life_support']!.science),
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

String _facilityName(String id) =>
    const {
      'lab': '研究所',
      'factory': '共用工場',
      'launch': '宇宙港',
      'mars': '火星建設班',
    }[id] ??
    id;
String _duration(int ms) {
  final seconds = (ms / 1000).ceil();
  return seconds < 60
      ? '$seconds秒'
      : '${seconds ~/ 60}分${seconds % 60 == 0 ? '' : '${seconds % 60}秒'}';
}
