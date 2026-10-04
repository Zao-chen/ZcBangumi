import 'dart:convert';

import '../constants.dart';
import 'subject_browse.dart';
import 'subject_search.dart';
import 'unified_search.dart';

class SubjectTagQuery {
  final int? subjectType;
  final String keyword;
  final SubjectSearchSort sort;
  final UnifiedSearchOptions options;

  const SubjectTagQuery({
    this.subjectType = BgmConst.subjectAnime,
    this.keyword = '',
    this.sort = SubjectSearchSort.heat,
    this.options = const UnifiedSearchOptions(),
  });

  String get typeLabel =>
      subjectType == null ? '全部类型' : subjectTypeLabel(subjectType!);

  SubjectSearchFilter get filter =>
      options.toSubjectFilter(subjectType: subjectType);

  bool get hasCriteria =>
      keyword.trim().isNotEmpty ||
      options.activeLabelsFor(SearchScope.subjects).isNotEmpty;

  String get label => [
    if (options.tags.isNotEmpty) options.tags.join(' + '),
    if (options.metaTags.isNotEmpty) '公共：${options.metaTags.join(' + ')}',
    if (keyword.isNotEmpty) '关键词：$keyword',
    if (!hasCriteria) '全部$typeLabel',
    if (hasCriteria &&
        options.tags.isEmpty &&
        options.metaTags.isEmpty &&
        keyword.isEmpty)
      '条件筛选',
  ].join(' · ');

  String get description => [
    typeLabel,
    subjectTagSortLabel(sort),
    if (filter.airDates.isNotEmpty) '日期 ${filter.airDates.join(' ')}',
    if (filter.ratings.isNotEmpty) '评分 ${filter.ratings.join(' ')}',
    if (filter.ratingCounts.isNotEmpty) '评分人数 ${filter.ratingCounts.join(' ')}',
    if (filter.ranks.isNotEmpty) '排名 ${filter.ranks.join(' ')}',
    if (options.nsfwMode == SearchNsfwMode.safeOnly) '仅非成人内容',
    if (options.nsfwMode == SearchNsfwMode.adultOnly) '仅成人内容',
  ].join(' · ');

  String get identity {
    final payload = toJson();
    final normalizedOptions = Map<String, dynamic>.from(
      payload['options'] as Map,
    );
    normalizedOptions['tags'] = normalizeSubjectTags(options.tags)..sort();
    normalizedOptions['meta_tags'] = normalizeSubjectTags(options.metaTags)
      ..sort();
    payload['keyword'] = keyword.trim();
    payload['options'] = normalizedOptions;
    return jsonEncode(payload);
  }

  SubjectTagQuery copyWith({
    int? subjectType,
    bool clearSubjectType = false,
    String? keyword,
    SubjectSearchSort? sort,
    UnifiedSearchOptions? options,
  }) => SubjectTagQuery(
    subjectType: clearSubjectType ? null : (subjectType ?? this.subjectType),
    keyword: keyword ?? this.keyword,
    sort: sort ?? this.sort,
    options: options ?? this.options,
  );

  SubjectTagQuery withTags(Iterable<String> tags) => copyWith(
    options: UnifiedSearchOptions(
      tags: normalizeSubjectTags(tags),
      metaTags: options.metaTags,
      airDateFrom: options.airDateFrom,
      airDateTo: options.airDateTo,
      ratingMin: options.ratingMin,
      ratingMax: options.ratingMax,
      ratingCountMin: options.ratingCountMin,
      ratingCountMax: options.ratingCountMax,
      rankMin: options.rankMin,
      rankMax: options.rankMax,
      nsfwMode: options.nsfwMode,
    ),
  );

  Map<String, dynamic> toJson() => {
    'subject_type': subjectType,
    'keyword': keyword,
    'sort': sort.name,
    'options': {
      'tags': options.tags,
      'meta_tags': options.metaTags,
      'air_date_from': options.airDateFrom == null
          ? null
          : formatSearchApiDate(options.airDateFrom!),
      'air_date_to': options.airDateTo == null
          ? null
          : formatSearchApiDate(options.airDateTo!),
      'rating_min': options.ratingMin,
      'rating_max': options.ratingMax,
      'rating_count_min': options.ratingCountMin,
      'rating_count_max': options.ratingCountMax,
      'rank_min': options.rankMin,
      'rank_max': options.rankMax,
      'nsfw': options.nsfwMode.name,
    },
  };

  factory SubjectTagQuery.fromJson(Map<String, dynamic> json) {
    final type = json['subject_type'] as int?;
    if (type != null && !subjectBrowseTypes.contains(type)) {
      throw const FormatException('无效的条目类型');
    }
    final options = Map<String, dynamic>.from(json['options'] as Map);
    return SubjectTagQuery(
      subjectType: type,
      keyword: (json['keyword'] as String).trim(),
      sort: SubjectSearchSort.values.byName(json['sort'] as String),
      options: UnifiedSearchOptions(
        tags: normalizeSubjectTags(List<String>.from(options['tags'] as List)),
        metaTags: normalizeSubjectTags(
          List<String>.from(options['meta_tags'] as List),
        ),
        airDateFrom: options['air_date_from'] == null
            ? null
            : DateTime.parse(options['air_date_from'] as String),
        airDateTo: options['air_date_to'] == null
            ? null
            : DateTime.parse(options['air_date_to'] as String),
        ratingMin: (options['rating_min'] as num?)?.toDouble(),
        ratingMax: (options['rating_max'] as num?)?.toDouble(),
        ratingCountMin: options['rating_count_min'] as int?,
        ratingCountMax: options['rating_count_max'] as int?,
        rankMin: options['rank_min'] as int?,
        rankMax: options['rank_max'] as int?,
        nsfwMode: SearchNsfwMode.values.byName(options['nsfw'] as String),
      ),
    );
  }
}

class RelatedSubjectTag {
  final String name;
  final int subjectCount;

  const RelatedSubjectTag({required this.name, required this.subjectCount});
}

List<String> normalizeSubjectTags(Iterable<String> tags) => tags
    .map((tag) => tag.trim())
    .where((tag) => tag.isNotEmpty)
    .toSet()
    .toList(growable: false);

List<String> parseSubjectTags(String input) =>
    normalizeSubjectTags(input.split(RegExp(r'[,，\n]+')));

String subjectTagSortLabel(SubjectSearchSort sort) => switch (sort) {
  SubjectSearchSort.match => '匹配程度',
  SubjectSearchSort.heat => '收藏热度',
  SubjectSearchSort.rank => '排名',
  SubjectSearchSort.score => '评分',
};

List<String> commonSubjectTags(int? type) => switch (type) {
  BgmConst.subjectBook => const [
    '漫画',
    '小说',
    '轻小说',
    '恋爱',
    '奇幻',
    '科幻',
    '悬疑',
    '日常',
  ],
  BgmConst.subjectMusic => const [
    'OST',
    'OP',
    'ED',
    'JPOP',
    'ACG',
    '同人',
    '声优',
    '纯音乐',
  ],
  BgmConst.subjectGame => const [
    'Galgame',
    'RPG',
    'ADV',
    '视觉小说',
    '剧情',
    '恋爱',
    '独立游戏',
    '动作',
  ],
  BgmConst.subjectReal => const [
    '日剧',
    '电影',
    '美剧',
    '特摄',
    '悬疑',
    '喜剧',
    '科幻',
    '恋爱',
  ],
  _ => const [
    '治愈',
    '日常',
    '校园',
    '恋爱',
    '科幻',
    '奇幻',
    '悬疑',
    '冒险',
    '搞笑',
    '音乐',
    '原创',
    '轻小说改',
  ],
};
