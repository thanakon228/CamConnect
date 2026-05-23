import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _key = 'device_id';

/// อ่าน/สร้าง persistent device_id ของกล้องเครื่องนี้
/// เก็บใน SharedPreferences — ติดตัวเครื่องไปตลอด (จน user ลบ data หรือ uninstall)
class DeviceIdStore {
  static String? _cached;

  static Future<String> getOrCreate() async {
    if (_cached != null) return _cached!;

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_key, id);
    }
    _cached = id;
    return id;
  }
}
