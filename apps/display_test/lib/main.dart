import 'package:flutter/material.dart';
import 'src/home_screen.dart';

void main() {
  runApp(const DisplayTestApp());
}

class DisplayTestApp extends StatelessWidget {
  const DisplayTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Display Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
