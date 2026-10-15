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
    required this.status,
    required this.destination,
    required this.target,
    this.facilityId,
    this.reason = '',
    this.remainingMs = 0,
  });

  final String id, title, timeHint, lesson, target, reason;
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
    return OnboardingGuide._(
      List.unmodifiable([
        step(
          id: 'first_research',
          title: '生命維持の実証',
          timeHint: '0〜5分',
          lesson: '研究ツリーで費用と時間を確認し、生命維持研究を予約します。予約した研究は画面を離れても進みます。',
          completed: state.research.contains('life_support'),
          destination: OnboardingDestination.research,
          target: 'life_support',
          plan: active('life_support'),
        ),
        step(
          id: 'first_district',
          title: '地球に最初の地区を建設',
          timeHint: '0〜10分・研究と並行',
          lesson: '施設を選び、六角区画の費用と効果を比較して建設を予約します。工場の受注と建設は同じ順番待ちです。',
          completed: hasEarthDistrict,
          destination: OnboardingDestination.city,
          target: earthConstruction?.cityId ?? 'earth_delta',
          plan: earthConstruction,
        ),
        step(
          id: 'urban_planning',
          title: '都市基盤の計画',
          timeHint: '10〜20分',
          lesson: '都市基盤研究で住宅の増強を解放します。新しい区画への建設と、完成した住宅の増強を比較できます。',
          completed: state.research.contains('urban_planning'),
          destination: OnboardingDestination.research,
          target: 'urban_planning',
          plan: active('urban_planning'),
        ),
        step(
          id: 'first_kit',
          title: '居住キットを製造',
          timeHint: '20〜35分',
          lesson: '製造・受注から居住キットを予約します。無期限受注の後ろで待つ場合は、設備配分で次の予約順を変更できます。',
          completed: madeKit,
          destination: OnboardingDestination.operations,
          target: '1',
          plan: active('habitat_kit') ?? active('batch_habitat_kit'),
          prerequisite: state.research.contains('life_support')
              ? ''
              : '生命維持研究の完成が必要',
        ),
        step(
          id: 'first_landing',
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
          title: '火星の居住地区を完成',
          timeHint: '45〜60分',
          lesson: '火星の区画を選び居住地区を建設します。初めての閉鎖居住を達成した後は、都市拡張や応用研究を自由に選べます。',
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
