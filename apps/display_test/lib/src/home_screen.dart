import 'package:flutter/material.dart';
import 'notification_tab.dart';
import 'overlay_tab.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Display Test'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.notifications), text: 'Notification'),
              Tab(icon: Icon(Icons.layers), text: 'Overlay'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            NotificationTab(),
            OverlayTab(),
          ],
        ),
      ),
    );
  }
}
