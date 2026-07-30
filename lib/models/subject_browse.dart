import '../constants.dart';

enum SubjectBrowseSort {
  rank,
  date;

  String get apiValue => name;
}

class SubjectBrowseCategory {
  final int value;
  final String label;

  const SubjectBrowseCategory(this.value, this.label);
}

class SubjectBrowseFilter {
  final int type;
  final int? category;
  final bool? series;
  final String? platform;
  final int? year;
  final int? month;
  final SubjectBrowseSort sort;

  const SubjectBrowseFilter({
    this.type = BgmConst.subjectAnime,
    this.category,
    this.series,
    this.platform,
    this.year,
    this.month,
    this.sort = SubjectBrowseSort.rank,
  });

  SubjectBrowseFilter copyWith({
    int? type,
    int? category,
    bool clearCategory = false,
    bool? series,
    bool clearSeries = false,
    String? platform,
    bool clearPlatform = false,
    int? year,
    bool clearYear = false,
    int? month,
    bool clearMonth = false,
    SubjectBrowseSort? sort,
  }) {
    return SubjectBrowseFilter(
      type: type ?? this.type,
      category: clearCategory ? null : (category ?? this.category),
      series: clearSeries ? null : (series ?? this.series),
      platform: clearPlatform ? null : (platform ?? this.platform),
      year: clearYear ? null : (year ?? this.year),
      month: clearMonth ? null : (month ?? this.month),
      sort: sort ?? this.sort,
    );
  }

  String get cacheKey {
    final normalizedPlatform = platform?.trim() ?? '';
    return [
      type,
      category ?? '-',
      series ?? '-',
      normalizedPlatform,
      year ?? '-',
      month ?? '-',
      sort.apiValue,
    ].join('_');
  }
}

const subjectBrowseTypes = <int>[
  BgmConst.subjectAnime,
  BgmConst.subjectBook,
  BgmConst.subjectMusic,
  BgmConst.subjectGame,
  BgmConst.subjectReal,
];

String subjectTypeLabel(int type) => switch (type) {
  BgmConst.subjectBook => '书籍',
  BgmConst.subjectAnime => '动画',
  BgmConst.subjectMusic => '音乐',
  BgmConst.subjectGame => '游戏',
  BgmConst.subjectReal => '三次元',
  _ => '条目',
};

List<SubjectBrowseCategory> subjectBrowseCategories(int type) => switch (type) {
  BgmConst.subjectBook => const [
    SubjectBrowseCategory(0, '其他'),
    SubjectBrowseCategory(1001, '漫画'),
    SubjectBrowseCategory(1002, '小说'),
    SubjectBrowseCategory(1003, '画集'),
  ],
  BgmConst.subjectAnime => const [
    SubjectBrowseCategory(0, '其他'),
    SubjectBrowseCategory(1, 'TV'),
    SubjectBrowseCategory(2, 'OVA'),
    SubjectBrowseCategory(3, 'Movie'),
    SubjectBrowseCategory(5, 'WEB'),
  ],
  BgmConst.subjectGame => const [
    SubjectBrowseCategory(0, '其他'),
    SubjectBrowseCategory(4001, '游戏'),
    SubjectBrowseCategory(4002, '软件'),
    SubjectBrowseCategory(4003, '扩展包'),
    SubjectBrowseCategory(4005, '桌游'),
  ],
  BgmConst.subjectReal => const [
    SubjectBrowseCategory(0, '其他'),
    SubjectBrowseCategory(1, '日剧'),
    SubjectBrowseCategory(2, '欧美剧'),
    SubjectBrowseCategory(3, '华语剧'),
    SubjectBrowseCategory(6001, '电视剧'),
    SubjectBrowseCategory(6002, '电影'),
    SubjectBrowseCategory(6003, '演出'),
    SubjectBrowseCategory(6004, '综艺'),
  ],
  _ => const [],
};
