class PersonImages {
  final String large;
  final String medium;
  final String small;
  final String grid;

  const PersonImages({
    this.large = '',
    this.medium = '',
    this.small = '',
    this.grid = '',
  });

  factory PersonImages.fromJson(Map<String, dynamic> json) {
    return PersonImages(
      large: (json['large'] as String?) ?? '',
      medium: (json['medium'] as String?) ?? '',
      small: (json['small'] as String?) ?? '',
      grid: (json['grid'] as String?) ?? '',
    );
  }

  String get bestLarge => large.isNotEmpty ? large : medium;
  String get bestSmall => medium.isNotEmpty ? medium : small;

  Map<String, dynamic> toJson() => {
    'large': large,
    'medium': medium,
    'small': small,
    'grid': grid,
  };
}

class PersonSummary {
  final int id;
  final String name;
  final int type;
  final List<String> career;
  final PersonImages? images;
  final String shortSummary;
  final bool locked;

  const PersonSummary({
    required this.id,
    required this.name,
    required this.type,
    this.career = const [],
    this.images,
    this.shortSummary = '',
    this.locked = false,
  });

  factory PersonSummary.fromJson(Map<String, dynamic> json) {
    return PersonSummary(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      type: (json['type'] as num?)?.toInt() ?? 0,
      career: _stringList(json['career']),
      images: _parseImages(json['images']),
      shortSummary: (json['short_summary'] as String?) ?? '',
      locked: (json['locked'] as bool?) ?? false,
    );
  }

  String get typeLabel => switch (type) {
    1 => '个人',
    2 => '公司',
    3 => '组合',
    _ => '人物',
  };

  List<String> get careerLabels => career.map(personCareerLabel).toList();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'career': career,
    if (images != null) 'images': images!.toJson(),
    'short_summary': shortSummary,
    'locked': locked,
  };
}

class RelatedPerson extends PersonSummary {
  final String relation;
  final String eps;

  const RelatedPerson({
    required super.id,
    required super.name,
    required super.type,
    super.career,
    super.images,
    required this.relation,
    required this.eps,
  });

  factory RelatedPerson.fromJson(Map<String, dynamic> json) {
    return RelatedPerson(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      type: (json['type'] as num?)?.toInt() ?? 0,
      career: _stringList(json['career']),
      images: _parseImages(json['images']),
      relation: (json['relation'] as String?) ?? '',
      eps: (json['eps'] as String?) ?? '',
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'relation': relation,
    'eps': eps,
  };
}

class PersonDetail extends PersonSummary {
  final String summary;
  final DateTime? lastModified;
  final Map<String, String> infobox;
  final String gender;
  final int? bloodType;
  final int? birthYear;
  final int? birthMonth;
  final int? birthDay;
  final int comments;
  final int collects;

  const PersonDetail({
    required super.id,
    required super.name,
    required super.type,
    super.career,
    super.images,
    super.locked,
    required this.summary,
    this.lastModified,
    this.infobox = const {},
    this.gender = '',
    this.bloodType,
    this.birthYear,
    this.birthMonth,
    this.birthDay,
    this.comments = 0,
    this.collects = 0,
  }) : super(shortSummary: summary);

  factory PersonDetail.fromJson(Map<String, dynamic> json) {
    final stat = json['stat'] is Map
        ? Map<String, dynamic>.from(json['stat'] as Map)
        : const <String, dynamic>{};
    return PersonDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      type: (json['type'] as num?)?.toInt() ?? 0,
      career: _stringList(json['career']),
      images: _parseImages(json['images']),
      locked: (json['locked'] as bool?) ?? false,
      summary: (json['summary'] as String?) ?? '',
      lastModified: DateTime.tryParse((json['last_modified'] as String?) ?? ''),
      infobox: _parseInfobox(json['infobox']),
      gender: (json['gender'] as String?) ?? '',
      bloodType: (json['blood_type'] as num?)?.toInt(),
      birthYear: (json['birth_year'] as num?)?.toInt(),
      birthMonth: (json['birth_mon'] as num?)?.toInt(),
      birthDay: (json['birth_day'] as num?)?.toInt(),
      comments: (stat['comments'] as num?)?.toInt() ?? 0,
      collects: (stat['collects'] as num?)?.toInt() ?? 0,
    );
  }

  String get bloodTypeLabel => switch (bloodType) {
    1 => 'A',
    2 => 'B',
    3 => 'AB',
    4 => 'O',
    _ => '',
  };

  String get birthdayLabel {
    final parts = <String>[];
    if (birthYear != null) parts.add('$birthYear年');
    if (birthMonth != null) parts.add('$birthMonth月');
    if (birthDay != null) parts.add('$birthDay日');
    return parts.join();
  }

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'summary': summary,
    if (lastModified != null) 'last_modified': lastModified!.toIso8601String(),
    'infobox': infobox.entries
        .map((entry) => {'key': entry.key, 'value': entry.value})
        .toList(),
    if (gender.isNotEmpty) 'gender': gender,
    if (bloodType != null) 'blood_type': bloodType,
    if (birthYear != null) 'birth_year': birthYear,
    if (birthMonth != null) 'birth_mon': birthMonth,
    if (birthDay != null) 'birth_day': birthDay,
    'stat': {'comments': comments, 'collects': collects},
  };
}

class PersonSubject {
  final int id;
  final int type;
  final String name;
  final String nameCn;
  final String image;
  final String staff;
  final String eps;

  const PersonSubject({
    required this.id,
    required this.type,
    required this.name,
    required this.nameCn,
    required this.image,
    required this.staff,
    required this.eps,
  });

  factory PersonSubject.fromJson(Map<String, dynamic> json) {
    return PersonSubject(
      id: (json['id'] as num?)?.toInt() ?? 0,
      type: (json['type'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      nameCn: (json['name_cn'] as String?) ?? '',
      image: (json['image'] as String?) ?? '',
      staff: (json['staff'] as String?) ?? '',
      eps: (json['eps'] as String?) ?? '',
    );
  }

  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'name': name,
    'name_cn': nameCn,
    'image': image,
    'staff': staff,
    'eps': eps,
  };
}

class PersonCharacter {
  final int id;
  final String name;
  final int type;
  final PersonImages? images;
  final int subjectId;
  final int subjectType;
  final String subjectName;
  final String subjectNameCn;
  final String staff;

  const PersonCharacter({
    required this.id,
    required this.name,
    required this.type,
    this.images,
    required this.subjectId,
    required this.subjectType,
    required this.subjectName,
    required this.subjectNameCn,
    required this.staff,
  });

  factory PersonCharacter.fromJson(Map<String, dynamic> json) {
    return PersonCharacter(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      type: (json['type'] as num?)?.toInt() ?? 0,
      images: _parseImages(json['images']),
      subjectId: (json['subject_id'] as num?)?.toInt() ?? 0,
      subjectType: (json['subject_type'] as num?)?.toInt() ?? 0,
      subjectName: (json['subject_name'] as String?) ?? '',
      subjectNameCn: (json['subject_name_cn'] as String?) ?? '',
      staff: (json['staff'] as String?) ?? '',
    );
  }

  String get displaySubjectName =>
      subjectNameCn.isNotEmpty ? subjectNameCn : subjectName;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    if (images != null) 'images': images!.toJson(),
    'subject_id': subjectId,
    'subject_type': subjectType,
    'subject_name': subjectName,
    'subject_name_cn': subjectNameCn,
    'staff': staff,
  };
}

String personCareerLabel(String career) => switch (career) {
  'producer' => '制作人',
  'mangaka' => '漫画家',
  'artist' => '艺术家',
  'seiyu' => '声优',
  'writer' => '作家',
  'illustrator' => '插画家',
  'actor' => '演员',
  _ => career,
};

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

PersonImages? _parseImages(dynamic value) {
  if (value is Map<String, dynamic>) return PersonImages.fromJson(value);
  if (value is Map) {
    return PersonImages.fromJson(Map<String, dynamic>.from(value));
  }
  return null;
}

Map<String, String> _parseInfobox(dynamic value) {
  if (value is! List) return const {};
  final result = <String, String>{};
  for (final item in value) {
    if (item is! Map) continue;
    final map = Map<String, dynamic>.from(item);
    final key = map['key']?.toString().trim() ?? '';
    final displayValue = _formatInfoboxValue(map['value']);
    if (key.isNotEmpty && displayValue.isNotEmpty) result[key] = displayValue;
  }
  return result;
}

String _formatInfoboxValue(dynamic value) {
  if (value == null) return '';
  if (value is String || value is num || value is bool) return '$value';
  if (value is List) {
    return value.map(_formatInfoboxValue).where((e) => e.isNotEmpty).join('、');
  }
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    final text = _formatInfoboxValue(map['v'] ?? map['value']);
    final label = _formatInfoboxValue(map['k'] ?? map['key']);
    if (text.isNotEmpty && label.isNotEmpty) return '$text（$label）';
    if (text.isNotEmpty) return text;
    return map.entries
        .map((entry) => '${entry.key}: ${_formatInfoboxValue(entry.value)}')
        .join('、');
  }
  return value.toString();
}
