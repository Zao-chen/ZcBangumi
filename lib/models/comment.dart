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
  final List<Comment> replyItems;

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
    this.replyItems = const [],
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
  String get userAvatar {
    final avatar = user['avatar'];
    if (avatar is String) return avatar;
    if (avatar is Map) {
      return (avatar['medium'] as String?) ??
          (avatar['small'] as String?) ??
          (avatar['large'] as String?) ??
          '';
    }
    return '';
  }

  factory Comment.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value, {int fallback = 0}) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    DateTime? parseDateTime(dynamic value) {
      DateTime fromEpoch(num timestamp) {
        final value = timestamp.toInt();
        final absoluteValue = value.abs();
        if (absoluteValue >= 100000000000000) {
          return DateTime.fromMicrosecondsSinceEpoch(value);
        }
        if (absoluteValue >= 100000000000) {
          return DateTime.fromMillisecondsSinceEpoch(value);
        }
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }

      if (value is num) {
        return fromEpoch(value);
      }
      if (value is String) {
        final normalized = value.trim();
        if (normalized.isEmpty) return null;
        final asNumber = num.tryParse(normalized);
        if (asNumber != null) {
          return fromEpoch(asNumber);
        }
        return DateTime.tryParse(normalized);
      }
      return null;
    }

    final rawReplies = json['replies'];
    final replyItems = rawReplies is List
        ? rawReplies
              .whereType<Map>()
              .map(
                (reply) => Comment.fromJson(Map<String, dynamic>.from(reply)),
              )
              .toList(growable: false)
        : const <Comment>[];
    final replyCount = rawReplies is List
        ? replyItems.length
        : toInt(rawReplies);

    final rawUser = json['user'];
    final parsedCreatedAt = parseDateTime(
      json['created_at'] ?? json['createdAt'] ?? json['created'],
    );
    final parsedUpdatedAt = parseDateTime(
      json['updated_at'] ?? json['updatedAt'] ?? json['updated'],
    );
    final fallbackDate = DateTime.fromMillisecondsSinceEpoch(0);
    return Comment(
      id: toInt(json['id']),
      content: (json['content'] as String?) ?? '',
      contentHtml:
          (json['content_html'] as String?) ?? (json['contentHtml'] as String?),
      rating: toInt(json['rating']),
      spoiler: toInt(json['spoiler']),
      state: toInt(json['state']),
      createdAt: parsedCreatedAt ?? parsedUpdatedAt ?? fallbackDate,
      updatedAt: parsedUpdatedAt ?? parsedCreatedAt ?? fallbackDate,
      user: rawUser is Map<String, dynamic>
          ? rawUser
          : rawUser is Map
          ? Map<String, dynamic>.from(rawUser)
          : {},
      usable: toInt(json['usable']),
      replies: replyCount,
      replyItems: replyItems,
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
    'replies': replyItems.isNotEmpty
        ? replyItems.map((reply) => reply.toJson()).toList(growable: false)
        : replies,
  };
}
