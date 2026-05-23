import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Notification ที่เครื่องลูกได้รับ — ส่งให้ viewer ดูผ่าน socket
class NotifEvent {
  const NotifEvent({
    required this.packageName,
    required this.appLabel,
    required this.title,
    required this.text,
    required this.postTime,
  });

  final String packageName;
  final String appLabel;
  final String title;
  final String text;
  final int postTime;

  factory NotifEvent.fromMap(Map<dynamic, dynamic> m) => NotifEvent(
        packageName: m['packageName'] as String? ?? '',
        appLabel: m['appLabel'] as String? ?? '',
        title: m['title'] as String? ?? '',
        text: m['text'] as String? ?? '',
        postTime: m['postTime'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'packageName': packageName,
        'appLabel': appLabel,
        'title': title,
        'text': text,
        'postTime': postTime,
      };
}

/// ดึง notif events จาก native buffer แล้วส่งให้ server ผ่าน socket
/// เริ่มต้นเฉพาะเมื่อ user grant Notification Listener access แล้ว
class NotifDrainer {
  NotifDrainer({this.interval = const Duration(seconds: 10)});

  static const _channel =
      MethodChannel('com.camconnect.camera_app/foreground_service');

  final Duration interval;
  Timer? _timer;
  void Function(List<NotifEvent> events)? onDrained;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => _drain());
    debugPrint('[NotifDrainer] started ($interval)');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _drain() async {
    try {
      final list = await _channel.invokeListMethod<dynamic>('drainNotifBuffer');
      if (list == null || list.isEmpty) return;
      final events = list
          .map((e) => NotifEvent.fromMap(e as Map<dynamic, dynamic>))
          .toList();
      onDrained?.call(events);
    } catch (e) {
      debugPrint('[NotifDrainer] drain failed: $e');
    }
  }

  /// เช็ค Notification Listener access
  static Future<bool> hasPermission() async {
    try {
      final r = await _channel.invokeMethod<bool>('hasNotifListenerPermission');
      return r ?? false;
    } catch (e) {
      return false;
    }
  }

  /// เปิด Settings → Notification access
  static Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openNotifListenerSettings');
    } catch (e) {
      debugPrint('[NotifDrainer] openSettings failed: $e');
    }
  }
}
