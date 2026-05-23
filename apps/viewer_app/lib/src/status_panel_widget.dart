import 'package:flutter/material.dart';
import 'device_status.dart';

/// แสดง 4 mini-card: 🔋 แบต, 📶 สัญญาณ, 📱 แอพปัจจุบัน, 🌙 จอ
/// ใช้ใน DashboardScreen — รับ DeviceStatus หรือ null (กำลังโหลด)
class StatusPanel extends StatelessWidget {
  const StatusPanel({super.key, this.status});

  final DeviceStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 1.8,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _BatteryCard(status: s),
        _SignalCard(status: s),
        _AppCard(status: s),
        _ScreenCard(status: s),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.sub,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withOpacity(0.55),
                    ),
                  ),
                ),
              ],
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (sub != null)
              Text(
                sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black.withOpacity(0.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BatteryCard extends StatelessWidget {
  const _BatteryCard({this.status});
  final DeviceStatus? status;

  @override
  Widget build(BuildContext context) {
    final level = status?.batteryLevel ?? -1;
    final charging = status?.batteryCharging ?? false;
    final (icon, color) = _iconForLevel(level, charging);
    return _StatusCard(
      icon: icon,
      color: color,
      label: 'แบตเตอรี่',
      value: level < 0 ? '—' : '$level%',
      sub: charging ? 'กำลังชาร์จ' : null,
    );
  }

  (IconData, Color) _iconForLevel(int level, bool charging) {
    if (charging) return (Icons.battery_charging_full, Colors.green);
    if (level < 0) return (Icons.battery_unknown, Colors.grey);
    if (level <= 15) return (Icons.battery_alert, Colors.red);
    if (level <= 50) return (Icons.battery_3_bar, Colors.orange);
    return (Icons.battery_full, Colors.green);
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({this.status});
  final DeviceStatus? status;

  @override
  Widget build(BuildContext context) {
    final type = status?.networkType ?? 'none';
    final level = status?.signalLevel ?? -1;
    final (icon, label, color) = _iconForNetwork(type, level);
    return _StatusCard(
      icon: icon,
      color: color,
      label: 'เครือข่าย',
      value: label,
      sub: level < 0 ? null : 'ขีดสัญญาณ $level/4',
    );
  }

  (IconData, String, Color) _iconForNetwork(String type, int level) {
    switch (type) {
      case 'wifi':
        if (level < 0) return (Icons.wifi, 'WiFi', Colors.blueAccent);
        if (level >= 3) return (Icons.wifi, 'WiFi (ดี)', Colors.green);
        if (level >= 2) return (Icons.wifi_2_bar, 'WiFi (กลาง)', Colors.orange);
        return (Icons.wifi_1_bar, 'WiFi (แย่)', Colors.red);
      case 'cellular':
        if (level < 0) return (Icons.signal_cellular_alt, 'มือถือ', Colors.blueAccent);
        if (level >= 3) return (Icons.signal_cellular_alt, 'มือถือ (ดี)', Colors.green);
        if (level >= 2) {
          return (Icons.signal_cellular_alt_2_bar, 'มือถือ (กลาง)', Colors.orange);
        }
        return (Icons.signal_cellular_alt_1_bar, 'มือถือ (แย่)', Colors.red);
      default:
        return (Icons.signal_cellular_nodata, 'ไม่มีสัญญาณ', Colors.grey);
    }
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({this.status});
  final DeviceStatus? status;

  @override
  Widget build(BuildContext context) {
    final app = status?.foregroundApp;
    return _StatusCard(
      icon: Icons.apps,
      color: Colors.deepPurple,
      label: 'แอพปัจจุบัน',
      value: app ?? '—',
      sub: app == null ? 'อนุญาต Usage Access' : null,
    );
  }
}

class _ScreenCard extends StatelessWidget {
  const _ScreenCard({this.status});
  final DeviceStatus? status;

  @override
  Widget build(BuildContext context) {
    final on = status?.screenOn ?? false;
    return _StatusCard(
      icon: on ? Icons.phone_iphone : Icons.nightlight_round,
      color: on ? Colors.amber : Colors.indigo,
      label: 'หน้าจอ',
      value: on ? 'เปิดอยู่' : 'ดับ',
    );
  }
}
