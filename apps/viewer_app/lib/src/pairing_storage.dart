import 'package:shared_preferences/shared_preferences.dart';

const _key = 'paired_device_id';

/// เก็บ device_id ของกล้องที่ pair ไว้ — ใส่รหัสครั้งเดียว ใช้ได้ตลอด
class PairingStorage {
  static Future<String?> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key);
    if (v == null || v.isEmpty) return null;
    return v;
  }

  static Future<void> setDeviceId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, deviceId);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
