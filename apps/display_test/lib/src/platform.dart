import 'package:flutter/services.dart';

/// MethodChannel wrapper สำหรับ native API
class Platform {
  static const _ch = MethodChannel('com.displaytest.display_test/platform');

  // ---- Notification ----

  static Future<void> ensureNotificationPermission() async {
    await _ch.invokeMethod('ensureNotificationPermission');
  }

  static Future<void> sendNotification({
    required String title,
    required String body,
    required String channel, // default / high / max
    required String style, // standard / bigtext / bigpicture / inbox
    required String category, // none / message / call / alarm / event
    required int actions, // 0, 1, 2
    required bool sound,
    required bool vibrate,
    required bool autoCancel,
  }) async {
    await _ch.invokeMethod('sendNotification', {
      'title': title,
      'body': body,
      'channel': channel,
      'style': style,
      'category': category,
      'actions': actions,
      'sound': sound,
      'vibrate': vibrate,
      'autoCancel': autoCancel,
    });
  }

  // ---- Overlay ----

  static Future<bool> hasOverlayPermission() async {
    final r = await _ch.invokeMethod<bool>('hasOverlayPermission');
    return r ?? false;
  }

  static Future<void> requestOverlayPermission() async {
    await _ch.invokeMethod('requestOverlayPermission');
  }

  static Future<void> showOverlay({
    required int width,
    required int height,
    required int x,
    required int y,
    required double alpha,
    required int color, // ARGB int
    required bool touchable,
  }) async {
    await _ch.invokeMethod('showOverlay', {
      'width': width,
      'height': height,
      'x': x,
      'y': y,
      'alpha': alpha,
      'color': color,
      'touchable': touchable,
    });
  }

  static Future<void> hideOverlay() async {
    await _ch.invokeMethod('hideOverlay');
  }
}
