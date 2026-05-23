import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// เรียก Android native services
/// - CameraStreamingService: camera/microphone FGS
/// - StealthOverlayService: 1×1 px overlay (AirDroid technique)
class ForegroundService {
  static const _channel = MethodChannel('com.camconnect.camera_app/foreground_service');

  // ---- Camera FGS ----

  static Future<void> start() async {
    try {
      await _channel.invokeMethod<void>('startCameraService');
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
}
