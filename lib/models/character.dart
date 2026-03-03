/// 角色
class Character {
  final int id;
  final String name;
  final String type; // 角色/机体/舰船/组织
  final List<CharacterImage> images;
  final String comment;
  final int collects;
  final String relation; // 主角/配角
  final String summary; // 详细描述
  final Map<String, String> infobox; // 详细信息

  Character({
    required this.id,
    required this.name,
    required this.type,
    required this.images,
    required this.comment,
    required this.collects,
    required this.relation,
    this.summary = '',
    Map<String, String>? infobox,
  }) : infobox = infobox ?? {};

  factory Character.fromJson(Map<String, dynamic> json) {
    final imagesList = <CharacterImage>[];
    if (json['images'] != null) {
      final images = json['images'] as Map<String, dynamic>;
      imagesList.add(CharacterImage.fromJson(images));
    }

    // type 可能是 int 或 String，需要统一转换为 String
    String typeStr = '';
    final typeValue = json['type'];
    if (typeValue is int) {
      // 1=角色, 2=机体, 3=舰船, 4=组织
      typeStr = {
        1: '角色',
        2: '机体',
        3: '舰船',
        4: '组织',
      }[typeValue] ?? '';
    } else if (typeValue is String) {
      typeStr = typeValue;
    }

    // 解析 infobox
    final infoboxMap = <String, String>{};
    if (json['infobox'] != null) {
      final infobox = json['infobox'] as List<dynamic>;
      for (final item in infobox) {
        if (item is Map<String, dynamic>) {
          final key = item['key'] as String?;
          final value = item['value'] as dynamic;
          if (key != null && value != null) {
            infoboxMap[key] = value.toString();
          }
        }
      }
    }

    return Character(
      id: json['id'] as int,
      name: (json['name'] as String?) ?? '',
      type: typeStr,
      images: imagesList,
      comment: (json['comment'] as String?) ?? '',
      collects: (json['collects'] as int?) ?? 0,
      relation: (json['relation'] as String?) ?? '',
      summary: (json['summary'] as String?) ?? '',
      infobox: infoboxMap,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'images': images.map((e) => e.toJson()).toList(),
        'comment': comment,
        'collects': collects,
        'relation': relation,
        'summary': summary,
        'infobox': infobox.entries
            .map((e) => {'key': e.key, 'value': e.value})
            .toList(),
      };
}

class CharacterImage {
  final String large;
  final String medium;
  final String small;
  final String grid;

  CharacterImage({
    required this.large,
    required this.medium,
    required this.small,
    required this.grid,
  });

  factory CharacterImage.fromJson(Map<String, dynamic> json) {
    return CharacterImage(
      large: (json['large'] as String?) ?? '',
      medium: (json['medium'] as String?) ?? '',
      small: (json['small'] as String?) ?? '',
      grid: (json['grid'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'large': large,
        'medium': medium,
        'small': small,
        'grid': grid,
      };
}

/// 关联条目
class RelatedSubject {
  final int id;
  final int type;
  final String name;
  final String nameCn;
  final String relation; // 前传/续集/番外篇/其他
  final Map<String, String> images;

  RelatedSubject({
    required this.id,
    required this.type,
    required this.name,
    required this.nameCn,
    required this.relation,
    required this.images,
  });

  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  factory RelatedSubject.fromJson(Map<String, dynamic> json) {
    final imagesMap = <String, String>{};
    if (json['images'] != null) {
      final images = json['images'] as Map<String, dynamic>;
      images.forEach((key, value) {
        if (value is String) {
          imagesMap[key] = value;
        }
      });
    }

    return RelatedSubject(
      id: json['id'] as int,
      type: (json['type'] as int?) ?? 0,
      name: (json['name'] as String?) ?? '',
      nameCn: (json['name_cn'] as String?) ?? '',
      relation: (json['relation'] as String?) ?? '',
      images: imagesMap,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'name_cn': nameCn,
        'relation': relation,
        'images': images,
      };
}
