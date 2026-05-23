import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'device_status.dart';
import 'notif_event.dart';
import 'usage_stat.dart';

typedef JsonMap = Map<String, dynamic>;

class SignalingService {
  SignalingService(this._url);

  final String _url;
  late final io.Socket _socket;

  // callbacks
  void Function()? onPeerJoined;
  void Function()? onPeerLeft;
  void Function(JsonMap offer)? onOffer;
  void Function(JsonMap answer)? onAnswer;
  void Function(JsonMap candidate)? onIceCandidate;
  void Function(String msg)? onError;

  /// viewer ส่ง config มา → เก็บ + apply (เรียกได้ทั้งตอน register-camera + ตอน viewer save ใหม่)
  void Function(JsonMap config)? onConfigPushed;

  /// viewer สั่งสลับกล้องหน้า/หลัง
  void Function()? onSwitchCamera;

  /// viewer toggle mic — true = on, false = off
  void Function(bool enabled)? onToggleMic;

  /// viewer ขอ refresh usage stats — camera ต้องอ่านสด + ส่งกลับ
  void Function()? onFetchUsageStats;

  /// viewer สั่ง factory-reset — camera ต้อง clear pref + restore UI + stop FGS
  void Function()? onFactoryReset;

  /// socket reconnect — UI ต้อง re-register + re-join room
  /// (server ล้าง state ฝั่งตัวเองเมื่อ socket disconnect)
  void Function()? onReconnect;

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
    _socket.on('config-pushed',
        (data) => onConfigPushed?.call(Map<String, dynamic>.from(data as Map)));
    _socket.on('switch-camera', (_) => onSwitchCamera?.call());
    _socket.on('fetch-usage-stats', (_) => onFetchUsageStats?.call());
    _socket.on('factory-reset', (_) => onFactoryReset?.call());
    _socket.on('toggle-mic', (data) {
      // payload: { enabled: bool }
      try {
        final m = Map<String, dynamic>.from(data as Map);
        onToggleMic?.call((m['enabled'] as bool?) ?? false);
      } catch (e) {
        // payload ผิดรูป → ignore เลย (อย่าเปิด mic เผื่อความเป็นส่วนตัว)
        debugPrint('[signaling] toggle-mic malformed: $e — ignored');
      }
    });
    _socket.on('error', (msg) => onError?.call(msg.toString()));
    _socket.on('connect', (_) => debugPrint('[signaling] connected'));
    _socket.on('disconnect', (_) => debugPrint('[signaling] disconnected'));
    _socket.on('reconnect', (_) {
      debugPrint('[signaling] reconnected — UI ต้อง re-subscribe');
      onReconnect?.call();
    });
  }

  void joinRoom(String roomKey) => _socket.emit('join', roomKey);
  void sendOffer(JsonMap offer) => _socket.emit('offer', offer);
  void sendAnswer(JsonMap answer) => _socket.emit('answer', answer);
  void sendIceCandidate(JsonMap candidate) => _socket.emit('ice-candidate', candidate);

  /// camera แจ้งตัวตน + pair code + FCM token ให้ server
  /// เรียกหลัง connect() แล้ว (รอ socket connect ก่อน — เก็บ pending ไว้)
  void registerCamera({
    required String deviceId,
    required String code,
    String? fcmToken,
  }) {
    final payload = <String, dynamic>{'deviceId': deviceId, 'code': code};
    if (fcmToken != null && fcmToken.isNotEmpty) {
      payload['fcmToken'] = fcmToken;
    }
    if (_socket.connected) {
      _socket.emit('register-camera', payload);
    } else {
      _socket.onConnect((_) => _socket.emit('register-camera', payload));
    }
  }

  /// camera รายงานสถานะเครื่อง (battery/signal/foreground app/screen)
  /// — ไม่ต้อง ack เพราะ server เงียบ (status มาบ่อย ลด overhead)
  void reportStatus({required String deviceId, required DeviceStatus status}) {
    final payload = <String, dynamic>{'deviceId': deviceId, 'status': status.toJson()};
    if (_socket.connected) {
      _socket.emit('report-status', payload);
    } else {
      _socket.onConnect((_) => _socket.emit('report-status', payload));
    }
  }

  /// camera ส่ง batch ของ notif events ที่ดักจับได้
  void reportNotifBatch({
    required String deviceId,
    required List<NotifEvent> events,
  }) {
    if (events.isEmpty) return;
    final payload = <String, dynamic>{
      'deviceId': deviceId,
      'events': events.map((e) => e.toJson()).toList(),
    };
    if (_socket.connected) {
      _socket.emit('report-notif', payload);
    } else {
      _socket.onConnect((_) => _socket.emit('report-notif', payload));
    }
  }

  /// camera ส่ง snapshot usage stats 24h
  void reportUsageStats({
    required String deviceId,
    required List<UsageStat> stats,
  }) {
    final payload = <String, dynamic>{
      'deviceId': deviceId,
      'stats': stats.map((e) => e.toJson()).toList(),
    };
    if (_socket.connected) {
      _socket.emit('report-usage-stats', payload);
    } else {
      _socket.onConnect((_) => _socket.emit('report-usage-stats', payload));
    }
  }

  void dispose() => _socket.dispose();

  // สร้างรหัส 6 หลัก (ตัวอักษร A-Z ไม่มีตัวเลขสับสน)
  static String generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}
