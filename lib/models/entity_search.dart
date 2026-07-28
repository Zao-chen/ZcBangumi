/// 官方角色搜索的筛选条件。
class CharacterSearchFilter {
  final bool? nsfw;

  const CharacterSearchFilter({this.nsfw});

  bool get isEmpty => nsfw == null;

  Map<String, dynamic> toJson() => {if (nsfw != null) 'nsfw': nsfw};
}

/// 官方 `/v0/search/characters` 的请求体。
class CharacterSearchRequest {
  final String keyword;
  final CharacterSearchFilter filter;

  const CharacterSearchRequest({
    required this.keyword,
    this.filter = const CharacterSearchFilter(),
  });

  Map<String, dynamic> toJson() => {
    'keyword': keyword,
    if (!filter.isEmpty) 'filter': filter.toJson(),
  };
}

/// 官方人物搜索的筛选条件。
class PersonSearchFilter {
  final List<String> careers;

  const PersonSearchFilter({this.careers = const []});

  bool get isEmpty => careers.isEmpty;

  Map<String, dynamic> toJson() => {if (careers.isNotEmpty) 'career': careers};
}

/// 官方 `/v0/search/persons` 的请求体。
class PersonSearchRequest {
  final String keyword;
  final PersonSearchFilter filter;

  const PersonSearchRequest({
    required this.keyword,
    this.filter = const PersonSearchFilter(),
  });

  Map<String, dynamic> toJson() => {
    'keyword': keyword,
    if (!filter.isEmpty) 'filter': filter.toJson(),
  };
}
