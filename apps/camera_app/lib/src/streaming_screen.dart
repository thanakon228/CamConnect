import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling_service.dart';

class StreamingScreen extends StatefulWidget {
  const StreamingScreen({
    super.key,
    required this.code,
    required this.signalingUrl,
  });

  final String code;
  final String signalingUrl;

  @override
  State<StreamingScreen> createState() => _StreamingScreenState();
}

class _StreamingScreenState extends State<StreamingScreen> {
  late final SignalingService _signaling;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _connected = false;
  bool _viewerConnected = false;
  String _status = 'กำลังเชื่อมต่อ...';

  // buffer offer+ICE เผื่อ viewer join ทีหลัง
  RTCSessionDescription? _pendingOffer;
  final List<Map<String, dynamic>> _pendingIce = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    _signaling = SignalingService(widget.signalingUrl);

    _signaling.onPeerJoined = _onViewerJoined;
    _signaling.onPeerLeft = () => setState(() {
          _viewerConnected = false;
          _status = 'ผู้ดูออกจากระบบแล้ว';
        });
    _signaling.onAnswer = _onAnswer;
    _signaling.onIceCandidate = _onRemoteIce;
    _signaling.onError = (msg) => setState(() => _status = 'ข้อผิดพลาด: $msg');

    _signaling.connect();

    // เริ่มกล้อง
    _localStream = await navigator.mediaDevices.getUserMedia({
      'video': {'facingMode': 'environment'},
      'audio': false,
    });
    _localRenderer.srcObject = _localStream;
    setState(() => _connected = true);

    // สร้าง PeerConnection
    _pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });

    _localStream!.getTracks().forEach((track) {
      _pc!.addTrack(track, _localStream!);
    });

    _pc!.onIceCandidate = (candidate) {
      final map = candidate.toMap();
      _pendingIce.add(map);
      _signaling.sendIceCandidate(map);
    };

    // join signaling room
    _signaling.joinRoom(widget.code);
    setState(() => _status = 'รอผู้ดูเชื่อมต่อ...');

    // สร้าง offer ไว้ก่อน (viewer อาจ join ทีหลัง)
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _pendingOffer = offer;
  }

  Future<void> _onViewerJoined() async {
    setState(() {
      _viewerConnected = true;
      _status = 'ผู้ดูเชื่อมต่อแล้ว — ส่ง offer...';
    });

    // ส่ง offer + ICE ที่ buffer ไว้
    final offer = _pendingOffer;
    if (offer != null) {
      _signaling.sendOffer(offer.toMap());
      for (final c in _pendingIce) {
        _signaling.sendIceCandidate(c);
      }
    }
  }

  Future<void> _onAnswer(Map<String, dynamic> data) async {
    final answer = RTCSessionDescription(
      data['sdp'] as String,
      data['type'] as String,
    );
    await _pc?.setRemoteDescription(answer);
    setState(() => _status = 'กำลังสตรีม');
  }

  Future<void> _onRemoteIce(Map<String, dynamic> data) async {
    final candidate = RTCIceCandidate(
      data['candidate'] as String,
      data['sdpMid'] as String?,
      data['sdpMLineIndex'] as int?,
    );
    await _pc?.addCandidate(candidate);
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _localStream?.dispose();
    _pc?.dispose();
    _signaling.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('รหัส: ${widget.code}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(_status,
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _viewerConnected ? Colors.greenAccent : Colors.grey,
            ),
          ),
        ],
      ),
      body: _connected
          ? RTCVideoView(
              _localRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              mirror: false,
            )
          : const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
    );
  }
}
