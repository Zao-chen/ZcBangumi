/// 吐槽（评论）信息
class Comment {
  final int id;
  final String content;
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
  String get userName => user['nickname'] ?? user['username'] ?? '未知用户';

  /// 获取用户头像
  String get userAvatar => user['avatar'] ?? '';

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'] as int,
      content: (json['content'] as String?) ?? '',
      rating: (json['rating'] as int?) ?? 0,
      spoiler: (json['spoiler'] as int?) ?? 0,
      state: (json['state'] as int?) ?? 0,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      user: json['user'] as Map<String, dynamic>? ?? {},
      usable: (json['usable'] as int?) ?? 0,
      replies: (json['replies'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
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
