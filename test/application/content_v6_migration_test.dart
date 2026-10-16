import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/infrastructure/key_value_save_store.dart';

void main() {
  test(
    'district-5 keeps specialists, choices and paid work through two reloads',
    () async {
      final epoch = DateTime.utc(2026, 10, 16);
      final old = GameEngine(GameState.initial(epoch));
      old.state.specialistCount = 18;
      old.state.researchers = 10;
      old.state.partnershipChoices['research_exchange'] = 'funding';
      old.state.claimedRewards.add(
        '${old.state.worldId}:partnership:research_exchange',
      );
      old.enqueue('factory_contract', repeats: 3);
      old.advanceBy(const Duration(seconds: 30));
      final legacy = old.state.toJson()
        ..['contentVersion'] = 'district-5'
        ..remove('missionIdentity')
        ..remove('openingSeen')
        ..remove('openingStarted');
      final storage = <String, String>{};
      KeyValueSaveStore repository() => KeyValueSaveStore(
        read: (key) => storage[key],
        write: (key, value) => storage[key] = value,
      );
      await repository().save(legacy);
      final first = GameController(repository(), now: () => epoch);
      await first.initialize(startTimer: false);
      addTearDown(first.dispose);
      expect(first.error, isNull);
      expect(first.state.openingSeen, isTrue);
      expect(first.state.specialistCount, 18);
      expect(first.state.researchers, 10);
      expect(first.state.partnershipChoices, old.state.partnershipChoices);
      expect(first.state.moneyUnits, old.state.moneyUnits);
      expect(
        first.state.plans.single.toJson(),
        old.state.plans.single.toJson(),
      );
      expect(first.state.claimedRewards, old.state.claimedRewards);
      expect(first.state.toJson()['contentVersion'], GameContent.version);
      final second = GameController(repository(), now: () => epoch);
      await second.initialize(startTimer: false);
      addTearDown(second.dispose);
      expect(second.state.toJson(), first.state.toJson());
    },
  );
}
