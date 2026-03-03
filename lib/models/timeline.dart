/// 时间线条目模型（从 bgm.tv HTML 解析或 /p1/timeline JSON API）
class TimelineItem {
  final String username;
  final String nickname;
  final String avatarUrl;
  final String actionText; // 看过, 在看, 想看, 搁置了, 完成了 ...
  final String? targetText; // 动作目标文本 (ep.34 讨伐要请 / Subject Name)
  final int? subjectId;
  final String? subjectName;
  final String? subjectNameCn;
  final String? subjectCoverUrl;
  final String? subjectInfo; // 话数 / 日期 / 制作信息
  final double? score;
  final String? rank;
  final String timeText; // "37秒前", "2小时前" ...
  final int? createdAt; // unix timestamp（用于游标分页）

  TimelineItem({
    required this.username,
    required this.nickname,
    required this.avatarUrl,
    required this.actionText,
    this.targetText,
    this.subjectId,
    this.subjectName,
    this.subjectNameCn,
    this.subjectCoverUrl,
    this.subjectInfo,
    this.score,
    this.rank,
    required this.timeText,
    this.createdAt,
  });

  /// 显示用的条目名 (优先中文名)
  String get displaySubjectName {
    if (subjectNameCn != null && subjectNameCn!.isNotEmpty) {
      return subjectNameCn!;
    }
    return subjectName ?? targetText ?? '';
  }

  /// 序列化为 JSON（用于本地缓存）
  Map<String, dynamic> toJson() => {
        'username': username,
        'nickname': nickname,
        'avatarUrl': avatarUrl,
        'actionText': actionText,
        'targetText': targetText,
        'subjectId': subjectId,
        'subjectName': subjectName,
        'subjectNameCn': subjectNameCn,
        'subjectCoverUrl': subjectCoverUrl,
        'subjectInfo': subjectInfo,
        'score': score,
        'rank': rank,
        'timeText': timeText,
        'createdAt': createdAt,
      };

  /// 从缓存 JSON 反序列化
  factory TimelineItem.fromCacheJson(Map<String, dynamic> json) {
    return TimelineItem(
      username: json['username'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      actionText: json['actionText'] as String? ?? '',
      targetText: json['targetText'] as String?,
      subjectId: json['subjectId'] as int?,
      subjectName: json['subjectName'] as String?,
      subjectNameCn: json['subjectNameCn'] as String?,
      subjectCoverUrl: json['subjectCoverUrl'] as String?,
      subjectInfo: json['subjectInfo'] as String?,
      score: (json['score'] as num?)?.toDouble(),
      rank: json['rank'] as String?,
      timeText: json['timeText'] as String? ?? '',
      createdAt: json['createdAt'] as int?,
    );
  }

  // ==================== /p1/timeline JSON API 解析 ====================

  /// 从 /p1/timeline JSON 数组解析
  /// [fallbackUser] 当 API 返回的 user 为 null 时使用的回退用户信息
  static List<TimelineItem> fromApiJsonList(
    List<dynamic> list, {
    Map<String, dynamic>? fallbackUser,
  }) {
    final items = <TimelineItem>[];
    for (final e in list) {
      try {
        items.add(TimelineItem._fromApiMap(
          e as Map<String, dynamic>,
          fallbackUser: fallbackUser,
        ));
      } catch (_) {
        // 跳过解析失败的条目
      }
    }
    return items;
  }

  /// 从单个 API JSON 对象创建
  static TimelineItem _fromApiMap(
    Map<String, dynamic> json, {
    Map<String, dynamic>? fallbackUser,
  }) {
    // ---- 用户信息 ----
    final user = json['user'] as Map<String, dynamic>? ?? fallbackUser;
    final username = user?['username'] as String? ?? '';
    final nickname = user?['nickname'] as String? ?? '';
    final avatar = user?['avatar'] as Map<String, dynamic>?;
    var avatarUrl =
        avatar?['medium'] as String? ?? avatar?['small'] as String? ?? '';
    if (avatarUrl.startsWith('//')) avatarUrl = 'https:$avatarUrl';

    // ---- 基本字段 ----
    final cat = json['cat'] as int? ?? 0;
    final type = json['type'] as int? ?? 0;
    final memo = json['memo'] as Map<String, dynamic>? ?? {};
    final ts = json['createdAt'] as int? ?? 0;

    String actionText = '';
    String? targetText;
    int? subjectId;
    String? subjectName;
    String? subjectNameCn;
    String? subjectCoverUrl;
    String? subjectInfo;
    double? score;

    switch (cat) {
      // ---- 收藏 (cat=3) ----
      case 3:
        final subjects = memo['subject'] as List<dynamic>?;
        if (subjects != null && subjects.isNotEmpty) {
          final first = subjects[0] as Map<String, dynamic>;
          final subject = first['subject'] as Map<String, dynamic>?;
          final subjectType = subject?['type'] as int? ?? 2;
          actionText = _collectionLabel(type, subjectType);

          _fillSubject(subject, (id, name, cn, cover, info) {
            subjectId = id;
            subjectName = name;
            subjectNameCn = cn;
            subjectCoverUrl = cover;
            subjectInfo = info;
          });

          final rate = first['rate'];
          if (rate is num && rate > 0) score = rate.toDouble();

          final comment = first['comment'] as String?;
          if (comment != null && comment.isNotEmpty) targetText = comment;

          if (subjects.length > 1) {
            actionText += ' 等${subjects.length}部作品';
          }
        } else {
          actionText = _collectionLabel(type, 2);
        }
        break;

      // ---- 进度 (cat=4) ----
      case 4:
        actionText = '看了';
        final progress = memo['progress'] as Map<String, dynamic>?;
        if (progress != null) {
          final single = progress['single'] as Map<String, dynamic>?;
          final batch = progress['batch'] as Map<String, dynamic>?;

          if (single != null) {
            final episode = single['episode'] as Map<String, dynamic>?;
            final subject = single['subject'] as Map<String, dynamic>?;
            if (episode != null) {
              final sort = episode['sort'];
              final epName = episode['name'] as String? ?? '';
              targetText = 'ep.$sort $epName'.trim();
            }
            _fillSubject(subject, (id, name, cn, cover, info) {
              subjectId = id;
              subjectName = name;
              subjectNameCn = cn;
              subjectCoverUrl = cover;
              subjectInfo = info;
            });
          } else if (batch != null) {
            final epsUpdate = batch['epsUpdate'];
            final epsTotal = batch['epsTotal'] as String?;
            final subject = batch['subject'] as Map<String, dynamic>?;
            targetText = '看到第 $epsUpdate 话';
            if (epsTotal != null && epsTotal.isNotEmpty) {
              subjectInfo = '全 $epsTotal 话';
            }
            _fillSubject(subject, (id, name, cn, cover, info) {
              subjectId = id;
              subjectName = name;
              subjectNameCn = cn;
              subjectCoverUrl = cover;
              if (subjectInfo == null && info != null) subjectInfo = info;
            });
          }
        }
        break;

      // ---- 吐槽 / 日常 (cat=1) ----
      case 1:
        actionText = '说';
        final status = memo['status'] as Map<String, dynamic>?;
        if (status != null) {
          targetText = status['tsukkomi'] as String?;
        }
        break;

      // ---- 状态变更 (cat=5) ----
      case 5:
        final status = memo['status'] as Map<String, dynamic>?;
        if (status != null) {
          if (status.containsKey('tsukkomi')) {
            actionText = '说';
            targetText = status['tsukkomi'] as String?;
          } else if (status.containsKey('nickname')) {
            final nick = status['nickname'] as Map<String, dynamic>;
            actionText = '更改了昵称';
            targetText = '${nick['before']} → ${nick['after']}';
          } else if (status.containsKey('sign')) {
            actionText = '更新了签名';
            targetText = status['sign'] as String?;
          } else {
            actionText = '更新了状态';
          }
        } else {
          actionText = '更新了状态';
        }
        break;

      // ---- 日志 (cat=6) ----
      case 6:
        actionText = '发表了日志';
        final blog = memo['blog'] as Map<String, dynamic>?;
        if (blog != null) {
          targetText = blog['title'] as String?;
        }
        break;

      // ---- 目录 (cat=7) ----
      case 7:
        actionText = '创建了目录';
        final index = memo['index'] as Map<String, dynamic>?;
        if (index != null) {
          targetText = index['title'] as String?;
        }
        break;

      // ---- 人物/角色 (cat=8) ----
      case 8:
        final mono = memo['mono'] as Map<String, dynamic>?;
        if (mono != null) {
          final characters = mono['characters'] as List<dynamic>? ?? [];
          final persons = mono['persons'] as List<dynamic>? ?? [];
          if (characters.isNotEmpty && persons.isEmpty) {
            actionText = '收藏了角色';
          } else if (persons.isNotEmpty && characters.isEmpty) {
            actionText = '收藏了人物';
          } else {
            actionText = '收藏了';
          }
          final names = <String>[];
          for (final c in characters) {
            final n = (c as Map<String, dynamic>)['name'] as String? ?? '';
            if (n.isNotEmpty) names.add(n);
          }
          for (final p in persons) {
            final n = (p as Map<String, dynamic>)['name'] as String? ?? '';
            if (n.isNotEmpty) names.add(n);
          }
          if (names.isNotEmpty) targetText = names.take(3).join('、');
        } else {
          actionText = '收藏了';
        }
        break;

      // ---- Wiki (cat=2) ----
      case 2:
        actionText = '编辑了';
        final wiki = memo['wiki'] as Map<String, dynamic>?;
        if (wiki != null) {
          final subject = wiki['subject'] as Map<String, dynamic>?;
          _fillSubject(subject, (id, name, cn, cover, info) {
            subjectId = id;
            subjectName = name;
            subjectNameCn = cn;
            subjectCoverUrl = cover;
            subjectInfo = info;
          });
        }
        break;

      // ---- 好友 (cat=9) 等 ----
      default:
        // daily 类型中可能包含好友相关动态
        final daily = memo['daily'] as Map<String, dynamic>?;
        if (daily != null) {
          final users = daily['users'] as List<dynamic>?;
          if (users != null && users.isNotEmpty) {
            actionText = '成为了好友';
            final friendNames = users
                .map((u) =>
                    (u as Map<String, dynamic>)['nickname'] as String? ?? '')
                .where((n) => n.isNotEmpty)
                .take(3);
            if (friendNames.isNotEmpty) {
              targetText = friendNames.join('、');
            }
          } else {
            actionText = '动态';
          }
        } else {
          actionText = '动态';
        }
    }

    return TimelineItem(
      username: username,
      nickname: nickname,
      avatarUrl: avatarUrl,
      actionText: actionText,
      targetText: targetText,
      subjectId: subjectId,
      subjectName: subjectName,
      subjectNameCn: subjectNameCn,
      subjectCoverUrl: subjectCoverUrl,
      subjectInfo: subjectInfo,
      score: score,
      rank: null,
      timeText: _formatRelativeTime(ts),
      createdAt: ts,
    );
  }

  // ---- 辅助方法 ----

  /// 收藏动作文本
  static String _collectionLabel(int collectionType, int subjectType) {
    const book = 1;
    const game = 4;
    switch (collectionType) {
      case 1:
        return subjectType == book
            ? '想读'
            : subjectType == game
                ? '想玩'
                : '想看';
      case 2:
        return subjectType == book
            ? '读过'
            : subjectType == game
                ? '玩过'
                : '看过';
      case 3:
        return subjectType == book
            ? '在读'
            : subjectType == game
                ? '在玩'
                : '在看';
      case 4:
        return '搁置了';
      case 5:
        return '抛弃了';
      default:
        return '收藏了';
    }
  }

  /// 提取 SlimSubject 信息
  static void _fillSubject(
    Map<String, dynamic>? subject,
    void Function(
            int? id, String? name, String? cn, String? cover, String? info)
        callback,
  ) {
    if (subject == null) return;
    final images = subject['images'] as Map<String, dynamic>?;
    var coverUrl =
        images?['common'] as String? ?? images?['small'] as String?;
    if (coverUrl != null && coverUrl.startsWith('//')) {
      coverUrl = 'https:$coverUrl';
    }
    if (coverUrl != null && coverUrl.isEmpty) coverUrl = null;
    callback(
      subject['id'] as int?,
      subject['name'] as String?,
      subject['nameCN'] as String?,
      coverUrl,
      subject['info'] as String?,
    );
  }

  /// 将 unix 时间戳转为相对时间文本
  static String _formatRelativeTime(int timestamp) {
    if (timestamp <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.isNegative) return '刚刚';
    if (diff.inSeconds < 60) return '${diff.inSeconds}秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
