/// เวลาใช้งานต่อแอพในช่วง 24 ชม. ของเครื่องลูก
class UsageStat {
  const UsageStat({
    required this.packageName,
    required this.appLabel,
    required this.totalTimeMs,
    required this.lastUsed,
  });

  final String packageName;
  final String appLabel;
  final int totalTimeMs;
  final int lastUsed;

  factory UsageStat.fromJson(Map<String, dynamic> j) => UsageStat(
        packageName: j['packageName'] as String? ?? '',
        appLabel: j['appLabel'] as String? ?? '',
        totalTimeMs: (j['totalTimeMs'] as int?) ?? 0,
        lastUsed: (j['lastUsed'] as int?) ?? 0,
      );

  /// human readable เช่น "1 ชม 30 นาที", "45 นาที", "30 วินาที"
  String get formattedTime {
    final secs = totalTimeMs ~/ 1000;
    if (secs < 60) return '$secs วินาที';
    if (secs < 3600) return '${secs ~/ 60} นาที';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    if (m == 0) return '$h ชั่วโมง';
    return '$h ชม $m นาที';
  }
}

class UsageReport {
  const UsageReport({required this.stats, required this.reportedAt});

  final List<UsageStat> stats;
  final int reportedAt;

  factory UsageReport.fromJson(Map<String, dynamic> j) {
    final list = j['stats'] as List? ?? const [];
    return UsageReport(
      stats: list
          .map((e) => UsageStat.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      reportedAt: (j['reportedAt'] as int?) ?? 0,
    );
  }
}
