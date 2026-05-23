import 'package:flutter/material.dart';
import 'device_status.dart';
import 'home_screen.dart';
import 'live_view_screen.dart';
import 'pairing_storage.dart';
import 'settings_screen.dart';
import 'signaling_service.dart';
import 'status_panel_widget.dart';

/// หน้าหลักของ viewer หลัง pair แล้ว — แสดง status เครื่องลูก + ปุ่ม action
/// แทนที่ LiveViewScreen เป็น default route — user ต้องกด "ดูกล้อง" ถึงจะเข้าสตรีม
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.deviceId,
    required this.signalingUrl,
  });

  final String deviceId;
  final String signalingUrl;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final SignalingService _signaling;
  DeviceStatus? _status;
  String? _statusError;
  bool _initialLoading = true;

  @override
  void initState() {
    super.initState();
    _signaling = SignalingService(widget.signalingUrl);

    // subscribe — server จะ push status-updated มาเรื่อยๆ
    _signaling.onStatusUpdated = (deviceId, status) {
      if (!mounted || deviceId != widget.deviceId) return;
      setState(() {
        _status = status;
        _statusError = null;
        _initialLoading = false;
      });
    };

    _signaling.connect();
    _signaling.subscribeStatus(widget.deviceId);
    _fetchInitialStatus();
  }

  Future<void> _fetchInitialStatus() async {
    try {
      final s = await _signaling.getStatus(widget.deviceId);
      if (!mounted) return;
      setState(() {
        _status = s;
        _statusError = null;
        _initialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusError = e.toString();
        _initialLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() => _statusError = null);
    await _fetchInitialStatus();
  }

  @override
  void dispose() {
    _signaling.unsubscribeStatus(widget.deviceId);
    _signaling.dispose();
    super.dispose();
  }

  Future<void> _openLiveView() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveViewScreen(
          deviceId: widget.deviceId,
          signalingUrl: widget.signalingUrl,
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          deviceId: widget.deviceId,
          signalingUrl: widget.signalingUrl,
        ),
      ),
    );
  }

  Future<void> _wakeCamera() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('กำลังส่งสัญญาณปลุกกล้อง...'),
        duration: Duration(seconds: 2),
      ),
    );
    try {
      await _signaling.wakeCamera(widget.deviceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ส่งสัญญาณปลุกแล้ว'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ปลุกไม่สำเร็จ: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _confirmUnpair() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เลิกจับคู่กับกล้องนี้?'),
        content: const Text('หลังจากนี้ต้องใส่รหัสใหม่อีกครั้ง'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('เลิกจับคู่'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await PairingStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _status;
    final isOnline = s?.isOnline ?? false;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.inversePrimary,
        title: const Text('แดชบอร์ดกล้อง'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeaderCard(
              deviceId: widget.deviceId,
              isOnline: isOnline,
              status: s,
            ),
            const SizedBox(height: 16),
            _SectionTitle(icon: Icons.monitor_heart, text: 'สถานะเครื่อง'),
            const SizedBox(height: 8),
            if (_initialLoading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_statusError != null && s == null)
              _ErrorBox(message: _statusError!, onRetry: _refresh)
            else
              StatusPanel(status: s),
            const SizedBox(height: 24),
            _SectionTitle(icon: Icons.touch_app, text: 'ควบคุม'),
            const SizedBox(height: 8),
            _ActionGrid(
              onViewCamera: _openLiveView,
              onSettings: _openSettings,
              onWake: _wakeCamera,
              onUnpair: _confirmUnpair,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.deviceId,
    required this.isOnline,
    this.status,
  });

  final String deviceId;
  final bool isOnline;
  final DeviceStatus? status;

  String get _shortId =>
      deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId;

  String get _lastSeen {
    final s = status;
    if (s == null || s.lastUpdate == 0) return 'ยังไม่ได้รับ status';
    final age = s.age;
    if (age < const Duration(seconds: 60)) return 'อัพเดทเมื่อสักครู่';
    if (age < const Duration(minutes: 5)) return '${age.inMinutes} นาทีที่แล้ว';
    if (age < const Duration(hours: 1)) return '${age.inMinutes} นาทีที่แล้ว';
    return '${age.inHours} ชั่วโมงที่แล้ว';
  }

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? Colors.green : Colors.grey;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.videocam, color: color, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'กล้อง $_shortId',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isOnline ? 'ออนไลน์ · $_lastSeen' : 'ออฟไลน์ · $_lastSeen',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.teal),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(color: Colors.orange),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('ลองใหม่'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.onViewCamera,
    required this.onSettings,
    required this.onWake,
    required this.onUnpair,
  });

  final VoidCallback onViewCamera;
  final VoidCallback onSettings;
  final VoidCallback onWake;
  final VoidCallback onUnpair;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.4,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _ActionButton(
          icon: Icons.videocam,
          label: 'ดูกล้อง',
          color: Colors.teal,
          onTap: onViewCamera,
        ),
        _ActionButton(
          icon: Icons.settings,
          label: 'ตั้งค่า',
          color: Colors.indigo,
          onTap: onSettings,
        ),
        _ActionButton(
          icon: Icons.notifications_active,
          label: 'ปลุกกล้อง',
          color: Colors.orange,
          onTap: onWake,
        ),
        _ActionButton(
          icon: Icons.link_off,
          label: 'เลิกจับคู่',
          color: Colors.red,
          onTap: onUnpair,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: color.shade(700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on Color {
  /// helper สำหรับ MaterialColor → ใช้กับ Colors.* ที่เป็น MaterialColor
  /// ถ้าไม่ใช่ MaterialColor คืน this เอง
  Color shade(int weight) {
    final c = this;
    if (c is MaterialColor) return c[weight] ?? c;
    return c;
  }
}
