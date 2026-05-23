import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Top-level handler — รับ FCM push ขณะ app อยู่ background หรือ killed
/// ต้องเป็น top-level function (ไม่ใช่ method) เพื่อให้ Flutter spawn background isolate ได้
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // ตอน background isolate รับ message — ไม่ทำอะไร เพราะ MainActivity จะถูก launch โดย
  // CamConnectMessagingService.kt (native side) อยู่แล้ว เราแค่ต้องมี handler นี้ไว้
  debugPrint('[fcm] background message: ${message.data}');
}

/// อ่าน FCM token + setup foreground handlers
class FcmService {
  static Future<String?> getToken() async {
    try {
      // ขอ permission notification (Android 13+ จะมี dialog)
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('[fcm] token: ${token?.substring(0, 20)}…');
      return token;
    } catch (e) {
      debugPrint('[fcm] getToken failed: $e');
      return null;
    }
  }

  static void setupForegroundHandler() {
    // ตอน app foreground ก็รับ message ได้ — สำหรับ debug
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('[fcm] foreground message: ${message.data}');
    });
  }
}
