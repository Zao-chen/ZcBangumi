import 'rakuen_topic_favorite.dart';

String bangumiIndexViewerCacheScope(String? username) {
  final normalized = username?.trim().toLowerCase() ?? '';
  return Uri.encodeComponent(normalized.isEmpty ? 'guest' : normalized);
}

String bangumiIndexDetailCacheKey(int indexId, String? viewerUsername) =>
    'bangumi_index_${indexId}_${bangumiIndexViewerCacheScope(viewerUsername)}';

String bangumiIndexRelatedCacheKey(
  int indexId,
  IndexRelatedCategory? category,
  int? subjectType,
  String? viewerUsername,
) =>
    'bangumi_index_related_${indexId}_${category?.value ?? -1}_${subjectType ?? -1}_${bangumiIndexViewerCacheScope(viewerUsername)}';

String bangumiEntityIndexesCacheKey(
  IndexRelatedCategory category,
  int contentId,
  String? viewerUsername,
) {
  final prefix = switch (category) {
    IndexRelatedCategory.subject => 'subject',
    IndexRelatedCategory.character => 'character',
    IndexRelatedCategory.person => 'person',
    _ => throw ArgumentError.value(category, 'category', '仅条目、角色和人物支持反向目录缓存'),
  };
  return '${prefix}_indexes_${contentId}_${bangumiIndexViewerCacheScope(viewerUsername)}';
}

String bangumiUserIndexesCacheKey({
  required String targetUsername,
  required String? viewerUsername,
  required bool collected,
}) {
  final target = Uri.encodeComponent(targetUsername.trim().toLowerCase());
  final kind = collected ? 'collected' : 'created';
  return 'user_${kind}_indexes_${target}_${bangumiIndexViewerCacheScope(viewerUsername)}';
}

int _asInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = '$value'.trim().toLowerCase();
  return normalized == 'true' || normalized == '1';
}

DateTime _fromUnix(dynamic value) {
  if (value is String && value.contains('-')) {
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(_asInt(value) * 1000);
}

DateTime? _optionalTimestamp(dynamic value) {
  if (value == null) return null;
  final parsed = _fromUnix(value);
  return parsed.millisecondsSinceEpoch > 0 ? parsed : null;
}

enum BangumiIndexType {
  user(0, '用户目录'),
  public(1, '公共目录'),
  award(2, '精选目录'),
  unknown(-1, '目录');

  const BangumiIndexType(this.value, this.label);

  final int value;
  final String label;

  static BangumiIndexType fromValue(dynamic value) {
    final number = _asInt(value, -1);
    return values.firstWhere(
      (item) => item.value == number,
      orElse: () => unknown,
    );
  }
}

enum IndexRelatedCategory {
  subject(0, '条目'),
  character(1, '角色'),
  person(2, '人物'),
  episode(3, '单集'),
  blog(4, '日志'),
  groupTopic(5, '小组话题'),
  subjectTopic(6, '条目讨论');

  const IndexRelatedCategory(this.value, this.label);

  final int value;
  final String label;

  static IndexRelatedCategory? fromValue(dynamic value) {
    final number = _asInt(value, -1);
    for (final category in values) {
      if (category.value == number) return category;
    }
    return null;
  }
}

class BangumiIndexStats {
  final Map<int, int> subjects;
  final int character;
  final int person;
  final int episode;
  final int blog;
  final int groupTopic;
  final int subjectTopic;

  const BangumiIndexStats({
    this.subjects = const {},
    this.character = 0,
    this.person = 0,
    this.episode = 0,
    this.blog = 0,
    this.groupTopic = 0,
    this.subjectTopic = 0,
  });

  int countFor(IndexRelatedCategory category) => switch (category) {
    IndexRelatedCategory.subject => subjects.values.fold(0, (a, b) => a + b),
    IndexRelatedCategory.character => character,
    IndexRelatedCategory.person => person,
    IndexRelatedCategory.episode => episode,
    IndexRelatedCategory.blog => blog,
    IndexRelatedCategory.groupTopic => groupTopic,
    IndexRelatedCategory.subjectTopic => subjectTopic,
  };

  factory BangumiIndexStats.fromJson(dynamic json) {
    final map = _asMap(json) ?? const <String, dynamic>{};
    final subject = _asMap(map['subject']) ?? const <String, dynamic>{};
    const subjectKeys = {
      1: 'book',
      2: 'anime',
      3: 'music',
      4: 'game',
      6: 'real',
    };
    return BangumiIndexStats(
      subjects: {
        for (final entry in subjectKeys.entries)
          if (_asInt(subject[entry.value]) > 0)
            entry.key: _asInt(subject[entry.value]),
      },
      character: _asInt(map['character']),
      person: _asInt(map['person']),
      episode: _asInt(map['episode']),
      blog: _asInt(map['blog']),
      groupTopic: _asInt(map['groupTopic'] ?? map['group_topic']),
      subjectTopic: _asInt(map['subjectTopic'] ?? map['subject_topic']),
    );
  }

  Map<String, dynamic> toJson() => {
    'subject': {
      'book': subjects[1] ?? 0,
      'anime': subjects[2] ?? 0,
      'music': subjects[3] ?? 0,
      'game': subjects[4] ?? 0,
      'real': subjects[6] ?? 0,
    },
    'character': character,
    'person': person,
    'episode': episode,
    'blog': blog,
    'groupTopic': groupTopic,
    'subjectTopic': subjectTopic,
  };
}

class BangumiIndexSummary {
  final int id;
  final int uid;
  final Map<String, dynamic>? user;
  final BangumiIndexType type;
  final String title;
  final bool isPrivate;
  final int total;
  final BangumiIndexStats stats;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BangumiIndexSummary({
    required this.id,
    required this.uid,
    required this.user,
    required this.type,
    required this.title,
    required this.isPrivate,
    required this.total,
    required this.stats,
    required this.createdAt,
    required this.updatedAt,
  });

  String get userName {
    final nickname = '${user?['nickname'] ?? ''}'.trim();
    if (nickname.isNotEmpty) return nickname;
    final username = '${user?['username'] ?? ''}'.trim();
    return username.isNotEmpty ? username : '用户 #$uid';
  }

  String get username => '${user?['username'] ?? ''}'.trim();

  String get userAvatar {
    final avatar = _asMap(user?['avatar']);
    return '${avatar?['medium'] ?? avatar?['small'] ?? avatar?['large'] ?? ''}';
  }

  bool get isSystemSyncIndex => title.trim() == rakuenFavoriteIndexTitle;

  factory BangumiIndexSummary.fromJson(Map<String, dynamic> json) {
    return BangumiIndexSummary(
      id: _asInt(json['id']),
      uid: _asInt(json['uid']),
      user: _asMap(json['user']),
      type: BangumiIndexType.fromValue(json['type']),
      title: '${json['title'] ?? ''}',
      isPrivate: _asBool(json['private']),
      total: _asInt(json['total']),
      stats: BangumiIndexStats.fromJson(json['stats']),
      createdAt: _fromUnix(json['createdAt'] ?? json['created_at']),
      updatedAt: _fromUnix(json['updatedAt'] ?? json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'uid': uid,
    'user': user,
    'type': type.value,
    'title': title,
    'private': isPrivate,
    'total': total,
    'stats': stats.toJson(),
    'createdAt': createdAt.millisecondsSinceEpoch ~/ 1000,
    'updatedAt': updatedAt.millisecondsSinceEpoch ~/ 1000,
  };
}

class BangumiIndex extends BangumiIndexSummary {
  final String description;
  final int replies;
  final int collects;
  final int award;
  final DateTime? collectedAt;

  const BangumiIndex({
    required super.id,
    required super.uid,
    required super.user,
    required super.type,
    required super.title,
    required super.isPrivate,
    required super.total,
    required super.stats,
    required super.createdAt,
    required super.updatedAt,
    required this.description,
    required this.replies,
    required this.collects,
    required this.award,
    required this.collectedAt,
  });

  bool get isCollected => collectedAt != null;

  @override
  bool get isSystemSyncIndex =>
      super.isSystemSyncIndex || description.contains(rakuenFavoriteBlockStart);

  factory BangumiIndex.fromJson(Map<String, dynamic> json) {
    final summary = BangumiIndexSummary.fromJson(json);
    final collected = json['collectedAt'] ?? json['collected_at'];
    return BangumiIndex(
      id: summary.id,
      uid: summary.uid,
      user: summary.user,
      type: summary.type,
      title: summary.title,
      isPrivate: summary.isPrivate,
      total: summary.total,
      stats: summary.stats,
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
      description: '${json['desc'] ?? json['description'] ?? ''}',
      replies: _asInt(json['replies']),
      collects: _asInt(json['collects']),
      award: _asInt(json['award']),
      collectedAt: _optionalTimestamp(collected),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'desc': description,
    'replies': replies,
    'collects': collects,
    'award': award,
    'collectedAt': collectedAt == null
        ? null
        : collectedAt!.millisecondsSinceEpoch ~/ 1000,
  };
}

class BangumiIndexRelated {
  final int id;
  final IndexRelatedCategory category;
  final int rid;
  final int type;
  final int sid;
  final int order;
  final String comment;
  final String award;
  final DateTime createdAt;
  final Map<String, dynamic>? payload;

  const BangumiIndexRelated({
    required this.id,
    required this.category,
    required this.rid,
    required this.type,
    required this.sid,
    required this.order,
    required this.comment,
    required this.award,
    required this.createdAt,
    required this.payload,
  });

  factory BangumiIndexRelated.fromJson(Map<String, dynamic> json) {
    final category =
        IndexRelatedCategory.fromValue(json['cat']) ??
        IndexRelatedCategory.subject;
    final payloadKey = switch (category) {
      IndexRelatedCategory.subject => 'subject',
      IndexRelatedCategory.character => 'character',
      IndexRelatedCategory.person => 'person',
      IndexRelatedCategory.episode => 'episode',
      IndexRelatedCategory.blog => 'blog',
      IndexRelatedCategory.groupTopic => 'groupTopic',
      IndexRelatedCategory.subjectTopic => 'subjectTopic',
    };
    return BangumiIndexRelated(
      id: _asInt(json['id']),
      category: category,
      rid: _asInt(json['rid']),
      type: _asInt(json['type']),
      sid: _asInt(json['sid']),
      order: _asInt(json['order']),
      comment: '${json['comment'] ?? ''}',
      award: '${json['award'] ?? ''}',
      createdAt: _fromUnix(json['createdAt'] ?? json['created_at']),
      payload: _asMap(json[payloadKey]),
    );
  }

  String get title {
    final data = payload ?? const <String, dynamic>{};
    if (category == IndexRelatedCategory.episode) {
      final nameCn =
          '${data['name_cn'] ?? data['nameCN'] ?? data['nameCn'] ?? ''}'.trim();
      final name = '${data['name'] ?? ''}'.trim();
      final sort = data['ep'] ?? data['sort'];
      final sortText = sort is num && sort == sort.roundToDouble()
          ? '${sort.toInt()}'
          : '$sort';
      final prefix = sort == null ? '单集' : 'EP$sortText';
      final text = nameCn.isNotEmpty ? nameCn : name;
      return text.isEmpty ? prefix : '$prefix · $text';
    }
    return '${data['name_cn'] ?? data['nameCN'] ?? data['nameCn'] ?? data['title'] ?? data['name'] ?? '${category.label} #$sid'}'
        .trim();
  }

  String get subtitle {
    final data = payload ?? const <String, dynamic>{};
    switch (category) {
      case IndexRelatedCategory.episode:
        final subject = _asMap(data['subject']);
        return '${subject?['name_cn'] ?? subject?['nameCN'] ?? subject?['nameCn'] ?? subject?['name'] ?? ''}'
            .trim();
      case IndexRelatedCategory.blog:
        return _userName(_asMap(data['user']));
      case IndexRelatedCategory.groupTopic:
        final group = _asMap(data['group']);
        return '${group?['title'] ?? group?['name'] ?? ''}'.trim();
      case IndexRelatedCategory.subjectTopic:
        final subject = _asMap(data['subject']);
        return '${subject?['name_cn'] ?? subject?['nameCN'] ?? subject?['nameCn'] ?? subject?['name'] ?? ''}'
            .trim();
      default:
        return '';
    }
  }

  String get imageUrl {
    final data = payload ?? const <String, dynamic>{};
    Map<String, dynamic>? images = _asMap(data['images']);
    if (category == IndexRelatedCategory.episode ||
        category == IndexRelatedCategory.subjectTopic) {
      images = _asMap(_asMap(data['subject'])?['images']);
    } else if (category == IndexRelatedCategory.groupTopic) {
      images = _asMap(_asMap(data['group'])?['icon']);
    }
    if (category == IndexRelatedCategory.blog) {
      images = _asMap(_asMap(data['user'])?['avatar']);
      final icon = '${data['icon'] ?? ''}'.trim();
      if (images == null && icon.isNotEmpty) return icon;
    }
    return '${images?['medium'] ?? images?['small'] ?? images?['large'] ?? images?['grid'] ?? ''}';
  }

  String get webUrl => switch (category) {
    IndexRelatedCategory.subject => 'https://bgm.tv/subject/$sid',
    IndexRelatedCategory.character => 'https://bgm.tv/character/$sid',
    IndexRelatedCategory.person => 'https://bgm.tv/person/$sid',
    IndexRelatedCategory.episode => 'https://bgm.tv/ep/$sid',
    IndexRelatedCategory.blog => 'https://bgm.tv/blog/$sid',
    IndexRelatedCategory.groupTopic => 'https://bgm.tv/group/topic/$sid',
    IndexRelatedCategory.subjectTopic => 'https://bgm.tv/subject/topic/$sid',
  };

  Map<String, dynamic> toJson() {
    final payloadKey = switch (category) {
      IndexRelatedCategory.subject => 'subject',
      IndexRelatedCategory.character => 'character',
      IndexRelatedCategory.person => 'person',
      IndexRelatedCategory.episode => 'episode',
      IndexRelatedCategory.blog => 'blog',
      IndexRelatedCategory.groupTopic => 'groupTopic',
      IndexRelatedCategory.subjectTopic => 'subjectTopic',
    };
    return {
      'id': id,
      'cat': category.value,
      'rid': rid,
      'type': type,
      'sid': sid,
      'order': order,
      'comment': comment,
      'award': award,
      'createdAt': createdAt.millisecondsSinceEpoch ~/ 1000,
      payloadKey: payload,
    };
  }

  static String _userName(Map<String, dynamic>? user) {
    return '${user?['nickname'] ?? user?['username'] ?? ''}'.trim();
  }
}

Map<int, int> buildBangumiIndexOrderUpdates(List<BangumiIndexRelated> items) {
  final updates = <int, int>{};
  for (var i = 0; i < items.length; i++) {
    final order = (i + 1) * 10;
    if (items[i].order != order) updates[items[i].id] = order;
  }
  return updates;
}

class BangumiIndexContentRef {
  final IndexRelatedCategory category;
  final int id;
  final String sourceUrl;

  const BangumiIndexContentRef({
    required this.category,
    required this.id,
    required this.sourceUrl,
  });

  static BangumiIndexContentRef? parse(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;
    final normalized = raw.contains('://')
        ? raw
        : raw.startsWith('bgm.tv/') ||
              raw.startsWith('bangumi.tv/') ||
              raw.startsWith('chii.in/')
        ? 'https://$raw'
        : 'https://bgm.tv/${raw.startsWith('/') ? raw.substring(1) : raw}';
    final uri = Uri.tryParse(normalized);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (!(host == 'bgm.tv' ||
        host.endsWith('.bgm.tv') ||
        host == 'bangumi.tv' ||
        host.endsWith('.bangumi.tv') ||
        host == 'chii.in' ||
        host.endsWith('.chii.in'))) {
      return null;
    }
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .map((segment) => segment.toLowerCase())
        .toList();
    if (segments.length < 2) return null;

    IndexRelatedCategory? category;
    String? rawId;
    switch (segments.first) {
      case 'subject':
        if (segments.length >= 3 && segments[1] == 'topic') {
          category = IndexRelatedCategory.subjectTopic;
          rawId = segments[2];
        } else {
          category = IndexRelatedCategory.subject;
          rawId = segments[1];
        }
        break;
      case 'character':
        category = IndexRelatedCategory.character;
        rawId = segments[1];
        break;
      case 'person':
        category = IndexRelatedCategory.person;
        rawId = segments[1];
        break;
      case 'ep':
        category = IndexRelatedCategory.episode;
        rawId = segments[1];
        break;
      case 'blog':
        category = IndexRelatedCategory.blog;
        rawId = segments[1];
        break;
      case 'group':
        if (segments.length >= 3 && segments[1] == 'topic') {
          category = IndexRelatedCategory.groupTopic;
          rawId = segments[2];
        }
        break;
      case 'rakuen':
        if (segments.length >= 4 && segments[1] == 'topic') {
          category = switch (segments[2]) {
            'group' => IndexRelatedCategory.groupTopic,
            'subject' => IndexRelatedCategory.subjectTopic,
            'blog' => IndexRelatedCategory.blog,
            _ => null,
          };
          rawId = segments[3];
        }
        break;
    }
    final id = int.tryParse(rawId ?? '');
    if (category == null || id == null || id <= 0) return null;
    return BangumiIndexContentRef(category: category, id: id, sourceUrl: raw);
  }
}

class BangumiIndexApiException implements Exception {
  final int? statusCode;
  final String message;

  const BangumiIndexApiException(this.message, {this.statusCode});

  bool get requiresLogin => statusCode == 401;
  bool get forbidden => statusCode == 403;
  bool get notFound => statusCode == 404;
  bool get conflict => statusCode == 409;
  bool get rateLimited => statusCode == 429;

  @override
  String toString() => message;
}
