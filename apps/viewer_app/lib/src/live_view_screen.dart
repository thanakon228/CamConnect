import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'home_screen.dart';
import 'pairing_storage.dart';
import 'settings_screen.dart';
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
  String _status = 'กำลังเรียกเครื่องลูก...';

  // ติดตามสถานะ mic ใน UI (camera-side คือ source of truth จริง — viewer toggle เท่านั้น)
  bool _micOn = false;

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
    setState(() => _status = 'กำลังเรียกเครื่องลูก... รอการอนุญาต');
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

  /// ส่งสัญญาณปลุกกล้อง (FCM) — ใช้เมื่อกล้อง offline หรือเปิดไม่ได้
  Future<void> _wakeCamera() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('กำลังส่งสัญญาณปลุกกล้อง...'),
        duration: Duration(seconds: 2),
      ),
    );
    try {
      await _signaling.wakeCamera(widget.deviceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ส่งสัญญาณปลุกแล้ว — รอกล้องตอบกลับ'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ปลุกไม่สำเร็จ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _switchCamera() {
    _signaling.switchCamera();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('สลับกล้องหน้า ↔ หลัง'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _toggleMic() {
    final next = !_micOn;
    _signaling.toggleMic(next);
    setState(() => _micOn = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(next ? 'เปิดไมโครโฟน' : 'ปิดไมโครโฟน'),
        backgroundColor: next ? Colors.green : Colors.grey.shade700,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          deviceId: widget.deviceId,
          signalingUrl: widget.signalingUrl,
        ),
      ),
    );
  }

  /// ตัวเลือกเลิกจับคู่:
  /// 1. ยกเลิก
  /// 2. เลิกฝั่งเรา — clear PairingStorage ฝั่ง viewer (camera ยังสตรีมต่อ)
  /// 3. รีเซ็ตเครื่องลูกด้วย — ส่ง factory-reset socket event ก่อน
  Future<void> _confirmUnpair() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เลิกจับคู่กับกล้องนี้?'),
        content: const Text(
          'เลือกวิธีเลิกจับคู่:\n\n'
          '• "เลิกแค่ฝั่งเรา" — ลบเฉพาะเครื่องนี้ — กล้องลูกยังสตรีมต่อ '
          '(ใช้ตอนแม่หลายคนแชร์กล้องเดียวกัน)\n\n'
          '• "รีเซ็ตเครื่องลูก" — สั่งเครื่องลูกหยุดสตรีม + คืน UI ปกติ '
          '(สำหรับการ pair ใหม่)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('viewer-only'),
            child: const Text('เลิกแค่ฝั่งเรา'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop('full-reset'),
            child: const Text('รีเซ็ตเครื่องลูก'),
          ),
        ],
      ),
    );

    if (choice == null || choice == 'cancel') return;

    if (choice == 'full-reset') {
      try {
        final relayed = await _signaling.factoryResetCamera(widget.deviceId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(relayed
                ? 'สั่งรีเซ็ตเครื่องลูกแล้ว'
                : 'กล้อง offline — ล้าง state ฝั่ง server แล้ว (กล้องจะรีเซ็ตเมื่อ online)'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('รีเซ็ตไม่สำเร็จ: $e'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

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
            tooltip: _micOn ? 'ปิดไมโครโฟน' : 'เปิดไมโครโฟน',
            icon: Icon(_micOn ? Icons.mic : Icons.mic_off,
                color: _micOn ? Colors.greenAccent : Colors.white70),
            onPressed: _toggleMic,
          ),
          IconButton(
            tooltip: 'สลับกล้องหน้า/หลัง',
            icon: const Icon(Icons.cameraswitch),
            onPressed: _switchCamera,
          ),
          IconButton(
            tooltip: 'ปลุกกล้อง',
            icon: const Icon(Icons.notifications_active),
            onPressed: _wakeCamera,
          ),
          IconButton(
            tooltip: 'ตั้งค่า',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
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
