/// 条目图片
class SubjectImages {
  final String large;
  final String common;
  final String medium;
  final String small;
  final String grid;

  SubjectImages({
    required this.large,
    required this.common,
    required this.medium,
    required this.small,
    required this.grid,
  });

  factory SubjectImages.fromJson(Map<String, dynamic> json) {
    return SubjectImages(
      large: (json['large'] as String?) ?? '',
      common: (json['common'] as String?) ?? '',
      medium: (json['medium'] as String?) ?? '',
      small: (json['small'] as String?) ?? '',
      grid: (json['grid'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'large': large,
        'common': common,
        'medium': medium,
        'small': small,
        'grid': grid,
      };
}

/// 精简条目（用于收藏列表）
class SlimSubject {
  final int id;
  final int type;
  final String name;
  final String nameCn;
  final String shortSummary;
  final SubjectImages? images;
  final int eps;
  final int volumes;
  final int collectionTotal;
  final double score;
  final int rank;

  SlimSubject({
    required this.id,
    required this.type,
    required this.name,
    required this.nameCn,
    required this.shortSummary,
    this.images,
    required this.eps,
    required this.volumes,
    required this.collectionTotal,
    required this.score,
    required this.rank,
  });

  /// 优先显示中文名
  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  factory SlimSubject.fromJson(Map<String, dynamic> json) {
    return SlimSubject(
      id: json['id'] as int,
      type: json['type'] as int,
      name: (json['name'] as String?) ?? '',
      nameCn: (json['name_cn'] as String?) ?? '',
      shortSummary: (json['short_summary'] as String?) ?? '',
      images: json['images'] != null
          ? SubjectImages.fromJson(json['images'] as Map<String, dynamic>)
          : null,
      eps: (json['eps'] as int?) ?? 0,
      volumes: (json['volumes'] as int?) ?? 0,
      collectionTotal: (json['collection_total'] as int?) ?? 0,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      rank: (json['rank'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'name_cn': nameCn,
        'short_summary': shortSummary,
        'images': images?.toJson(),
        'eps': eps,
        'volumes': volumes,
        'collection_total': collectionTotal,
        'score': score,
        'rank': rank,
      };
}

/// 完整条目信息（用于详情页）
class Subject {
  final int id;
  final int type;
  final String name;
  final String nameCn;
  final String summary;
  final SubjectImages? images;
  final int eps;
  final int volumes;
  final double score;
  final int rank;
  final int collectionTotal;
  final String date;
  final List<String> tags;
  final Map<String, String> infobox;

  Subject({
    required this.id,
    required this.type,
    required this.name,
    required this.nameCn,
    required this.summary,
    this.images,
    required this.eps,
    required this.volumes,
    required this.score,
    required this.rank,
    required this.collectionTotal,
    required this.date,
    required this.tags,
    required this.infobox,
  });

  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  factory Subject.fromJson(Map<String, dynamic> json) {
    // 解析 tags
    final tagsList = <String>[];
    if (json['tags'] != null) {
      for (final tag in json['tags'] as List<dynamic>) {
        if (tag is Map<String, dynamic> && tag['name'] != null) {
          tagsList.add(tag['name'] as String);
        }
      }
    }

    // 解析 infobox
    final infoboxMap = <String, String>{};
    if (json['infobox'] != null) {
      for (final item in json['infobox'] as List<dynamic>) {
        if (item is Map<String, dynamic>) {
          final key = item['key'] as String? ?? '';
          final rawValue = item['value'];
          
          // 处理不同类型的 value
          String value;
          if (rawValue is String) {
            value = rawValue;
          } else if (rawValue is List) {
            // 如果是列表，将每个元素转为字符串并用逗号分隔
            value = rawValue
                .map((e) => e is Map ? (e['v'] ?? e.toString()) : e.toString())
                .join(', ');
          } else if (rawValue is Map) {
            // 如果是 Map，尝试获取 v 字段或转为字符串
            value = rawValue['v']?.toString() ?? rawValue.toString();
          } else {
            value = rawValue?.toString() ?? '';
          }
          
          if (key.isNotEmpty) {
            infoboxMap[key] = value;
          }
        }
      }
    }

    return Subject(
      id: json['id'] as int,
      type: json['type'] as int,
      name: (json['name'] as String?) ?? '',
      nameCn: (json['name_cn'] as String?) ?? '',
      summary: (json['summary'] as String?) ?? '',
      images: json['images'] != null
          ? SubjectImages.fromJson(json['images'] as Map<String, dynamic>)
          : null,
      eps: (json['eps'] as int?) ?? 0,
      volumes: (json['volumes'] as int?) ?? 0,
      score: (json['rating']?['score'] as num?)?.toDouble() ?? 
             (json['score'] as num?)?.toDouble() ?? 0.0,
      rank: (json['rating']?['rank'] as int?) ?? 
            (json['rank'] as int?) ?? 0,
      collectionTotal: (json['collection_total'] as int?) ?? 0,
      date: (json['date'] as String?) ?? '',
      tags: tagsList,
      infobox: infoboxMap,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'name_cn': nameCn,
        'summary': summary,
        'images': images?.toJson(),
        'eps': eps,
        'volumes': volumes,
        'score': score,
        'rank': rank,
        'collection_total': collectionTotal,
        'date': date,
        'tags': tags,
        'infobox': infobox,
      };
}
