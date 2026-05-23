import 'package:flutter/material.dart';
import 'usage_stat.dart';

/// แสดง bar chart แบบ horizontal — top N apps + เวลาที่ใช้
/// + ปุ่ม refresh (สั่งกล้อง re-query ผ่าน server)
class UsageStatsWidget extends StatelessWidget {
  const UsageStatsWidget({
    super.key,
    required this.stats,
    this.previewLimit = 5,
    this.onRefresh,
    this.onSeeAll,
    this.reportedAt = 0,
  });

  final List<UsageStat> stats;
  final int previewLimit;
  final VoidCallback? onRefresh;
  final VoidCallback? onSeeAll;
  final int reportedAt;

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.bar_chart, color: Colors.grey),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'ยังไม่มีข้อมูลการใช้แอพ — ต้องเปิดสิทธิ์ Usage Access '
                  'บนเครื่องลูกก่อน',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
              if (onRefresh != null)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: onRefresh,
                ),
            ],
          ),
        ),
      );
    }

    final sorted = [...stats]
      ..sort((a, b) => b.totalTimeMs.compareTo(a.totalTimeMs));
    final preview = sorted.take(previewLimit).toList();
    final maxTime = preview.first.totalTimeMs;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding:
                const EdgeInsets.only(left: 16, right: 8, top: 12, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'ใช้งานใน 24 ชม. ล่าสุด · ${preview.length} แอพ',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black54),
                  ),
                ),
                if (onRefresh != null)
                  IconButton(
                    tooltip: 'รีเฟรช',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: onRefresh,
                  ),
              ],
            ),
          ),
          for (final s in preview) _UsageBar(stat: s, maxMs: maxTime),
          if (sorted.length > previewLimit && onSeeAll != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextButton.icon(
                onPressed: onSeeAll,
                icon: const Icon(Icons.expand_more),
                label: Text('ดูทั้งหมด (${sorted.length})'),
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.stat, required this.maxMs});
  final UsageStat stat;
  final int maxMs;

  @override
  Widget build(BuildContext context) {
    final ratio = maxMs > 0 ? stat.totalTimeMs / maxMs : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  stat.appLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                stat.formattedTime,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.indigo.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.indigo.shade50,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo.shade400),
            ),
          ),
        ],
      ),
    );
  }
}

/// หน้าใหม่ — list ครบทั้งหมด
class UsageStatsFullScreen extends StatelessWidget {
  const UsageStatsFullScreen({super.key, required this.stats});
  final List<UsageStat> stats;

  @override
  Widget build(BuildContext context) {
    final sorted = [...stats]
      ..sort((a, b) => b.totalTimeMs.compareTo(a.totalTimeMs));
    final maxTime = sorted.isEmpty ? 1 : sorted.first.totalTimeMs;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('การใช้แอพของเครื่องลูก'),
      ),
      body: sorted.isEmpty
          ? const Center(child: Text('ยังไม่มีข้อมูล'))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: sorted.length,
              itemBuilder: (_, i) => _UsageBar(stat: sorted[i], maxMs: maxTime),
            ),
    );
  }
}
