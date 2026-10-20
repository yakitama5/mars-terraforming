import 'game_content.dart';
import 'game_state.dart';

enum OnboardingStatus { available, queued, running, stopped, locked, completed }

enum OnboardingDestination { research, city, operations }

/// Read-only milestones. Time is a suggested pace, never a completion rule.
class OnboardingStep {
  const OnboardingStep({
    required this.id,
    required this.title,
    required this.timeHint,
    required this.lesson,
    required this.story,
    required this.status,
    required this.destination,
    required this.target,
    this.facilityId,
    this.reason = '',
    this.remainingMs = 0,
  });

  final String id, title, timeHint, lesson, story, target, reason;
  final String? facilityId;
  final OnboardingStatus status;
  final OnboardingDestination destination;
  final int remainingMs;
  bool get isCompleted => status == OnboardingStatus.completed;
}

class OnboardingGuide {
  OnboardingGuide._(this.steps, this.elapsedMs);

  final List<OnboardingStep> steps;
  final int elapsedMs;
  int get completedCount => steps.where((step) => step.isCompleted).length;
  bool get isComplete => completedCount == steps.length;
  double get progress => completedCount / steps.length;

  factory OnboardingGuide.fromState(GameState state) {
    PlannedTask? active(String id) => state.plans
        .where((plan) => plan.taskId == id && !plan.isFinished)
        .firstOrNull;

    OnboardingStep step({
      required String id,
      required String title,
      required String timeHint,
      required String lesson,
      required String story,
      required bool completed,
      required OnboardingDestination destination,
      required String target,
      PlannedTask? plan,
      String prerequisite = '',
    }) {
      var status = completed
          ? OnboardingStatus.completed
          : OnboardingStatus.available;
      var reason = '';
      if (!completed && plan != null) {
        if (state.facilities[plan.definition.facilityId] != true) {
          status = OnboardingStatus.stopped;
          reason = '設備休止中・設備配分から手動で再開';
        } else if (plan.stopReason.startsWith('研究ポイント待ち')) {
          status = OnboardingStatus.queued;
          reason = plan.stopReason;
        } else if (plan.stopReason.isNotEmpty &&
            plan.stopReason != '共用設備の順番待ち') {
          status = OnboardingStatus.stopped;
          reason = plan.stopReason;
        } else {
          status = plan.status == 'running'
              ? OnboardingStatus.running
              : OnboardingStatus.queued;
        }
      } else if (!completed && prerequisite.isNotEmpty) {
        status = OnboardingStatus.locked;
        reason = prerequisite;
      }
      final inspectQueue = !completed && plan != null;
      return OnboardingStep(
        id: id,
        title: title,
        timeHint: timeHint,
        lesson: lesson,
        story: story,
        status: status,
        destination: inspectQueue
            ? OnboardingDestination.operations
            : destination,
        target: inspectQueue ? '0' : target,
        facilityId: inspectQueue ? plan.definition.facilityId : null,
        reason: reason,
        remainingMs: plan?.remainingMs ?? 0,
      );
    }

    final landed =
        state.achievements.contains('first_landing') || state.marsHabitats > 0;
    final delivery = active('mars_delivery') ?? active('cargo_delivery');
    final madeKit =
        state.earthKits > 0 ||
        state.marsKits > 0 ||
        landed ||
        delivery?.status == 'running' ||
        state.plans.any(
          (plan) =>
              plan.definition.outputResource == 'earthKits' &&
              plan.completedRuns > 0,
        );
    final earthConstruction = state.plans
        .where(
          (plan) =>
              !plan.isFinished &&
              ((plan.definition.districtId != null &&
                      GameContent.cities[plan.cityId]?.planet == 'earth') ||
                  plan.taskId == 'earth_expansion'),
        )
        .firstOrNull;
    final hasEarthDistrict =
        state.earthLevel > 1 ||
        state.districts.values.any(
          (district) => GameContent.cities[district.cityId]?.planet == 'earth',
        );
    final nextResearch = state.discoveredResearchIds
        .where((id) => id != 'life_support' && !state.research.contains(id))
        .firstOrNull;
    final secondResearchComplete = state.research.length >= 2;
    return OnboardingGuide._(
      List.unmodifiable([
        step(
          id: 'first_research',
          story: '研究所で生まれた知見を、人が暮らせる区画へ。都市の研究者が最初の一歩を支えます。',
          title: GameContent.tasks['life_support']!.name,
          timeHint: '0〜5分',
          lesson: '研究者を配置した施設で共通RPを蓄え、必要量を使って技術を解放します。解放後は、施設や機体の建設・製造へ進めます。',
          completed: state.research.contains('life_support'),
          destination: OnboardingDestination.research,
          target: 'life_support',
          plan: active('life_support'),
        ),
        step(
          id: 'first_district',
          story: '宇宙への挑戦を支えるのは、${state.cityName('earth_delta')}で暮らす人々です。',
          title: '地球に最初の地区を建設',
          timeHint: '0〜10分・研究と並行',
          lesson: '施設→六角区画→建設予約。土地と隣接の効果を比較しましょう。受注と建設は工場を共用します。',
          completed: hasEarthDistrict,
          destination: OnboardingDestination.city,
          target: earthConstruction?.cityId ?? 'earth_delta',
          plan: earthConstruction,
        ),
        step(
          id: 'urban_planning',
          story: '街が育てば、計画も育つ。限られた土地で、次に何を増やすかを決めましょう。',
          title: '次の技術を選ぶ',
          timeHint: '10〜20分',
          lesson:
              '見つかった技術の解放先と必要RPを比較します。RPは全分野で共通です。研究を進めると、その先の候補が少しずつ見つかります。',
          completed: secondResearchComplete,
          destination: OnboardingDestination.research,
          target: nextResearch ?? 'life_support',
          plan: nextResearch == null ? null : active(nextResearch),
          prerequisite: !secondResearchComplete && nextResearch == null
              ? '研究を進めて次の候補を見つけましょう'
              : '',
        ),
        step(
          id: 'first_kit',
          story: '研究所の成果を、人が暮らせる設備へ。工場が地球と火星をつなぎます。',
          title: '居住キットを製造',
          timeHint: '20〜35分',
          lesson: '製造・受注で居住キットを予約。受注が続いて着手できないときは、設備配分でキットを先頭へ移します。',
          completed: madeKit,
          destination: OnboardingDestination.operations,
          target: '1',
          plan: active('habitat_kit') ?? active('batch_habitat_kit'),
          prerequisite: state.research.contains('life_support')
              ? ''
              : '最初の居住技術の解放が必要',
        ),
        step(
          id: 'first_landing',
          story:
              '輸送船「${state.rocketName}」が運ぶのは、${state.cityName('mars_arcadia')}の最初の灯りです。',
          title: landed ? '火星の居住方式を選ぶ' : '火星へ輸送し、居住方式を選ぶ',
          timeHint: '35〜45分',
          lesson: landed && state.habitatChoice == null
              ? '初輸送が完了しました。輸送・居住でドームか地下居住を選びます。方式が決まるまで居住建設は待機します。'
              : '輸送に地球のキットを1基使います。到着後、ドームか地下居住を自分で選びます。未選択でも他の設備は動き続けます。',
          completed: landed && state.habitatChoice != null,
          destination: OnboardingDestination.operations,
          target: '2',
          plan: landed ? null : delivery,
          prerequisite: !landed && !madeKit ? '居住キットの製造が必要' : '',
        ),
        step(
          id: 'first_habitat',
          story: '赤い大地に、小さな日常が生まれます。この街を育てる次の一手は、あなたが決めます。',
          title: '火星の居住地区を完成',
          timeHint: '45〜60分',
          lesson: '火星で居住地区を建設。完成後は、収入・研究・補給のうち足りないものを見つけ、次の投資を選びましょう。',
          completed: state.marsHabitats > 0,
          destination: OnboardingDestination.city,
          target: 'mars_arcadia',
          plan: active('district_mars_habitat') ?? active('build_habitat'),
          prerequisite: !landed
              ? '火星への初輸送が必要'
              : state.habitatChoice == null
              ? '輸送・居住で居住方式を選択'
              : '',
        ),
      ]),
      state.simulatedMs,
    );
  }
}
