import 'entity_search.dart';
import 'subject_search.dart';

enum SearchScope { all, subjects, characters, persons }

enum SearchNsfwMode { any, safeOnly, adultOnly }

class UnifiedSearchOptions {
  final List<String> metaTags;
  final List<String> tags;
  final DateTime? airDateFrom;
  final DateTime? airDateTo;
  final double? ratingMin;
  final double? ratingMax;
  final int? ratingCountMin;
  final int? ratingCountMax;
  final int? rankMin;
  final int? rankMax;
  final SearchNsfwMode nsfwMode;
  final List<String> personCareers;

  const UnifiedSearchOptions({
    this.metaTags = const [],
    this.tags = const [],
    this.airDateFrom,
    this.airDateTo,
    this.ratingMin,
    this.ratingMax,
    this.ratingCountMin,
    this.ratingCountMax,
    this.rankMin,
    this.rankMax,
    this.nsfwMode = SearchNsfwMode.any,
    this.personCareers = const [],
  });

  List<String> activeLabelsFor(SearchScope scope) => [
    if (scope == SearchScope.all || scope == SearchScope.subjects) ...[
      if (metaTags.isNotEmpty) '公共标签',
      if (tags.isNotEmpty) '用户标签',
      if (airDateFrom != null || airDateTo != null) '日期',
      if (ratingMin != null || ratingMax != null) '评分',
      if (ratingCountMin != null || ratingCountMax != null) '评分人数',
      if (rankMin != null || rankMax != null) '排名',
    ],
    if (scope != SearchScope.persons && nsfwMode != SearchNsfwMode.any) 'NSFW',
    if ((scope == SearchScope.all || scope == SearchScope.persons) &&
        personCareers.isNotEmpty)
      '职业',
  ];

  SubjectSearchFilter toSubjectFilter({required int? subjectType}) {
    return SubjectSearchFilter(
      types: subjectType == null ? const [] : [subjectType],
      metaTags: metaTags,
      tags: tags,
      airDates: [
        if (airDateFrom != null) '>=${formatSearchApiDate(airDateFrom!)}',
        if (airDateTo != null) '<=${formatSearchApiDate(airDateTo!)}',
      ],
      ratings: [
        if (ratingMin != null) '>=${formatSearchNumber(ratingMin!)}',
        if (ratingMax != null) '<=${formatSearchNumber(ratingMax!)}',
      ],
      ratingCounts: [
        if (ratingCountMin != null) '>=$ratingCountMin',
        if (ratingCountMax != null) '<=$ratingCountMax',
      ],
      ranks: [
        if (rankMin != null) '>=$rankMin',
        if (rankMax != null) '<=$rankMax',
      ],
      nsfw: _nsfwValue,
    );
  }

  CharacterSearchFilter toCharacterFilter() =>
      CharacterSearchFilter(nsfw: _nsfwValue);

  PersonSearchFilter toPersonFilter() =>
      PersonSearchFilter(careers: personCareers);

  bool? get _nsfwValue => switch (nsfwMode) {
    SearchNsfwMode.any => null,
    SearchNsfwMode.safeOnly => false,
    SearchNsfwMode.adultOnly => true,
  };
}

String formatSearchApiDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String formatSearchNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();
