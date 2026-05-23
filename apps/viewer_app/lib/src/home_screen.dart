import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'pairing_storage.dart';
import 'signaling_service.dart';

const _signalingUrl = String.fromEnvironment(
  'SIGNALING_URL',
  // production: Railway deployment (Singapore region)
  // override ตอน build ได้ด้วย --dart-define=SIGNALING_URL=http://192.168.x.x:4001 สำหรับ LAN test
  defaultValue: 'https://famirycare-production.up.railway.app',
);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _errorMsg;

  Future<void> _pairAndConnect() async {
    if (!_formKey.currentState!.validate()) return;
    if (_busy) return;
    final code = _codeController.text.trim().toUpperCase();

    setState(() {
      _busy = true;
      _errorMsg = null;
    });

    final svc = SignalingService(_signalingUrl);
    svc.connect();

    try {
      final deviceId = await svc.pairViewer(code);
      svc.dispose();

      await PairingStorage.setDeviceId(deviceId);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DashboardScreen(
            deviceId: deviceId,
            signalingUrl: _signalingUrl,
          ),
        ),
      );
    } catch (e) {
      svc.dispose();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMsg = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.inversePrimary,
        title: const Text('CamConnect — ดูกล้อง'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.visibility, size: 80, color: Colors.teal),
                const SizedBox(height: 24),
                const Text(
                  'ดูกล้องระยะไกล',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'ใส่รหัส 6 หลักจากอุปกรณ์กล้อง — ครั้งเดียวพอ',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 40),
                TextFormField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  enabled: !_busy,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                  ),
                  decoration: InputDecoration(
                    hintText: 'XXXXXX',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade300,
                      fontSize: 32,
                      letterSpacing: 6,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    counterText: '',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length != 6) {
                      return 'กรุณาใส่รหัส 6 หลัก';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _pairAndConnect(),
                ),
                if (_errorMsg != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMsg!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _pairAndConnect,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_circle),
                  label: Text(_busy ? 'กำลังจับคู่...' : 'เชื่อมต่อ'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
