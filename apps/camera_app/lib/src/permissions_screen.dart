import 'package:flutter/material.dart';
import 'device_status.dart';
import 'foreground_service.dart';
import 'notif_event.dart';

/// หน้าตั้งค่าสิทธิ์ — แสดงสถานะ permissions ทั้งหมดที่ camera_app ต้องใช้
/// + ปุ่ม "ขอสิทธิ์" สำหรับแต่ละตัว (deep link ไป Settings ตามแต่ละชนิด)
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  Map<String, bool> _status = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// เมื่อ user กลับมาจาก Settings → refresh สถานะ
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await ForegroundService.checkAllPermissions();
    if (!mounted) return;
    setState(() {
      _status = s;
      _loading = false;
    });
  }

  Future<void> _grantCameraMic() async {
    await ForegroundService.requestRuntimePermissions();
    // wait a moment for dialog to close
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _refresh();
  }

  Future<void> _grantOverlay() async {
    await ForegroundService.openOverlaySettings();
  }

  Future<void> _grantUsageStats() async {
    await DeviceStatus.openUsageStatsSettings();
  }

  Future<void> _grantNotifListener() async {
    await NotifDrainer.openSettings();
  }

  Future<void> _grantBattery() async {
    await ForegroundService.openBatterySettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final items = <_PermItem>[
      const _PermItem(
        key: 'cameraMic',
        icon: Icons.videocam,
        title: 'กล้อง + ไมโครโฟน',
        subtitle: 'จำเป็นสำหรับสตรีมภาพและเสียง',
        required: true,
      ),
      const _PermItem(
        key: 'notifications',
        icon: Icons.notifications,
        title: 'การแจ้งเตือน',
        subtitle: 'แสดง notification ตอนสตรีมอยู่ (FGS)',
        required: true,
      ),
      const _PermItem(
        key: 'batteryExempt',
        icon: Icons.battery_charging_full,
        title: 'ยกเว้นการประหยัดแบต',
        subtitle: 'ป้องกันระบบฆ่าแอปอัตโนมัติ',
        required: true,
      ),
      const _PermItem(
        key: 'overlay',
        icon: Icons.layers,
        title: 'แสดงทับบนแอพอื่น',
        subtitle: 'จำเป็นสำหรับโหมดซ้อนแอพ (overlay 1×1)',
        required: false,
      ),
      const _PermItem(
        key: 'usageStats',
        icon: Icons.apps,
        title: 'เข้าถึงข้อมูลการใช้งาน',
        subtitle: 'รายงานแอพที่ใช้บ่อยให้เครื่องแม่',
        required: false,
      ),
      const _PermItem(
        key: 'notifListener',
        icon: Icons.notifications_active,
        title: 'อ่านการแจ้งเตือน',
        subtitle: 'ส่งต่อ notification ให้เครื่องแม่ดู',
        required: false,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.inversePrimary,
        title: const Text('ตั้งค่าสิทธิ์'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.info_outline, color: Colors.indigo),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'สิทธิ์ที่จำเป็นต้องเปิดทั้งหมดเพื่อให้แอพทำงานเต็มฟีเจอร์ '
                          '— ตัวที่ขึ้นป้าย "ต้องการ" ขาดไม่ได้',
                          style: TextStyle(fontSize: 13, color: Colors.indigo),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (final item in items) _buildTile(item),
              ],
            ),
    );
  }

  Widget _buildTile(_PermItem item) {
    final granted = _isGranted(item.key);
    final onGrant = _grantHandler(item.key);

    return Card(
      child: ListTile(
        leading: Icon(
          item.icon,
          color: granted ? Colors.green : Colors.orange,
          size: 32,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (item.required)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'ต้องการ',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(item.subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ),
        trailing: granted
            ? const Icon(Icons.check_circle, color: Colors.green)
            : FilledButton.tonal(
                onPressed: onGrant,
                child: const Text('ขอสิทธิ์'),
              ),
        isThreeLine: true,
      ),
    );
  }

  bool _isGranted(String key) {
    switch (key) {
      case 'cameraMic':
        return (_status['camera'] ?? false) && (_status['microphone'] ?? false);
      default:
        return _status[key] ?? false;
    }
  }

  VoidCallback? _grantHandler(String key) {
    switch (key) {
      case 'cameraMic':
      case 'notifications':
        return _grantCameraMic;
      case 'batteryExempt':
        return _grantBattery;
      case 'overlay':
        return _grantOverlay;
      case 'usageStats':
        return _grantUsageStats;
      case 'notifListener':
        return _grantNotifListener;
      default:
        return null;
    }
  }
}

class _PermItem {
  const _PermItem({
    required this.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.required,
  });

  final String key;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool required;
}
