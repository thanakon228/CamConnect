import 'dart:async';
import 'package:flutter/foundation.dart';
import 'device_status.dart';
import 'signaling_service.dart';

/// รายงาน DeviceStatus ให้ server ทุก [interval]
/// - skip emission ถ้า status ไม่เปลี่ยนจากครั้งก่อน (ลด bandwidth)
/// - เรียก [report] manual ได้ทันทีเช่นตอน app resume
/// - หยุดเองตอน [stop] หรือ owner dispose
class StatusReporter {
  StatusReporter({
    required this.signaling,
    required this.deviceId,
    this.interval = const Duration(seconds: 30),
  });

  final SignalingService signaling;
  final String deviceId;
  final Duration interval;

  Timer? _timer;
  DeviceStatus? _last;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    // ส่งทันทีรอบแรก แล้วค่อย periodic
    report();
    _timer = Timer.periodic(interval, (_) => report());
    debugPrint('[StatusReporter] started ($interval)');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
    debugPrint('[StatusReporter] stopped');
  }

  /// อ่าน status แล้วส่งถ้าเปลี่ยน
  Future<void> report() async {
    try {
      final status = await DeviceStatus.read();
      if (_last != null && status.isSameAs(_last!)) {
        return; // ไม่เปลี่ยน — skip
      }
      _last = status;
      signaling.reportStatus(deviceId: deviceId, status: status);
      debugPrint(
        '[StatusReporter] sent: bat=${status.batteryLevel}% '
        'net=${status.networkType}/${status.signalLevel} '
        'app=${status.foregroundApp} screen=${status.screenOn}',
      );
    } catch (e) {
      debugPrint('[StatusReporter] report failed: $e');
    }
  }
}
