/// สถานะเครื่องลูกที่ viewer (เครื่องแม่) ได้รับจาก server ผ่าน socket
/// — server cache snapshot ล่าสุด + relay ให้ subscriber
class DeviceStatus {
  const DeviceStatus({
    required this.batteryLevel,
    required this.batteryCharging,
    required this.networkType,
    required this.signalLevel,
    required this.foregroundApp,
    required this.screenOn,
    required this.lastUpdate,
  });

  /// 0-100, -1 = ไม่ทราบ
  final int batteryLevel;
  final bool batteryCharging;

  /// 'wifi' | 'cellular' | 'none'
  final String networkType;

  /// 0-4 (ขีดสัญญาณ), -1 = ไม่ทราบ
  final int signalLevel;

  /// label ของแอพที่ใช้อยู่ หรือ null
  final String? foregroundApp;
  final bool screenOn;

  /// epoch ms ที่ server บันทึก status นี้
  final int lastUpdate;

  factory DeviceStatus.fromJson(Map<String, dynamic> json) => DeviceStatus(
        batteryLevel: (json['batteryLevel'] as int?) ?? -1,
        batteryCharging: (json['batteryCharging'] as bool?) ?? false,
        networkType: (json['networkType'] as String?) ?? 'none',
        signalLevel: (json['signalLevel'] as int?) ?? -1,
        foregroundApp: json['foregroundApp'] as String?,
        screenOn: (json['screenOn'] as bool?) ?? false,
        lastUpdate: (json['lastUpdate'] as int?) ?? 0,
      );

  /// เวลาที่ผ่านไปตั้งแต่ status update ครั้งล่าสุด
  Duration get age =>
      Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - lastUpdate);

  /// online ถ้า status update ภายใน 90 วินาที (3× interval reporter)
  bool get isOnline => age < const Duration(seconds: 90);
}
