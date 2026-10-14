/// Specialists are agency staff, distinct from the population of its cities.
class AgencyStatus {
  const AgencyStatus({
    required this.fame,
    required this.technology,
    required this.friendship,
    required this.spaceContribution,
  });
  final int fame, technology, friendship, spaceContribution;
}

/// Fictional partners and game effects; these are not real endorsements.
class PartnershipDefinition {
  const PartnershipDefinition({
    required this.id,
    required this.title,
    required this.partner,
    required this.description,
    required this.choices,
    this.requiredResearch,
    this.requiredDistrict,
    this.requiredAchievement,
    this.minimumDistricts = 0,
    this.minimumFame = 0,
    this.minimumTechnology = 0,
    this.minimumFriendship = 0,
    this.minimumSpaceContribution = 0,
  });
  final String id, title, partner, description;
  final String? requiredResearch, requiredDistrict, requiredAchievement;
  final int minimumDistricts;
  final int minimumFame,
      minimumTechnology,
      minimumFriendship,
      minimumSpaceContribution;
  final List<PartnershipChoice> choices;
}

class PartnershipChoice {
  const PartnershipChoice({
    required this.id,
    required this.title,
    required this.description,
    this.funding = 0,
    this.friendship = 0,
    this.spaceContribution = 0,
    this.efficiencyBonuses = const {},
  });
  final String id, title, description;
  final int funding, friendship, spaceContribution;
  final Map<String, int> efficiencyBonuses;
}
