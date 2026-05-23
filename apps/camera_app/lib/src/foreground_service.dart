import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// เรียก Android foreground service ฝั่ง native
/// ทำให้กล้องสตรีมต่อได้แม้ user ปิดแอป/ปิดจอ
class ForegroundService {
  static const _channel = MethodChannel('com.camconnect.camera_app/foreground_service');

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
}
