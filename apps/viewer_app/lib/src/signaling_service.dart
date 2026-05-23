import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

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

  void dispose() => _socket.dispose();
}
