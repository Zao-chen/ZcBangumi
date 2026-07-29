import 'person.dart';
import 'subject.dart';

/// 用户收藏条目
class UserCollection {
  final int subjectId;
  final int subjectType;
  final int rate;
  final int type; // 1=想看 2=看过 3=在看 4=搁置 5=抛弃
  final String? comment;
  final List<String> tags;
  final int epStatus;
  final int volStatus;
  final DateTime updatedAt;
  final bool private_;
  final SlimSubject? subject;

  UserCollection({
    required this.subjectId,
    required this.subjectType,
    required this.rate,
    required this.type,
    this.comment,
    required this.tags,
    required this.epStatus,
    required this.volStatus,
    required this.updatedAt,
    required this.private_,
    this.subject,
  });

  factory UserCollection.fromJson(Map<String, dynamic> json) {
    return UserCollection(
      subjectId: json['subject_id'] as int,
      subjectType: json['subject_type'] as int,
      rate: (json['rate'] as int?) ?? 0,
      type: json['type'] as int,
      comment: json['comment'] as String?,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          [],
      epStatus: (json['ep_status'] as int?) ?? 0,
      volStatus: (json['vol_status'] as int?) ?? 0,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      private_: (json['private'] as bool?) ?? false,
      subject: json['subject'] != null
          ? SlimSubject.fromJson(json['subject'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'subject_id': subjectId,
    'subject_type': subjectType,
    'rate': rate,
    'type': type,
    'comment': comment,
    'tags': tags,
    'ep_status': epStatus,
    'vol_status': volStatus,
    'updated_at': updatedAt.toIso8601String(),
    'private': private_,
    'subject': subject?.toJson(),
  };
}

/// 用户收藏的角色或人物条目。
sealed class UserEntityCollection {
  final int id;
  final String name;
  final int type;
  final PersonImages? images;
  final DateTime createdAt;

  const UserEntityCollection({
    required this.id,
    required this.name,
    required this.type,
    this.images,
    required this.createdAt,
  });

  String get typeLabel;

  Map<String, dynamic> toJson();
}

/// 用户收藏的角色。
class UserCharacterCollection extends UserEntityCollection {
  const UserCharacterCollection({
    required super.id,
    required super.name,
    required super.type,
    super.images,
    required super.createdAt,
  });

  factory UserCharacterCollection.fromJson(Map<String, dynamic> json) {
    return UserCharacterCollection(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      type: (json['type'] as num?)?.toInt() ?? 0,
      images: _parseCollectionImages(json['images']),
      createdAt: _parseCollectionDate(json['created_at']),
    );
  }

  @override
  String get typeLabel => switch (type) {
    1 => '角色',
    2 => '机体',
    3 => '舰船',
    4 => '组织',
    _ => '其他',
  };

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    if (images != null) 'images': images!.toJson(),
    'created_at': createdAt.toIso8601String(),
  };
}

/// 用户收藏的人物。
class UserPersonCollection extends UserEntityCollection {
  final List<String> career;

  const UserPersonCollection({
    required super.id,
    required super.name,
    required super.type,
    this.career = const [],
    super.images,
    required super.createdAt,
  });

  factory UserPersonCollection.fromJson(Map<String, dynamic> json) {
    return UserPersonCollection(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      type: (json['type'] as num?)?.toInt() ?? 0,
      career: _parseCollectionCareer(json['career']),
      images: _parseCollectionImages(json['images']),
      createdAt: _parseCollectionDate(json['created_at']),
    );
  }

  @override
  String get typeLabel => switch (type) {
    1 => '个人',
    2 => '公司',
    3 => '组合',
    _ => '人物',
  };

  List<String> get careerLabels => career.map(personCareerLabel).toList();

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'career': career,
    if (images != null) 'images': images!.toJson(),
    'created_at': createdAt.toIso8601String(),
  };
}

PersonImages? _parseCollectionImages(dynamic value) {
  if (value is Map<String, dynamic>) return PersonImages.fromJson(value);
  if (value is Map) {
    return PersonImages.fromJson(Map<String, dynamic>.from(value));
  }
  return null;
}

List<String> _parseCollectionCareer(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

DateTime _parseCollectionDate(dynamic value) {
  return DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
