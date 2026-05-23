import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'foreground_service.dart';
import 'streaming_screen.dart';
import 'streaming_prefs.dart';
import 'signaling_service.dart';

const _signalingUrl = String.fromEnvironment(
  'SIGNALING_URL',
  defaultValue: 'http://192.168.1.33:4001',
);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.autoStart = false});

  /// ถ้า true → ตรวจ StreamingPrefs.isAutoEnabled() แล้ว navigate ไป StreamingScreen
  /// อัตโนมัติ (ใช้ตอน app launch จาก boot หรือ launcher ครั้งต่อๆ ไป)
  final bool autoStart;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _code;
  bool _autoEnabled = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _maybeAutoStart();
  }

  Future<void> _maybeAutoStart() async {
    final enabled = await StreamingPrefs.isAutoEnabled();
    if (!mounted) return;
    setState(() {
      _autoEnabled = enabled;
      _checking = false;
    });

    if (enabled && widget.autoStart) {
      // ใช้ pair code เดิม (หรือสร้างใหม่ถ้าไม่มี — server map ใหม่ทุกครั้ง)
      final lastCode =
          await StreamingPrefs.lastPairCode() ?? SignalingService.generateCode();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => StreamingScreen(
            code: lastCode,
            signalingUrl: _signalingUrl,
          ),
        ),
      );
    }
  }

  void _generateCode() {
    setState(() => _code = SignalingService.generateCode());
  }

  void _startStreaming() {
    if (_code == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StreamingScreen(
          code: _code!,
          signalingUrl: _signalingUrl,
        ),
      ),
    ).then((_) async {
      // กลับมา home_screen → refresh สถานะ
      final enabled = await StreamingPrefs.isAutoEnabled();
      if (!mounted) return;
      setState(() => _autoEnabled = enabled);
    });
  }

  Future<void> _stopAutoStreaming() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('หยุดการสตรีมอัตโนมัติ?'),
        content: const Text(
          'หลังจากนี้ต้องกด "เริ่มส่งกล้อง" ใหม่ทุกครั้งที่เปิดแอป '
          'หรือรีบูตเครื่อง',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('หยุด'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await StreamingPrefs.disable();
    await ForegroundService.stop();
    if (!mounted) return;
    setState(() => _autoEnabled = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.inversePrimary,
        title: const Text('CamConnect — กล้อง'),
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _autoEnabled ? Icons.cloud_done : Icons.videocam,
                      size: 80,
                      color: _autoEnabled ? Colors.green : Colors.indigo,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _autoEnabled
                          ? 'กำลังสตรีมอัตโนมัติ'
                          : 'แชร์กล้องของคุณ',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _autoEnabled
                          ? 'กล้องเครื่องนี้จะสตรีมต่อเนื่องแม้ปิดแอป — '
                              'แตะ "หยุด" ถ้าต้องการเลิกใช้'
                          : 'กดสร้างรหัส แล้วให้อีกฝั่งใส่รหัสนี้เพื่อดูกล้อง',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 40),
                    if (_autoEnabled) ...[
                      FilledButton.icon(
                        onPressed: _openPreview,
                        icon: const Icon(Icons.visibility),
                        label: const Text('ดูพรีวิวกล้อง'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _stopAutoStreaming,
                        icon: const Icon(Icons.stop),
                        label: const Text('หยุดการสตรีมอัตโนมัติ'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                        ),
                      ),
                    ] else if (_code != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.indigo.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _code!,
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 6,
                                color: Colors.indigo,
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              icon:
                                  const Icon(Icons.copy, color: Colors.indigo),
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: _code!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('คัดลอกรหัสแล้ว')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _startStreaming,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('เริ่มส่งกล้อง'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _generateCode,
                        child: const Text('สร้างรหัสใหม่'),
                      ),
                    ] else ...[
                      FilledButton.icon(
                        onPressed: _generateCode,
                        icon: const Icon(Icons.vpn_key),
                        label: const Text('สร้างรหัสเชื่อมต่อ'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _openPreview() async {
    final code =
        await StreamingPrefs.lastPairCode() ?? SignalingService.generateCode();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StreamingScreen(
          code: code,
          signalingUrl: _signalingUrl,
        ),
      ),
    );
  }
}
