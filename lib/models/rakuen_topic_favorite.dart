import 'dart:convert';

import 'rakuen_topic.dart';

const String rakuenFavoriteIndexTitle = 'ZCBangumi 帖子收藏同步';
const String rakuenFavoriteBlockStart = '[zc_bangumi_topic_favorites_v1]';
const String rakuenFavoriteBlockEnd = '[/zc_bangumi_topic_favorites_v1]';

class RakuenFavoriteTopic {
  final String key;
  final String type;
  final String title;
  final String topicUrl;
  final String avatarUrl;
  final int replyCount;
  final String timeText;
  final String? sourceTitle;
  final String? sourceUrl;
  final String? authorName;
  final DateTime favoritedAt;
  final DateTime updatedAt;

  const RakuenFavoriteTopic({
    required this.key,
    required this.type,
    required this.title,
    required this.topicUrl,
    required this.avatarUrl,
    required this.replyCount,
    required this.timeText,
    this.sourceTitle,
    this.sourceUrl,
    this.authorName,
    required this.favoritedAt,
    required this.updatedAt,
  });

  factory RakuenFavoriteTopic.fromTopic(RakuenTopic topic, {DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    return RakuenFavoriteTopic(
      key: keyForTopic(topic),
      type: topic.type,
      title: topic.title,
      topicUrl: topic.topicUrl,
      avatarUrl: topic.avatarUrl,
      replyCount: topic.replyCount,
      timeText: topic.timeText,
      sourceTitle: topic.sourceTitle,
      sourceUrl: topic.sourceUrl,
      authorName: topic.authorName,
      favoritedAt: timestamp,
      updatedAt: timestamp,
    );
  }

  RakuenTopic get topic => RakuenTopic(
    id: key,
    type: type,
    title: title,
    topicUrl: topicUrl,
    avatarUrl: avatarUrl,
    replyCount: replyCount,
    timeText: timeText,
    sourceTitle: sourceTitle,
    sourceUrl: sourceUrl,
    authorName: authorName,
  );

  RakuenFavoriteTopic refreshedFromTopic(RakuenTopic topic, {DateTime? now}) {
    return RakuenFavoriteTopic(
      key: key,
      type: topic.type,
      title: topic.title,
      topicUrl: topic.topicUrl,
      avatarUrl: topic.avatarUrl,
      replyCount: topic.replyCount,
      timeText: topic.timeText,
      sourceTitle: topic.sourceTitle,
      sourceUrl: topic.sourceUrl,
      authorName: topic.authorName,
      favoritedAt: favoritedAt,
      updatedAt: now ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'type': type,
    'title': title,
    'topicUrl': topicUrl,
    'avatarUrl': avatarUrl,
    'replyCount': replyCount,
    'timeText': timeText,
    'sourceTitle': sourceTitle,
    'sourceUrl': sourceUrl,
    'authorName': authorName,
    'favoritedAt': favoritedAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory RakuenFavoriteTopic.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return RakuenFavoriteTopic(
      key: json['key'] as String? ?? '',
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      topicUrl: json['topicUrl'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      replyCount: json['replyCount'] as int? ?? 0,
      timeText: json['timeText'] as String? ?? '',
      sourceTitle: json['sourceTitle'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      authorName: json['authorName'] as String?,
      favoritedAt:
          DateTime.tryParse(json['favoritedAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }

  static String keyForTopic(RakuenTopic topic) {
    final uri = Uri.tryParse(topic.topicUrl);
    final path = uri?.path ?? '';

    final rakuenMatch = RegExp(
      r'^/rakuen/topic/([^/]+)/(\d+)$',
    ).firstMatch(path);
    if (rakuenMatch != null) {
      return '${rakuenMatch.group(1)}_${rakuenMatch.group(2)}';
    }

    final groupMatch = RegExp(r'^/group/topic/(\d+)$').firstMatch(path);
    if (groupMatch != null) {
      return 'group_${groupMatch.group(1)}';
    }

    final subjectMatch = RegExp(r'^/subject/topic/(\d+)$').firstMatch(path);
    if (subjectMatch != null) {
      return 'subject_${subjectMatch.group(1)}';
    }

    final episodeMatch = RegExp(r'^/ep/(\d+)$').firstMatch(path);
    if (episodeMatch != null) {
      return 'ep_${episodeMatch.group(1)}';
    }

    return topic.id.isNotEmpty ? topic.id : topic.topicUrl;
  }
}

class RakuenFavoriteCloudDocument {
  final int version;
  final DateTime updatedAt;
  final List<RakuenFavoriteTopic> items;

  const RakuenFavoriteCloudDocument({
    required this.version,
    required this.updatedAt,
    required this.items,
  });

  factory RakuenFavoriteCloudDocument.empty({DateTime? now}) {
    return RakuenFavoriteCloudDocument(
      version: 1,
      updatedAt: now ?? DateTime.now(),
      items: const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'updatedAt': updatedAt.toIso8601String(),
    'items': items.map((item) => item.toJson()).toList(),
  };

  factory RakuenFavoriteCloudDocument.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return RakuenFavoriteCloudDocument(
      version: json['version'] as int? ?? 1,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => RakuenFavoriteTopic.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .where(
                  (item) => item.key.isNotEmpty && item.topicUrl.isNotEmpty,
                )
                .toList()
          : const [],
    );
  }

  static RakuenFavoriteCloudDocument? tryParseFromDescription(String desc) {
    final startIndex = desc.indexOf(rakuenFavoriteBlockStart);
    final endIndex = desc.indexOf(rakuenFavoriteBlockEnd);
    if (startIndex < 0 || endIndex <= startIndex) return null;

    final payloadStart = startIndex + rakuenFavoriteBlockStart.length;
    final payload = desc.substring(payloadStart, endIndex).trim();
    if (payload.isEmpty) return RakuenFavoriteCloudDocument.empty();

    try {
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final json = jsonDecode(decoded);
      if (json is! Map) return null;
      return RakuenFavoriteCloudDocument.fromJson(
        Map<String, dynamic>.from(json),
      );
    } catch (_) {
      return null;
    }
  }

  static String buildDescription({
    required String existingDescription,
    required RakuenFavoriteCloudDocument document,
  }) {
    final encoded = base64Url
        .encode(utf8.encode(jsonEncode(document.toJson())))
        .replaceAll('=', '');
    final block =
        '$rakuenFavoriteBlockStart\n$encoded\n$rakuenFavoriteBlockEnd';
    final startIndex = existingDescription.indexOf(rakuenFavoriteBlockStart);
    final endIndex = existingDescription.indexOf(rakuenFavoriteBlockEnd);
    if (startIndex >= 0 && endIndex > startIndex) {
      final afterEnd = endIndex + rakuenFavoriteBlockEnd.length;
      return existingDescription.replaceRange(startIndex, afterEnd, block);
    }

    final prefix = existingDescription.trim().isEmpty
        ? '此目录由 ZCBangumi 用于同步帖子收藏，请不要手动编辑下面的数据块。'
        : existingDescription.trimRight();
    return '$prefix\n\n$block';
  }
}

class RakuenFavoriteIndex {
  final int id;
  final String title;
  final String desc;
  final bool private;

  const RakuenFavoriteIndex({
    required this.id,
    required this.title,
    required this.desc,
    required this.private,
  });

  factory RakuenFavoriteIndex.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    return RakuenFavoriteIndex(
      id: rawId is int ? rawId : int.tryParse('$rawId') ?? 0,
      title: json['title'] as String? ?? '',
      desc:
          json['desc'] as String? ??
          json['description'] as String? ??
          json['summary'] as String? ??
          '',
      private:
          json['private'] as bool? ??
          json['isPrivate'] as bool? ??
          json['ban'] == 2,
    );
  }
}
