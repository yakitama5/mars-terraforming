import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 20);
  String id(String catalogId) => ResearchCatalog.idForCatalog(catalogId);

  test('locked city reasons conceal undiscovered research names', () {
    final state = GameState.initial(epoch);
    state.achievements.add('first_landing');
    final required = GameContent.cities['mars_hellas']!.requiredResearch!;
    expect(state.isResearchDiscovered(required), isFalse);
    final reason = state.cityLockReason('mars_hellas');
    expect(reason, contains('手掛かり'));
    expect(reason, isNot(contains(GameContent.tasks[required]!.name)));
    // A reservation retained from a previous tree is already known.
    state.plans.add(PlannedTask(id: 'known-reservation', taskId: required));
    expect(
      state.cityLockReason('mars_hellas'),
      contains(GameContent.tasks[required]!.name),
    );
  });

  test('district upgrades name a prerequisite only after its discovery', () {
    final state = GameState.initial(epoch);
    state.research.add('urban_planning');
    const district = DistrictState(
      cityId: 'earth_delta',
      plotIndex: 1,
      districtId: 'solar',
    );
    state.districts[district.key] = district;
    final hidden = state
        .districtPreview('earth_delta', 1, 'solar', upgrade: true)
        .blockedReason;
    expect(hidden, contains('手掛かり'));
    expect(
      hidden,
      isNot(contains(GameContent.tasks['automated_fabrication']!.name)),
    );
    state.research.add(id('M01'));
    final known = state
        .districtPreview('earth_delta', 1, 'solar', upgrade: true)
        .blockedReason;
    expect(known, contains(GameContent.tasks['automated_fabrication']!.name));
  });

  test('partnerships do not disclose an unseen research root', () {
    final state = GameState.initial(epoch);
    expect(state.isResearchDiscovered('urban_planning'), isFalse);
    expect(state.partnershipLockReason('research_exchange'), contains('手掛かり'));
    expect(
      state.partnershipLockReason('research_exchange'),
      isNot(contains(GameContent.tasks['urban_planning']!.name)),
    );
    state.research.add(id('E01'));
    expect(
      state.partnershipLockReason('research_exchange'),
      contains(GameContent.tasks['urban_planning']!.name),
    );
  });

  test(
    'retained reservations conceal the names and count of hidden prerequisites',
    () {
      final state = GameState.initial(epoch);
      final engine = GameEngine(state);
      final prerequisite = id('M18');
      final statuses = engine.researchRequirements('industrial_network');
      expect(statuses, hasLength(1));
      expect(statuses.single.isMet, isFalse);
      expect(statuses.single.label, contains('手掛かり'));
      expect(
        statuses.single.unmetReason,
        isNot(contains(GameContent.tasks[prerequisite]!.name)),
      );
      state.research.add(id('M17'));
      expect(
        engine.researchRequirements('industrial_network').single.label,
        contains(GameContent.tasks[prerequisite]!.name),
      );
    },
  );

  test(
    'an OR prerequisite does not disclose its still unknown alternative',
    () {
      final state = GameState.initial(epoch);
      state.research.add(id('B22'));
      final engine = GameEngine(state);
      final hiddenAlternative = id('B23');
      expect(state.isResearchDiscovered(id('B24')), isTrue);
      expect(state.isResearchDiscovered(hiddenAlternative), isFalse);
      final statuses = engine.researchRequirements(id('B24'));
      expect(statuses, hasLength(1));
      expect(statuses.single.isMet, isTrue);
      expect(
        statuses.single.label,
        isNot(contains(GameContent.tasks[hiddenAlternative]!.name)),
      );
      expect(statuses.single.label, isNot(contains('または')));
    },
  );

  test(
    'opening city and district information never grows the research frontier',
    () {
      final state = GameState.initial(epoch);
      final discovered = state.discoveredResearchIds;
      state.achievements.add('first_landing');
      for (final city in GameContent.cities.values) {
        state.cityLockReason(city.id);
      }
      state.districtPreview('earth_delta', 0, 'campus');
      state.partnershipLockReason('research_exchange');
      expect(state.discoveredResearchIds, discovered);
    },
  );
}
