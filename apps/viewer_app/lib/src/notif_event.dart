/// Notification ที่ camera ดักจับได้ — viewer แสดงให้แม่ดู
class NotifEvent {
  const NotifEvent({
    required this.packageName,
    required this.appLabel,
    required this.title,
    required this.text,
    required this.postTime,
    required this.receivedAt,
  });

  final String packageName;
  final String appLabel;
  final String title;
  final String text;

  /// epoch ms ที่เครื่องลูกได้รับ
  final int postTime;

  /// epoch ms ที่ server ได้รับ
  final int receivedAt;

  factory NotifEvent.fromJson(Map<String, dynamic> j) => NotifEvent(
        packageName: j['packageName'] as String? ?? '',
        appLabel: j['appLabel'] as String? ?? '',
        title: j['title'] as String? ?? '',
        text: j['text'] as String? ?? '',
        postTime: (j['postTime'] as int?) ?? 0,
        receivedAt: (j['receivedAt'] as int?) ?? 0,
      );
}
