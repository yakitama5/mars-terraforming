import 'game_content.dart';

/// A saved completion receipt; reading it never applies gameplay rewards.
class CompletionNotice {
  const CompletionNotice({
    required this.id,
    required this.planId,
    required this.taskId,
    required this.simulatedMs,
    this.count = 1,
    this.cityId,
    this.plotIndex,
    this.targetLevel,
  });

  final int id, simulatedMs, count;
  final String planId, taskId;
  final String? cityId;
  final int? plotIndex, targetLevel;
  TaskDefinition get definition => GameContent.tasks[taskId]!;
  String get title => '${definition.name}が完了${count > 1 ? '（$count回）' : ''}';
  String get location => cityId == null
      ? GameContent.facilities[definition.facilityId]!.name
      : '${GameContent.cities[cityId]!.name}・区画 ${plotIndex! + 1}・Lv.$targetLevel';

  Map<String, dynamic> toJson() => {
    'id': id,
    'planId': planId,
    'taskId': taskId,
    'simulatedMs': simulatedMs,
    'count': count,
    'cityId': cityId,
    'plotIndex': plotIndex,
    'targetLevel': targetLevel,
  };

  factory CompletionNotice.fromJson(Map<String, dynamic> json) {
    final notice = CompletionNotice(
      id: json['id'] as int,
      planId: json['planId'] as String,
      taskId: json['taskId'] as String,
      simulatedMs: json['simulatedMs'] as int,
      count: json['count'] as int,
      cityId: json['cityId'] as String?,
      plotIndex: json['plotIndex'] as int?,
      targetLevel: json['targetLevel'] as int?,
    );
    final task = GameContent.tasks[notice.taskId];
    final city = GameContent.cities[notice.cityId];
    if (notice.id < 1 ||
        notice.count < 1 ||
        notice.simulatedMs < 0 ||
        notice.planId.isEmpty ||
        task == null ||
        (task.unique && notice.count != 1) ||
        (task.districtId != null) != (notice.cityId != null) ||
        (task.districtId != null &&
            city != null &&
            city.planet != GameContent.districts[task.districtId]!.planet) ||
        (notice.cityId != null &&
            (city == null ||
                notice.plotIndex == null ||
                notice.plotIndex! < 0 ||
                notice.plotIndex! >= city.plotCount ||
                notice.targetLevel == null ||
                notice.targetLevel! < 1 ||
                notice.targetLevel! > 3)) ||
        (notice.cityId == null &&
            (notice.plotIndex != null || notice.targetLevel != null))) {
      throw const FormatException('完了通知の保存が不正です');
    }
    return notice;
  }
}
