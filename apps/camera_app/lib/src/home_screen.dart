import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'streaming_screen.dart';
import 'signaling_service.dart';

const _signalingUrl = String.fromEnvironment(
  'SIGNALING_URL',
  defaultValue: 'http://192.168.1.33:4001',
);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _code;

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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.inversePrimary,
        title: const Text('CamConnect — กล้อง'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam, size: 80, color: Colors.indigo),
              const SizedBox(height: 24),
              const Text(
                'แชร์กล้องของคุณ',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'กดสร้างรหัส แล้วให้อีกฝั่งใส่รหัสนี้เพื่อดูกล้อง',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 40),
              if (_code != null) ...[
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
}
