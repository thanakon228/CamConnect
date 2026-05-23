import 'package:flutter/material.dart';
import 'platform.dart';

class NotificationTab extends StatefulWidget {
  const NotificationTab({super.key});
  @override
  State<NotificationTab> createState() => _NotificationTabState();
}

class _NotificationTabState extends State<NotificationTab> {
  final _title = TextEditingController(text: 'ทดสอบ');
  final _body = TextEditingController(text: 'ข้อความตัวอย่าง');

  String _channel = 'high';
  String _style = 'standard';
  String _category = 'none';
  int _actions = 0;
  bool _sound = true;
  bool _vibrate = true;
  bool _autoCancel = true;

  @override
  void initState() {
    super.initState();
    Platform.ensureNotificationPermission();
  }

  Future<void> _send() async {
    await Platform.sendNotification(
      title: _title.text,
      body: _body.text,
      channel: _channel,
      style: _style,
      category: _category,
      actions: _actions,
      sound: _sound,
      vibrate: _vibrate,
      autoCancel: _autoCancel,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่ง notification แล้ว'), duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
        const SizedBox(height: 8),
        TextField(
          controller: _body,
          decoration: const InputDecoration(labelText: 'Body'),
          maxLines: 3,
        ),
        const SizedBox(height: 16),

        _section('Channel importance'),
        _radioRow(_channel, ['default', 'high', 'max'], (v) => setState(() => _channel = v)),

        _section('Style'),
        _radioRow(
          _style,
          ['standard', 'bigtext', 'bigpicture', 'inbox'],
          (v) => setState(() => _style = v),
        ),

        _section('Category'),
        _radioRow(
          _category,
          ['none', 'message', 'call', 'alarm', 'event'],
          (v) => setState(() => _category = v),
        ),

        _section('Actions'),
        _radioRow(
          _actions.toString(),
          ['0', '1', '2'],
          (v) => setState(() => _actions = int.parse(v)),
        ),

        const SizedBox(height: 8),
        SwitchListTile(
          value: _sound,
          onChanged: (v) => setState(() => _sound = v),
          title: const Text('Sound'),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: _vibrate,
          onChanged: (v) => setState(() => _vibrate = v),
          title: const Text('Vibrate'),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: _autoCancel,
          onChanged: (v) => setState(() => _autoCancel = v),
          title: const Text('Auto cancel'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _send,
          icon: const Icon(Icons.send),
          label: const Text('Send notification'),
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
        ),
      ],
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  Widget _radioRow(String selected, List<String> options, ValueChanged<String> onTap) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options
          .map((o) => ChoiceChip(
                label: Text(o),
                selected: selected == o,
                onSelected: (_) => onTap(o),
              ))
          .toList(),
    );
  }
}
