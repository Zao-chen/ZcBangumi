import 'package:zc_bangumi/models/subject.dart';
import 'package:zc_bangumi/models/subject_search.dart';
import 'package:zc_bangumi/services/api_client.dart';

class TagSearchCall {
  final String keyword;
  final SubjectSearchSort sort;
  final SubjectSearchFilter filter;
  final int limit;
  final int offset;

  const TagSearchCall({
    required this.keyword,
    required this.sort,
    required this.filter,
    required this.limit,
    required this.offset,
  });
}

class TagSearchTestApi extends ApiClient {
  final List<TagSearchCall> calls = [];
  Future<PagedResult<SlimSubject>> Function(TagSearchCall)? handler;

  @override
  Future<PagedResult<SlimSubject>> searchSubjects({
    required String keyword,
    SubjectSearchSort sort = SubjectSearchSort.match,
    SubjectSearchFilter filter = const SubjectSearchFilter(),
    int limit = 30,
    int offset = 0,
  }) async {
    final call = TagSearchCall(
      keyword: keyword,
      sort: sort,
      filter: filter,
      limit: limit,
      offset: offset,
    );
    calls.add(call);
    if (handler != null) return handler!(call);
    return tagSearchPage(call, [tagTestSubject()]);
  }
}

PagedResult<SlimSubject> tagSearchPage(
  TagSearchCall call,
  List<SlimSubject> subjects, {
  int? total,
}) => PagedResult(
  total: total ?? subjects.length,
  limit: call.limit,
  offset: call.offset,
  data: subjects,
);

SlimSubject tagTestSubject({
  int id = 1,
  int type = 2,
  String name = '测试条目',
  List<String> tags = const ['治愈', '校园'],
}) => SlimSubject(
  id: id,
  type: type,
  name: name,
  nameCn: name,
  shortSummary: '来自 API 的简介',
  eps: 12,
  volumes: 0,
  collectionTotal: 80,
  score: 8.2,
  rank: 10,
  date: '2024-04-01',
  ratingTotal: 50,
  tags: tags,
);
