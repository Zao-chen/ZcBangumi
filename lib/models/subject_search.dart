/// 官方条目搜索支持的排序方式。
enum SubjectSearchSort {
  match,
  heat,
  rank,
  score;

  String get apiValue => name;
}

/// 官方 `/v0/search/subjects` 的筛选条件。
class SubjectSearchFilter {
  final List<int> types;
  final List<String> metaTags;
  final List<String> tags;
  final List<String> airDates;
  final List<String> ratings;
  final List<String> ratingCounts;
  final List<String> ranks;
  final bool? nsfw;

  const SubjectSearchFilter({
    this.types = const [],
    this.metaTags = const [],
    this.tags = const [],
    this.airDates = const [],
    this.ratings = const [],
    this.ratingCounts = const [],
    this.ranks = const [],
    this.nsfw,
  });

  bool get isEmpty =>
      types.isEmpty &&
      metaTags.isEmpty &&
      tags.isEmpty &&
      airDates.isEmpty &&
      ratings.isEmpty &&
      ratingCounts.isEmpty &&
      ranks.isEmpty &&
      nsfw == null;

  Map<String, dynamic> toJson() => {
    if (types.isNotEmpty) 'type': types,
    if (metaTags.isNotEmpty) 'meta_tags': metaTags,
    if (tags.isNotEmpty) 'tag': tags,
    if (airDates.isNotEmpty) 'air_date': airDates,
    if (ratings.isNotEmpty) 'rating': ratings,
    if (ratingCounts.isNotEmpty) 'rating_count': ratingCounts,
    if (ranks.isNotEmpty) 'rank': ranks,
    if (nsfw != null) 'nsfw': nsfw,
  };
}

/// 官方条目搜索的 JSON 请求体。
class SubjectSearchRequest {
  final String keyword;
  final SubjectSearchSort sort;
  final SubjectSearchFilter filter;

  const SubjectSearchRequest({
    required this.keyword,
    this.sort = SubjectSearchSort.match,
    this.filter = const SubjectSearchFilter(),
  });

  Map<String, dynamic> toJson() => {
    'keyword': keyword,
    'sort': sort.apiValue,
    if (!filter.isEmpty) 'filter': filter.toJson(),
  };
}
