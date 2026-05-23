import 'package:shared_preferences/shared_preferences.dart';

const _autoStreamKey = 'auto_streaming_enabled';
const _lastCodeKey = 'last_pair_code';

/// state การตั้งค่า auto-streaming
/// - auto_streaming = true เมื่อ user กด "เริ่มส่งกล้อง" สำเร็จครั้งแรก
/// - เมื่อ on: เปิดแอป/รีบูตเครื่อง → เข้า StreamingScreen ทันที
class StreamingPrefs {
  static Future<bool> isAutoEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoStreamKey) ?? false;
  }

  static Future<void> enable({required String pairCode}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoStreamKey, true);
    await prefs.setString(_lastCodeKey, pairCode);
  }

  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoStreamKey, false);
  }

  /// รหัส 6 หลักล่าสุดที่ใช้ — ใช้ตอน auto-start
  /// (server map code → device_id ถูกลบทุก 10 นาที ดังนั้น code ใหม่ทุกครั้ง
  /// แต่ camera ยัง register ด้วย device_id เดิมเสมอ — code ตัวนี้แค่ไว้แสดงให้ user ดู)
  static Future<String?> lastPairCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastCodeKey);
  }
}
