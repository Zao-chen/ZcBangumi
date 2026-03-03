import 'subject.dart';

/// 每日放送 - 一周中的某一天
class CalendarDay {
  final CalendarWeekday weekday;
  final List<CalendarSubject> items;

  CalendarDay({required this.weekday, required this.items});

  factory CalendarDay.fromJson(Map<String, dynamic> json) {
    return CalendarDay(
      weekday:
          CalendarWeekday.fromJson(json['weekday'] as Map<String, dynamic>),
      items: (json['items'] as List<dynamic>?)
              ?.map(
                  (e) => CalendarSubject.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// 星期几
class CalendarWeekday {
  final String en;
  final String cn;
  final String ja;
  final int id;

  CalendarWeekday({
    required this.en,
    required this.cn,
    required this.ja,
    required this.id,
  });

  factory CalendarWeekday.fromJson(Map<String, dynamic> json) {
    return CalendarWeekday(
      en: (json['en'] as String?) ?? '',
      cn: (json['cn'] as String?) ?? '',
      ja: (json['ja'] as String?) ?? '',
      id: (json['id'] as int?) ?? 0,
    );
  }
}

/// 每日放送中的条目
class CalendarSubject {
  final int id;
  final String url;
  final int type;
  final String name;
  final String nameCn;
  final String summary;
  final String? airDate;
  final int? airWeekday;
  final SubjectImages? images;
  final int eps;
  final int epsCount;
  final CalendarRating? rating;
  final int? rank;

  CalendarSubject({
    required this.id,
    required this.url,
    required this.type,
    required this.name,
    required this.nameCn,
    required this.summary,
    this.airDate,
    this.airWeekday,
    this.images,
    required this.eps,
    required this.epsCount,
    this.rating,
    this.rank,
  });

  /// 优先显示中文名
  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  factory CalendarSubject.fromJson(Map<String, dynamic> json) {
    return CalendarSubject(
      id: json['id'] as int,
      url: (json['url'] as String?) ?? '',
      type: (json['type'] as int?) ?? 2,
      name: (json['name'] as String?) ?? '',
      nameCn: (json['name_cn'] as String?) ?? '',
      summary: (json['summary'] as String?) ?? '',
      airDate: json['air_date'] as String?,
      airWeekday: json['air_weekday'] as int?,
      images: json['images'] != null
          ? SubjectImages.fromJson(json['images'] as Map<String, dynamic>)
          : null,
      eps: (json['eps'] as int?) ?? 0,
      epsCount: (json['eps_count'] as int?) ?? 0,
      rating: json['rating'] != null
          ? CalendarRating.fromJson(json['rating'] as Map<String, dynamic>)
          : null,
      rank: json['rank'] as int?,
    );
  }
}

/// 评分
class CalendarRating {
  final int total;
  final double score;

  CalendarRating({required this.total, required this.score});

  factory CalendarRating.fromJson(Map<String, dynamic> json) {
    return CalendarRating(
      total: (json['total'] as int?) ?? 0,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
