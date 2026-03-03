/// 章节/剧集
class Episode {
  final int id;
  final int type;
  final String name;
  final String nameCn;
  final double sort;
  final double? ep;
  final String airdate;
  final int comment;
  final String duration;
  final String desc;
  final int disc;

  Episode({
    required this.id,
    required this.type,
    required this.name,
    required this.nameCn,
    required this.sort,
    this.ep,
    required this.airdate,
    required this.comment,
    required this.duration,
    required this.desc,
    required this.disc,
  });

  /// 显示名称
  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  /// 排序用的集数显示
  String get sortLabel {
    final n = ep ?? sort;
    return n == n.toInt().toDouble() ? '${n.toInt()}' : '$n';
  }

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      id: json['id'] as int,
      type: (json['type'] as int?) ?? 0,
      name: (json['name'] as String?) ?? '',
      nameCn: (json['name_cn'] as String?) ?? '',
      sort: (json['sort'] as num?)?.toDouble() ?? 0,
      ep: (json['ep'] as num?)?.toDouble(),
      airdate: (json['airdate'] as String?) ?? '',
      comment: (json['comment'] as int?) ?? 0,
      duration: (json['duration'] as String?) ?? '',
      desc: (json['desc'] as String?) ?? '',
      disc: (json['disc'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'name_cn': nameCn,
        'sort': sort,
        'ep': ep,
        'airdate': airdate,
        'comment': comment,
        'duration': duration,
        'desc': desc,
        'disc': disc,
      };
}

/// 用户章节收藏
class UserEpisodeCollection {
  final Episode episode;
  final int type; // 0=未收藏 1=想看 2=看过 3=抛弃

  UserEpisodeCollection({
    required this.episode,
    required this.type,
  });

  factory UserEpisodeCollection.fromJson(Map<String, dynamic> json) {
    return UserEpisodeCollection(
      episode: Episode.fromJson(json['episode'] as Map<String, dynamic>),
      type: (json['type'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'episode': episode.toJson(),
        'type': type,
      };
}
