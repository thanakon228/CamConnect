import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// เวลาใช้งานต่อแอพในช่วง 24 ชั่วโมงล่าสุด
/// อ่านจาก UsageStatsManager (Android) ผ่าน MethodChannel
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

  factory UsageStat.fromMap(Map<dynamic, dynamic> m) => UsageStat(
        packageName: m['packageName'] as String? ?? '',
        appLabel: m['appLabel'] as String? ?? '',
        totalTimeMs: (m['totalTimeMs'] as int?) ?? 0,
        lastUsed: (m['lastUsed'] as int?) ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'packageName': packageName,
        'appLabel': appLabel,
        'totalTimeMs': totalTimeMs,
        'lastUsed': lastUsed,
      };

  static const _channel =
      MethodChannel('com.camconnect.camera_app/foreground_service');

  /// ดึง stats จาก native — default 24h, top 15
  static Future<List<UsageStat>> read({
    Duration range = const Duration(hours: 24),
    int topN = 15,
  }) async {
    try {
      final list = await _channel.invokeListMethod<dynamic>('readUsageStats', {
        'rangeMs': range.inMilliseconds,
        'topN': topN,
      });
      if (list == null) return [];
      return list
          .map((e) => UsageStat.fromMap(e as Map<dynamic, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[UsageStat] read failed: $e');
      return [];
    }
  }
}
