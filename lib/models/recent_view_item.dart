import 'character.dart';
import 'person.dart';
import 'rakuen_topic.dart';
import 'subject.dart';

enum RecentViewKind { subject, topic, character, person }

class RecentViewItem {
  final RecentViewKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final DateTime viewedAt;
  final Map<String, dynamic> routeData;

  const RecentViewItem({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.imageUrl = '',
    required this.viewedAt,
    this.routeData = const {},
  });

  String get key => '${kind.name}:$id';

  String get kindLabel => switch (kind) {
    RecentViewKind.subject => '条目',
    RecentViewKind.topic => '帖子',
    RecentViewKind.character => '角色',
    RecentViewKind.person => '人物',
  };

  int? get numericId => int.tryParse(id);

  RakuenTopic? get topic {
    final raw = routeData['topic'];
    if (raw is! Map) return null;
    try {
      return RakuenTopic.fromCacheJson(
        raw.map((key, value) => MapEntry('$key', value)),
      );
    } catch (_) {
      return null;
    }
  }

  RecentViewItem copyWith({DateTime? viewedAt}) {
    return RecentViewItem(
      kind: kind,
      id: id,
      title: title,
      subtitle: subtitle,
      imageUrl: imageUrl,
      viewedAt: viewedAt ?? this.viewedAt,
      routeData: routeData,
    );
  }

  factory RecentViewItem.fromSubject(Subject subject, {DateTime? viewedAt}) {
    final details = <String>[
      if (subject.score > 0) '★ ${subject.score.toStringAsFixed(1)}',
      if (subject.rank > 0) '#${subject.rank}',
    ];
    return RecentViewItem(
      kind: RecentViewKind.subject,
      id: '${subject.id}',
      title: subject.displayName,
      subtitle: details.join(' · '),
      imageUrl: subject.images?.common ?? '',
      viewedAt: viewedAt ?? DateTime.now(),
    );
  }

  factory RecentViewItem.fromTopic(
    RakuenTopic topic, {
    String? displayTitle,
    DateTime? viewedAt,
  }) {
    final details = <String>[
      topic.displayTypeLabel,
      if (topic.sourceTitle?.trim().isNotEmpty == true)
        topic.sourceTitle!.trim(),
      if (topic.authorName?.trim().isNotEmpty == true) topic.authorName!.trim(),
    ];
    return RecentViewItem(
      kind: RecentViewKind.topic,
      id: '${topic.type}:${topic.id}',
      title: displayTitle?.trim().isNotEmpty == true
          ? displayTitle!.trim()
          : topic.title,
      subtitle: details.join(' · '),
      imageUrl: topic.avatarUrl,
      viewedAt: viewedAt ?? DateTime.now(),
      routeData: {'topic': topic.toJson()},
    );
  }

  factory RecentViewItem.fromCharacter(
    Character character, {
    DateTime? viewedAt,
  }) {
    return RecentViewItem(
      kind: RecentViewKind.character,
      id: '${character.id}',
      title: character.name,
      subtitle: character.type,
      imageUrl: character.images.isEmpty ? '' : character.images.first.medium,
      viewedAt: viewedAt ?? DateTime.now(),
    );
  }

  factory RecentViewItem.fromPerson(
    PersonSummary person, {
    DateTime? viewedAt,
  }) {
    final details = <String>[person.typeLabel, ...person.careerLabels.take(2)];
    return RecentViewItem(
      kind: RecentViewKind.person,
      id: '${person.id}',
      title: person.name,
      subtitle: details.join(' · '),
      imageUrl: person.images?.bestSmall ?? '',
      viewedAt: viewedAt ?? DateTime.now(),
    );
  }

  factory RecentViewItem.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind']?.toString() ?? '';
    final kind = RecentViewKind.values.where((item) => item.name == kindName);
    if (kind.isEmpty) {
      throw const FormatException('Unknown recent view kind');
    }
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) {
      throw const FormatException('Missing recent view id');
    }
    final rawRouteData = json['route_data'];
    return RecentViewItem(
      kind: kind.first,
      id: id,
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      viewedAt:
          DateTime.tryParse(json['viewed_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      routeData: rawRouteData is Map
          ? rawRouteData.map((key, value) => MapEntry('$key', value))
          : const {},
    );
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'image_url': imageUrl,
    'viewed_at': viewedAt.toIso8601String(),
    'route_data': routeData,
  };
}
