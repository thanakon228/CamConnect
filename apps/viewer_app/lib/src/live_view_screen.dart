import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'home_screen.dart';
import 'pairing_storage.dart';
import 'signaling_service.dart';

class LiveViewScreen extends StatefulWidget {
  const LiveViewScreen({
    super.key,
    required this.deviceId,
    required this.signalingUrl,
  });

  final String deviceId;
  final String signalingUrl;

  @override
  State<LiveViewScreen> createState() => _LiveViewScreenState();
}

class _LiveViewScreenState extends State<LiveViewScreen> {
  late final SignalingService _signaling;
  RTCPeerConnection? _pc;
  MediaStream? _remoteStream;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _hasVideo = false;
  String _status = 'กำลังเชื่อมต่อ...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _remoteRenderer.initialize();
    _signaling = SignalingService(widget.signalingUrl);

    _signaling.onOffer = _onOffer;
    _signaling.onIceCandidate = _onRemoteIce;
    _signaling.onPeerLeft = () => setState(() {
          _status = 'กล้องออกจากระบบแล้ว';
          _hasVideo = false;
        });
    _signaling.onError = (msg) => setState(() => _status = 'ข้อผิดพลาด: $msg');

    _signaling.connect();

    _pc = await createPeerConnection(<String, dynamic>{
      'iceServers': <Map<String, dynamic>>[],
      'sdpSemantics': 'unified-plan',
    });

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        setState(() {
          _remoteStream = event.streams[0];
          _remoteRenderer.srcObject = _remoteStream;
          _hasVideo = true;
          _status = 'กำลังรับสัญญาณ';
        });
      }
    };

    _pc!.onIceCandidate = (candidate) {
      _signaling.sendIceCandidate(candidate.toMap());
    };

    // join room ด้วย device_id ตรงๆ (ไม่ผ่านรหัส 6 หลักแล้ว)
    _signaling.joinRoom(widget.deviceId);
    setState(() => _status = 'รอสัญญาณกล้อง...');
  }

  Future<void> _onOffer(Map<String, dynamic> data) async {
    setState(() => _status = 'รับ offer แล้ว — กำลัง answer...');

    final offer = RTCSessionDescription(
      data['sdp'] as String,
      data['type'] as String,
    );
    await _pc?.setRemoteDescription(offer);
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    _signaling.sendAnswer(answer.toMap());
  }

  Future<void> _onRemoteIce(Map<String, dynamic> data) async {
    final candidate = RTCIceCandidate(
      data['candidate'] as String,
      data['sdpMid'] as String?,
      data['sdpMLineIndex'] as int?,
    );
    await _pc?.addCandidate(candidate);
  }

  Future<void> _confirmUnpair() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เลิกจับคู่กับกล้องนี้?'),
        content: const Text(
          'หลังจากนี้ต้องใส่รหัสใหม่อีกครั้งเพื่อเชื่อมต่อกล้องอีกครั้ง',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('เลิกจับคู่'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await PairingStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _remoteRenderer.dispose();
    _remoteStream?.dispose();
    _pc?.dispose();
    _signaling.dispose();
    super.dispose();
  }

  String get _shortId =>
      widget.deviceId.length > 8 ? widget.deviceId.substring(0, 8) : widget.deviceId;

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
            Text('กล้อง: $_shortId',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(_status,
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hasVideo ? Colors.greenAccent : Colors.grey,
              ),
            ),
          ),
          IconButton(
            tooltip: 'เลิกจับคู่',
            icon: const Icon(Icons.link_off),
            onPressed: _confirmUnpair,
          ),
        ],
      ),
      body: _hasVideo
          ? RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.tealAccent),
                  const SizedBox(height: 20),
                  Text(
                    _status,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
    );
  }
}
