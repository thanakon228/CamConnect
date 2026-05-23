import 'package:flutter/material.dart';
import 'notif_event.dart';

/// แสดง notification ของเครื่องลูกแบบ list — Dashboard preview (max 5)
/// กดที่ list เพื่อดูทั้งหมดในหน้าใหม่
class NotifMirrorWidget extends StatelessWidget {
  const NotifMirrorWidget({
    super.key,
    required this.events,
    this.previewLimit = 5,
    this.onSeeAll,
  });

  final List<NotifEvent> events;
  final int previewLimit;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: const [
              Icon(Icons.notifications_off_outlined, color: Colors.grey),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'ยังไม่มีแจ้งเตือนจากเครื่องลูก '
                  '— เปิดสิทธิ์ "Notification access" บนเครื่องลูกก่อน',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // แสดงล่าสุดบนสุด
    final sorted = [...events]
      ..sort((a, b) => b.postTime.compareTo(a.postTime));
    final preview = sorted.take(previewLimit).toList();

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in preview) _NotifTile(event: e),
          if (sorted.length > previewLimit && onSeeAll != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextButton.icon(
                onPressed: onSeeAll,
                icon: const Icon(Icons.expand_more),
                label: Text('ดูทั้งหมด (${sorted.length})'),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  const _NotifTile({required this.event});
  final NotifEvent event;

  String _timeAgo() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = Duration(milliseconds: now - event.postTime);
    if (diff < const Duration(seconds: 60)) return 'เมื่อสักครู่';
    if (diff < const Duration(minutes: 60)) return '${diff.inMinutes} น.';
    if (diff < const Duration(hours: 24)) return '${diff.inHours} ชม.';
    return '${diff.inDays} วัน';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: Colors.indigo.shade50,
        child: Text(
          event.appLabel.isNotEmpty ? event.appLabel.characters.first : '?',
          style: const TextStyle(
              color: Colors.indigo, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(
        event.title.isNotEmpty ? event.title : event.appLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: event.text.isEmpty
          ? Text(event.appLabel,
              style: const TextStyle(color: Colors.black54, fontSize: 12))
          : Text(
              event.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
      trailing: Text(
        _timeAgo(),
        style: const TextStyle(fontSize: 11, color: Colors.black45),
      ),
    );
  }
}

/// หน้าใหม่ — แสดง notif ทั้งหมด (สำหรับกด "ดูทั้งหมด")
class NotifMirrorFullScreen extends StatelessWidget {
  const NotifMirrorFullScreen({super.key, required this.events});

  final List<NotifEvent> events;

  @override
  Widget build(BuildContext context) {
    final sorted = [...events]
      ..sort((a, b) => b.postTime.compareTo(a.postTime));
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('แจ้งเตือนของเครื่องลูก'),
      ),
      body: sorted.isEmpty
          ? const Center(child: Text('ยังไม่มีแจ้งเตือน'))
          : ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const Divider(height: 0),
              itemBuilder: (_, i) => _NotifTile(event: sorted[i]),
            ),
    );
  }
}
