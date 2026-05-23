import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

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

  void dispose() => _socket.dispose();

  // สร้างรหัส 6 หลัก (ตัวอักษร A-Z ไม่มีตัวเลขสับสน)
  static String generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}
