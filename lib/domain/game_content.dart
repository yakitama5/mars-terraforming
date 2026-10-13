/// Tuning data for the first playable prototype. Money is in credits (Cr),
/// durations are real seconds, and operating rates are credits per real minute.
/// These deliberately short values do not model the finished 4–6 week game.
class FacilityDefinition {
  const FacilityDefinition(this.id, this.name, this.upkeepPerMinute);
  final String id;
  final String name;
  final int upkeepPerMinute;
}

class TaskDefinition {
  const TaskDefinition({
    required this.id,
    required this.name,
    required this.facilityId,
    required this.durationSeconds,
    required this.cost,
    required this.description,
    this.reward = 0,
    this.requiredResearch,
    this.inputResource,
    this.outputResource,
    this.unique = false,
    this.requiresHabitatChoice = false,
    this.science = '',
  });
  final String id;
  final String name;
  final String facilityId;
  final int durationSeconds;
  final int cost;
  final int reward;
  final String description;
  final String? requiredResearch;
  final String? inputResource;
  final String? outputResource;
  final bool unique;
  final bool requiresHabitatChoice;
  final String science;
  int get durationMs => durationSeconds * 1000;
}

abstract final class GameContent {
  static const version = 'prototype-1';
  static const initialMoney = 900;
  static const initialPopulation = 120;
  static const baseTaxPerMinute = 30;
  static const districtTaxPerMinute = 18;
  static const residentsPerHabitat = 12;
  static const residentsPerDistrict = 60;
  static const achievementReward = 180;
  static const maxActivePlans = 24;
  static const maxFinishedPlans = 48;
  static const facilities = <String, FacilityDefinition>{
    'lab': FacilityDefinition('lab', '研究所', 8),
    'factory': FacilityDefinition('factory', '共用工場', 18),
    'launch': FacilityDefinition('launch', '共用宇宙港', 14),
    'mars': FacilityDefinition('mars', '火星建設班', 2),
  };
  static const tasks = <String, TaskDefinition>{
    'factory_contract': TaskDefinition(
      id: 'factory_contract',
      name: '外部受注・精密機器',
      facilityId: 'factory',
      durationSeconds: 90,
      cost: 40,
      reward: 220,
      description: '共用工場を使い、完了時に220 Crを受領。居住キット製造と設備を取り合う。',
    ),
    'launch_contract': TaskDefinition(
      id: 'launch_contract',
      name: '外部受注・衛星打上げ',
      facilityId: 'launch',
      durationSeconds: 120,
      cost: 80,
      reward: 360,
      description: '共用宇宙港を使い、完了時に360 Crを受領。自前の火星輸送はその間待機。',
    ),
    'life_support': TaskDefinition(
      id: 'life_support',
      name: '生命維持の実証',
      facilityId: 'lab',
      durationSeconds: 120,
      cost: 180,
      unique: true,
      description: '閉鎖居住に必要な水・空気の再生系を研究。居住キットを製造できるようになる。',
      science:
          '実証：ISSでは水回収・再生システムが運用されています。NASAは2023年に98%の水回収という到達点を報告しました。\n\n'
          '構想：その考え方を火星の閉鎖居住設備へ応用します。ISSでの実証は火星での長期自立や屋外居住の実証ではありません。\n\n'
          'ゲーム上の仮定：設備1組で少人数の居住を支えます。期間・費用・輸送・放射線対策を簡略化しています。\n\n'
          'NASA (2023) NASA Achieves Water Recovery Milestone on International Space Station\n'
          'https://www.nasa.gov/missions/station/iss-research/nasa-achieves-water-recovery-milestone-on-international-space-station/',
    ),
    'habitat_kit': TaskDefinition(
      id: 'habitat_kit',
      name: '居住キット製造',
      facilityId: 'factory',
      durationSeconds: 180,
      cost: 260,
      requiredResearch: 'life_support',
      outputResource: 'earthKits',
      description: '生命維持設備と居住モジュールを1基製造。地球の在庫に追加する。',
    ),
    'mars_delivery': TaskDefinition(
      id: 'mars_delivery',
      name: '火星へ輸送',
      facilityId: 'launch',
      durationSeconds: 180,
      cost: 220,
      inputResource: 'earthKits',
      outputResource: 'marsKits',
      description: '地球の居住キット1基を火星へ運ぶ。貨物と費用は出発時に確保する。',
    ),
    'build_habitat': TaskDefinition(
      id: 'build_habitat',
      name: '火星居住区を建設',
      facilityId: 'mars',
      durationSeconds: 120,
      cost: 200,
      inputResource: 'marsKits',
      requiresHabitatChoice: true,
      description: 'ドーム／地下居住の方針を選んで建設。1基につき12人が閉鎖居住区で暮らせる。',
      science: '火星の閉鎖居住は構想段階。保護された居住区の成立を仮定し、屋外の居住可能化とは区別します。',
    ),
    'earth_expansion': TaskDefinition(
      id: 'earth_expansion',
      name: '地球の住宅地区を拡張',
      facilityId: 'factory',
      durationSeconds: 120,
      cost: 300,
      description: '人口を60人、税収を毎分18 Cr増やす。工場を使うため、受注・製造との配分が必要。',
    ),
  };
  static const resourceNames = {
    'earthKits': '地球の居住キット',
    'marsKits': '火星の居住キット',
  };
  static const achievementNames = {
    'first_landing': '火星への初輸送',
    'dome_habitat': 'ドームでの暮らし',
    'underground_habitat': '地下での暮らし',
  };
}
