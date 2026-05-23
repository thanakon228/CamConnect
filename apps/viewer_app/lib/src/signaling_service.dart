import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'camera_config.dart';
import 'device_status.dart';
import 'notif_event.dart';

typedef JsonMap = Map<String, dynamic>;

class SignalingService {
  SignalingService(this._url);

  final String _url;
  late final io.Socket _socket;

  void Function()? onPeerJoined;
  void Function()? onPeerLeft;
  void Function(JsonMap offer)? onOffer;
  void Function(JsonMap answer)? onAnswer;
  void Function(JsonMap candidate)? onIceCandidate;
  void Function(String msg)? onError;

  /// camera รายงาน status สด (หลัง subscribe-status)
  void Function(String deviceId, DeviceStatus status)? onStatusUpdated;

  /// camera ส่ง notif batch มา (หลัง subscribe-notifs)
  void Function(String deviceId, List<NotifEvent> events)? onNotifPushed;

  void connect() {
    _socket = io.io(_url, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    _socket.on('peer-joined', (_) => onPeerJoined?.call());
    _socket.on('peer-left', (_) => onPeerLeft?.call());
    _socket.on('offer', (data) => onOffer?.call(Map<String, dynamic>.from(data as Map)));
    _socket.on('answer', (data) => onAnswer?.call(Map<String, dynamic>.from(data as Map)));
    _socket.on('ice-candidate', (data) => onIceCandidate?.call(Map<String, dynamic>.from(data as Map)));
    _socket.on('status-updated', (data) {
      final m = Map<String, dynamic>.from(data as Map);
      final deviceId = m['deviceId'] as String?;
      final s = m['status'];
      if (deviceId == null || s == null) return;
      onStatusUpdated?.call(deviceId, DeviceStatus.fromJson(Map<String, dynamic>.from(s as Map)));
    });
    _socket.on('notif-pushed', (data) {
      final m = Map<String, dynamic>.from(data as Map);
      final deviceId = m['deviceId'] as String?;
      final list = m['events'] as List?;
      if (deviceId == null || list == null) return;
      final events = list
          .map((e) => NotifEvent.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      onNotifPushed?.call(deviceId, events);
    });
    _socket.on('error', (msg) => onError?.call(msg.toString()));
    _socket.on('connect', (_) => debugPrint('[signaling] connected'));
    _socket.on('disconnect', (_) => debugPrint('[signaling] disconnected'));
  }

  void joinRoom(String roomKey) => _socket.emit('join', roomKey);
  void sendOffer(JsonMap offer) => _socket.emit('offer', offer);
  void sendAnswer(JsonMap answer) => _socket.emit('answer', answer);
  void sendIceCandidate(JsonMap candidate) => _socket.emit('ice-candidate', candidate);

  /// แลก pair code 6 หลัก → device_id (one-shot request/response)
  /// คืนค่า device_id ถ้าสำเร็จ หรือ throw String error
  Future<String> pairViewer(String code) {
    final completer = Completer<String>();

    void okHandler(dynamic data) {
      if (completer.isCompleted) return;
      try {
        final m = Map<String, dynamic>.from(data as Map);
        final deviceId = m['deviceId'] as String?;
        if (deviceId == null || deviceId.isEmpty) {
          completer.completeError('ไม่ได้รับ device_id จากเซิร์ฟเวอร์');
        } else {
          completer.complete(deviceId);
        }
      } catch (e) {
        completer.completeError('ตอบกลับไม่ถูกต้อง: $e');
      }
    }

    void errHandler(dynamic msg) {
      if (!completer.isCompleted) completer.completeError(msg.toString());
    }

    _socket.once('pair-viewer-ok', okHandler);
    _socket.once('pair-viewer-error', errHandler);

    void emitNow() => _socket.emit('pair-viewer', <String, dynamic>{'code': code.toUpperCase()});
    if (_socket.connected) {
      emitNow();
    } else {
      _socket.onConnect((_) => emitNow());
    }

    // timeout กันค้าง 10 วินาที
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw 'timeout: เซิร์ฟเวอร์ไม่ตอบ',
    );
  }

  // ---- Wake / Config control ----

  /// ส่งสัญญาณปลุกกล้องผ่าน FCM (server เรียก pushWakeCamera)
  /// ใช้เมื่อกล้อง offline หรือเปิดไม่ได้
  Future<void> wakeCamera(String deviceId) {
    final completer = Completer<void>();

    void okHandler(dynamic _) {
      if (!completer.isCompleted) completer.complete();
    }

    void errHandler(dynamic msg) {
      if (!completer.isCompleted) completer.completeError(msg.toString());
    }

    _socket.once('wake-camera-ok', okHandler);
    _socket.once('wake-camera-error', errHandler);

    _emitOrQueue('wake-camera', <String, dynamic>{'deviceId': deviceId});

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw 'timeout: เซิร์ฟเวอร์ไม่ตอบ',
    );
  }

  /// ดึง config ปัจจุบันของกล้องจาก server (ก่อนเปิดหน้า Settings)
  Future<CameraConfig> getConfig(String deviceId) {
    final completer = Completer<CameraConfig>();

    void okHandler(dynamic data) {
      if (completer.isCompleted) return;
      try {
        final m = Map<String, dynamic>.from(data as Map);
        final cfg = Map<String, dynamic>.from(m['config'] as Map);
        completer.complete(CameraConfig.fromJson(cfg));
      } catch (e) {
        completer.completeError('ตอบกลับไม่ถูกต้อง: $e');
      }
    }

    void errHandler(dynamic msg) {
      if (!completer.isCompleted) completer.completeError(msg.toString());
    }

    _socket.once('config-current', okHandler);
    _socket.once('get-config-error', errHandler);

    _emitOrQueue('get-config', <String, dynamic>{'deviceId': deviceId});

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw 'timeout: เซิร์ฟเวอร์ไม่ตอบ',
    );
  }

  /// บันทึก config ใหม่ลง server + server จะ relay ให้กล้องทันที (ถ้า online)
  Future<CameraConfig> updateConfig(String deviceId, CameraConfig config) {
    final completer = Completer<CameraConfig>();

    void okHandler(dynamic data) {
      if (completer.isCompleted) return;
      try {
        final m = Map<String, dynamic>.from(data as Map);
        completer.complete(CameraConfig.fromJson(m));
      } catch (e) {
        completer.completeError('ตอบกลับไม่ถูกต้อง: $e');
      }
    }

    void errHandler(dynamic msg) {
      if (!completer.isCompleted) completer.completeError(msg.toString());
    }

    _socket.once('update-config-ok', okHandler);
    _socket.once('update-config-error', errHandler);

    _emitOrQueue('update-config', <String, dynamic>{
      'deviceId': deviceId,
      'config': config.toJson(),
    });

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw 'timeout: เซิร์ฟเวอร์ไม่ตอบ',
    );
  }

  // ---- Device status (subscribe pattern) ----

  /// ดึง status snapshot ปัจจุบัน (one-shot)
  Future<DeviceStatus> getStatus(String deviceId) {
    final completer = Completer<DeviceStatus>();

    void okHandler(dynamic data) {
      if (completer.isCompleted) return;
      try {
        final m = Map<String, dynamic>.from(data as Map);
        final s = Map<String, dynamic>.from(m['status'] as Map);
        completer.complete(DeviceStatus.fromJson(s));
      } catch (e) {
        completer.completeError('ตอบกลับไม่ถูกต้อง: $e');
      }
    }

    void errHandler(dynamic msg) {
      if (!completer.isCompleted) completer.completeError(msg.toString());
    }

    _socket.once('status-current', okHandler);
    _socket.once('get-status-error', errHandler);

    _emitOrQueue('get-status', <String, dynamic>{'deviceId': deviceId});

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw 'timeout: ยังไม่มี status — กล้องอาจยังไม่ online',
    );
  }

  /// subscribe live status updates — server จะ emit 'status-updated' มาเรื่อยๆ
  /// → ตัว callback ใน [onStatusUpdated]
  void subscribeStatus(String deviceId) =>
      _emitOrQueue('subscribe-status', <String, dynamic>{'deviceId': deviceId});

  void unsubscribeStatus(String deviceId) =>
      _emitOrQueue('unsubscribe-status', <String, dynamic>{'deviceId': deviceId});

  // ---- Notification mirror ----

  /// ดึง notif buffer ล่าสุดทั้งหมด (snapshot)
  Future<List<NotifEvent>> getNotifs(String deviceId) {
    final completer = Completer<List<NotifEvent>>();

    void okHandler(dynamic data) {
      if (completer.isCompleted) return;
      try {
        final m = Map<String, dynamic>.from(data as Map);
        final list = m['events'] as List? ?? const [];
        completer.complete(
          list
              .map((e) => NotifEvent.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList(),
        );
      } catch (e) {
        completer.completeError('ตอบกลับไม่ถูกต้อง: $e');
      }
    }

    void errHandler(dynamic msg) {
      if (!completer.isCompleted) completer.completeError(msg.toString());
    }

    _socket.once('notifs-current', okHandler);
    _socket.once('get-notifs-error', errHandler);

    _emitOrQueue('get-notifs', <String, dynamic>{'deviceId': deviceId});

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw 'timeout',
    );
  }

  void subscribeNotifs(String deviceId) =>
      _emitOrQueue('subscribe-notifs', <String, dynamic>{'deviceId': deviceId});

  void unsubscribeNotifs(String deviceId) =>
      _emitOrQueue('unsubscribe-notifs', <String, dynamic>{'deviceId': deviceId});

  // ---- Stream controls (ใช้ใน LiveViewScreen ขณะกำลังสตรีม) ----

  /// สลับกล้องหน้า/หลังบนเครื่องลูก — broadcast ใน room ที่ join อยู่
  void switchCamera() => _socket.emit('switch-camera', <String, dynamic>{});

  /// เปิด/ปิด mic ของเครื่องลูก (default ตอนเริ่มสตรีม = off)
  void toggleMic(bool enabled) =>
      _socket.emit('toggle-mic', <String, dynamic>{'enabled': enabled});

  /// helper: ถ้า socket ยังไม่ connect → รอ then emit
  void _emitOrQueue(String event, dynamic payload) {
    if (_socket.connected) {
      _socket.emit(event, payload);
    } else {
      _socket.onConnect((_) => _socket.emit(event, payload));
    }
  }

  void dispose() => _socket.dispose();
}
