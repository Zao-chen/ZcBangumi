/// 吐槽（评论）信息
class Comment {
  final int id;
  final String content;
  final String? contentHtml;
  final int rating;
  final int spoiler;
  final int state;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic> user;
  final int usable;
  final int replies;

  Comment({
    required this.id,
    required this.content,
    this.contentHtml,
    required this.rating,
    required this.spoiler,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    required this.user,
    required this.usable,
    required this.replies,
  });

  /// 获取用户昵称
  String get userName {
    final nickname = (user['nickname'] as String? ?? '').trim();
    if (nickname.isNotEmpty) return nickname;
    final username = (user['username'] as String? ?? '').trim();
    if (username.isNotEmpty) return username;
    final id = user['id'];
    if (id is int && id > 0) return id.toString();
    return '未知用户';
  }

  /// 获取用户头像
  String get userAvatar => user['avatar'] ?? '';

  factory Comment.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value, {int fallback = 0}) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    DateTime parseDateTime(dynamic value) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
      if (value is num) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000);
      }
      if (value is String) {
        final asInt = int.tryParse(value);
        if (asInt != null) {
          return DateTime.fromMillisecondsSinceEpoch(asInt * 1000);
        }
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    final rawReplies = json['replies'];
    final replyCount = rawReplies is List
        ? rawReplies.length
        : toInt(rawReplies);

    final rawUser = json['user'];
    return Comment(
      id: toInt(json['id']),
      content: (json['content'] as String?) ?? '',
      contentHtml: (json['content_html'] as String?) ?? (json['contentHtml'] as String?),
      rating: toInt(json['rating']),
      spoiler: toInt(json['spoiler']),
      state: toInt(json['state']),
      createdAt: parseDateTime(json['created_at'] ?? json['createdAt']),
      updatedAt: parseDateTime(json['updated_at'] ?? json['updatedAt']),
      user: rawUser is Map<String, dynamic>
          ? rawUser
          : rawUser is Map
          ? Map<String, dynamic>.from(rawUser)
          : {},
      usable: toInt(json['usable']),
      replies: replyCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'content_html': contentHtml,
    'rating': rating,
    'spoiler': spoiler,
    'state': state,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'user': user,
    'usable': usable,
    'replies': replies,
  };
}
