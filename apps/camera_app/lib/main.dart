import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/fcm_service.dart';
import 'src/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // เปิด Firebase + register FCM background handler
  // ถ้า google-services.json ไม่อยู่ → Firebase.initializeApp จะ throw — รอ user setup
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    FcmService.setupForegroundHandler();
  } catch (e) {
    debugPrint('[main] Firebase init failed (FCM disabled): $e');
  }

  runApp(const ProviderScope(child: CameraApp()));
}

class CameraApp extends StatelessWidget {
  const CameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CamConnect — กล้อง',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(autoStart: true),
    );
  }
}
