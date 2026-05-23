import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// สถานะเครื่องลูก (camera_app) ที่ส่งให้ viewer (เครื่องแม่) ผ่าน signaling server
/// อ่านจาก native ผ่าน MethodChannel — ไม่ cache, ทุกครั้งที่เรียก [read] = อ่านสด
class DeviceStatus {
  const DeviceStatus({
    required this.batteryLevel,
    required this.batteryCharging,
    required this.networkType,
    required this.signalLevel,
    required this.foregroundApp,
    required this.screenOn,
  });

  /// 0-100, -1 = ไม่ทราบ
  final int batteryLevel;
  final bool batteryCharging;

  /// 'wifi' | 'cellular' | 'none'
  final String networkType;

  /// 0-4 (ขีดสัญญาณ), -1 = ไม่ทราบ
  final int signalLevel;

  /// ชื่อแอพ (label) หรือ null ถ้าไม่มี permission / ไม่ทราบ
  final String? foregroundApp;
  final bool screenOn;

  static const _channel =
      MethodChannel('com.camconnect.camera_app/foreground_service');

  /// อ่าน status สดจาก native
  static Future<DeviceStatus> read() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('readDeviceStatus');
      if (m == null) return _unknown;
      return DeviceStatus(
        batteryLevel: (m['batteryLevel'] as int?) ?? -1,
        batteryCharging: (m['batteryCharging'] as bool?) ?? false,
        networkType: (m['networkType'] as String?) ?? 'none',
        signalLevel: (m['signalLevel'] as int?) ?? -1,
        foregroundApp: m['foregroundApp'] as String?,
        screenOn: (m['screenOn'] as bool?) ?? false,
      );
    } catch (e) {
      debugPrint('[DeviceStatus] read failed: $e');
      return _unknown;
    }
  }

  /// เช็คว่ามี PACKAGE_USAGE_STATS permission แล้วหรือยัง
  static Future<bool> hasUsageStatsPermission() async {
    try {
      final r = await _channel.invokeMethod<bool>('hasUsageStatsPermission');
      return r ?? false;
    } catch (e) {
      return false;
    }
  }

  /// เปิดหน้า Settings → Usage access เพื่อให้ user grant manual
  static Future<void> openUsageStatsSettings() async {
    try {
      await _channel.invokeMethod<void>('openUsageStatsSettings');
    } catch (e) {
      debugPrint('[DeviceStatus] openUsageStatsSettings failed: $e');
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'batteryLevel': batteryLevel,
        'batteryCharging': batteryCharging,
        'networkType': networkType,
        'signalLevel': signalLevel,
        'foregroundApp': foregroundApp,
        'screenOn': screenOn,
      };

  /// เปรียบเทียบเพื่อ skip report ถ้าไม่เปลี่ยน (ลด traffic)
  bool isSameAs(DeviceStatus other) =>
      batteryLevel == other.batteryLevel &&
      batteryCharging == other.batteryCharging &&
      networkType == other.networkType &&
      signalLevel == other.signalLevel &&
      foregroundApp == other.foregroundApp &&
      screenOn == other.screenOn;

  static const _unknown = DeviceStatus(
    batteryLevel: -1,
    batteryCharging: false,
    networkType: 'none',
    signalLevel: -1,
    foregroundApp: null,
    screenOn: false,
  );
}
