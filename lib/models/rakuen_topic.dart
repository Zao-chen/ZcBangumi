class RakuenTopic {
  final String id;
  final String type;
  final String title;
  final String topicUrl;
  final String avatarUrl;
  final int replyCount;
  final String timeText;
  final String? sourceTitle;
  final String? sourceUrl;
  final String? authorName;

  const RakuenTopic({
    required this.id,
    required this.type,
    required this.title,
    required this.topicUrl,
    required this.avatarUrl,
    required this.replyCount,
    required this.timeText,
    this.sourceTitle,
    this.sourceUrl,
    this.authorName,
  });

  String get displayTypeLabel {
    switch (type) {
      case 'group':
        return '小组';
      case 'subject':
        return '条目';
      case 'ep':
        return '章节';
      case 'crt':
        return '角色';
      case 'prsn':
      case 'mono':
        return '人物';
      case 'blog':
        return '日志';
      default:
        return '超展开';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'topicUrl': topicUrl,
    'avatarUrl': avatarUrl,
    'replyCount': replyCount,
    'timeText': timeText,
    'sourceTitle': sourceTitle,
    'sourceUrl': sourceUrl,
    'authorName': authorName,
  };

  factory RakuenTopic.fromCacheJson(Map<String, dynamic> json) {
    return RakuenTopic(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      topicUrl: json['topicUrl'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      replyCount: json['replyCount'] as int? ?? 0,
      timeText: json['timeText'] as String? ?? '',
      sourceTitle: json['sourceTitle'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      authorName: json['authorName'] as String?,
    );
  }
}
