import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'foreground_service.dart';
import 'permissions_screen.dart';
import 'streaming_screen.dart';
import 'streaming_prefs.dart';
import 'signaling_service.dart';

const _signalingUrl = String.fromEnvironment(
  'SIGNALING_URL',
  defaultValue: 'http://192.168.1.33:4001',
);

/// 3 สถานะของหน้านี้:
/// 1. _checking — รอโหลด prefs (render เปล่า)
/// 2. ไม่ pair: แสดงปุ่ม "สร้างรหัสเชื่อมต่อ" + flow generate code → "เริ่มส่งกล้อง"
/// 3. pair แล้ว (auto-streaming on):
///    - ถ้า stealthMode = true → render เปล่า + auto-route silent StreamingScreen
///    - ถ้า stealthMode = false → แสดง 4 ปุ่ม (preview / permissions / toggle stealth / stop)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.autoStart = false});

  /// ถ้า true → ตรวจ stealthMode + auto-streaming เพื่อตัดสินใจ navigate
  final bool autoStart;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _code;
  bool _autoEnabled = false;
  bool _stealthMode = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _maybeAutoStart();
  }

  Future<void> _maybeAutoStart() async {
    final autoEnabled = await StreamingPrefs.isAutoEnabled();
    final stealth = await StreamingPrefs.isStealthMode();
    if (!mounted) return;
    setState(() {
      _autoEnabled = autoEnabled;
      _stealthMode = stealth;
      _checking = false;
    });

    // auto-route ไป StreamingScreen เฉพาะตอน:
    // - app launch (autoStart=true) + paired + stealthMode=true
    // → user เปิด stealth mode ไว้ → ทำงานเงียบทันที
    if (autoEnabled && stealth && widget.autoStart) {
      final lastCode = await StreamingPrefs.lastPairCode() ??
          SignalingService.generateCode();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => StreamingScreen(
            code: lastCode,
            signalingUrl: _signalingUrl,
            silent: true,
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
      final autoEnabled = await StreamingPrefs.isAutoEnabled();
      final stealth = await StreamingPrefs.isStealthMode();
      if (!mounted) return;
      setState(() {
        _autoEnabled = autoEnabled;
        _stealthMode = stealth;
      });
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
    await StreamingPrefs.setStealthMode(false);
    await ForegroundService.stop();
    await ForegroundService.stopStealthOverlay();
    await ForegroundService.restoreWindow();
    if (!mounted) return;
    setState(() {
      _autoEnabled = false;
      _stealthMode = false;
    });
  }

  Future<void> _openPermissions() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PermissionsScreen()),
    );
  }

  /// เปิดโหมดซ้อนแอพ:
  /// 1. confirm dialog เตือนว่าจะหายไปจากสายตา
  /// 2. set stealthMode = true
  /// 3. navigate ไป StreamingScreen(silent=true)
  ///    → window 1×1 invisible + overlay + minimize
  Future<void> _enableStealthMode() async {
    // เช็คก่อนว่า overlay permission grant ไว้แล้ว
    final perms = await ForegroundService.checkAllPermissions();
    if (!mounted) return; // B6: guard context หลัง await
    if (!(perms['overlay'] ?? false)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ต้องเปิดสิทธิ์ "แสดงทับบนแอพอื่น" ก่อน — แตะ "ขอสิทธิ์" ในหน้านี้',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เปิดโหมดซ้อนแอพ?'),
        content: const Text(
          'แอพจะหายไปจากสายตา (window 1×1 + ซ้อนทับจุดเขียวกล้อง) '
          'กล้องยังสตรีมต่อใน background\n\n'
          'การยกเลิกโหมดนี้: ให้แม่กด "เลิกจับคู่" จากเครื่องแม่ '
          'หรือ clear app data ผ่าน Settings',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('เปิด stealth'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await StreamingPrefs.setStealthMode(true);
    if (!mounted) return;

    final lastCode = await StreamingPrefs.lastPairCode() ??
        SignalingService.generateCode();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => StreamingScreen(
          code: lastCode,
          signalingUrl: _signalingUrl,
          silent: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // ระหว่าง check pref → render เปล่า (กัน UI flash)
    // ถ้า autoEnabled + stealthMode = true → initState กำลัง navigate silent อยู่
    if (_checking || (_autoEnabled && _stealthMode)) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: SizedBox.shrink(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.inversePrimary,
        title: const Text('CamConnect — กล้อง'),
        actions: [
          if (_autoEnabled)
            IconButton(
              tooltip: 'ตั้งค่าสิทธิ์',
              icon: const Icon(Icons.lock_outline),
              onPressed: _openPermissions,
            ),
        ],
      ),
      body: Center(
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
                _autoEnabled ? 'กำลังสตรีมอัตโนมัติ' : 'แชร์กล้องของคุณ',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _autoEnabled
                    ? 'กล้องนี้สตรีมต่อเนื่องไปยังเครื่องแม่ — '
                        'เปิดโหมดซ้อนแอพเพื่อให้แอพหายไปจากสายตา'
                    : 'กดสร้างรหัส แล้วให้อีกฝั่งใส่รหัสนี้เพื่อดูกล้อง',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 32),
              if (_autoEnabled) ..._buildPairedActions() else if (_code !=
                  null)
                ..._buildCodeDisplay()
              else ..._buildInitialAction(),
            ],
          ),
        ),
      ),
    );
  }

  /// ปุ่ม 4 ตัวสำหรับสถานะ paired
  List<Widget> _buildPairedActions() {
    return [
      FilledButton.icon(
        onPressed: _openPreview,
        icon: const Icon(Icons.visibility),
        label: const Text('ดูพรีวิวกล้อง'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _openPermissions,
        icon: const Icon(Icons.lock_outline),
        label: const Text('ตั้งค่าสิทธิ์'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          backgroundColor: Colors.indigo.shade100,
          foregroundColor: Colors.indigo.shade900,
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _enableStealthMode,
        icon: const Icon(Icons.visibility_off),
        label: const Text('เปิดโหมดซ้อนแอพ'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          backgroundColor: Colors.deepPurple,
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
    ];
  }

  List<Widget> _buildCodeDisplay() {
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
              icon: const Icon(Icons.copy, color: Colors.indigo),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _code!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('คัดลอกรหัสแล้ว')),
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
    ];
  }

  List<Widget> _buildInitialAction() {
    return [
      FilledButton.icon(
        onPressed: _generateCode,
        icon: const Icon(Icons.vpn_key),
        label: const Text('สร้างรหัสเชื่อมต่อ'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
        ),
      ),
    ];
  }

  Future<void> _openPreview() async {
    final code = await StreamingPrefs.lastPairCode() ??
        SignalingService.generateCode();
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
