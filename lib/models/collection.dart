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
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
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
