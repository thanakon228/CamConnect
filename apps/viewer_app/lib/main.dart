import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/home_screen.dart';
import 'src/live_view_screen.dart';
import 'src/pairing_storage.dart';

const _signalingUrl = String.fromEnvironment(
  'SIGNALING_URL',
  defaultValue: 'http://192.168.1.33:4001',
);

void main() {
  runApp(const ProviderScope(child: ViewerApp()));
}

class ViewerApp extends StatelessWidget {
  const ViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CamConnect — ดูกล้อง',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const _Bootstrap(),
    );
  }
}

/// เช็ค paired_device_id ก่อนตัดสินใจว่าจะแสดง HomeScreen หรือ LiveViewScreen เลย
class _Bootstrap extends StatelessWidget {
  const _Bootstrap();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: PairingStorage.getDeviceId(),
      builder: (context, snapshot) {
        if (!snapshot.hasData && snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final deviceId = snapshot.data;
        if (deviceId != null && deviceId.isNotEmpty) {
          // จับคู่แล้ว → เข้า LiveView ตรงๆ
          return LiveViewScreen(
            deviceId: deviceId,
            signalingUrl: _signalingUrl,
          );
        }
        // ยังไม่ได้ pair → ใส่รหัส
        return const HomeScreen();
      },
    );
  }
}
