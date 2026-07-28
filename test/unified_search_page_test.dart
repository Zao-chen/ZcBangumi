import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/character.dart';
import 'package:zc_bangumi/models/entity_search.dart';
import 'package:zc_bangumi/models/person.dart';
import 'package:zc_bangumi/models/subject.dart';
import 'package:zc_bangumi/models/subject_search.dart';
import 'package:zc_bangumi/models/unified_search.dart';
import 'package:zc_bangumi/pages/search_page.dart';
import 'package:zc_bangumi/providers/auth_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/storage_service.dart';

void main() {
  testWidgets('all scope searches every entity and groups previews', (
    tester,
  ) async {
    final api = _UnifiedSearchApiClient();
    await _pumpSearchPage(tester, api);

    expect(find.text('综合'), findsOneWidget);
    expect(_searchHint(tester), '搜索条目、角色或人物...');
    expect(
      find.byKey(const Key('search_advanced_filter_button')),
      findsNothing,
    );
    expect(find.text('条目类型'), findsNothing);

    await tester.enterText(find.byKey(const Key('search_query_field')), '爱音');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(api.subjectCalls, 1);
    expect(api.characterCalls, 1);
    expect(api.personCalls, 1);
    expect(api.subjectLimits.single, 6);
    expect(api.characterLimits.single, 6);
    expect(api.personLimits.single, 6);
    expect(api.subjectFilter?.isEmpty, isTrue);
    expect(api.characterFilter?.isEmpty, isTrue);
    expect(api.personFilter?.isEmpty, isTrue);
    expect(find.byKey(const Key('search_section_subjects')), findsOneWidget);
    expect(find.byKey(const Key('search_section_characters')), findsOneWidget);
    expect(find.byKey(const Key('search_section_persons')), findsOneWidget);
    expect(find.text('BanG Dream! It’s MyGO!!!!!'), findsOneWidget);
    expect(find.text('千早愛音'), findsOneWidget);
    expect(find.text('林原めぐみ'), findsOneWidget);

    final characterSection = find.byKey(const Key('search_section_characters'));
    await tester.tap(
      find.descendant(of: characterSection, matching: find.text('查看全部')),
    );
    await tester.pumpAndSettle();

    expect(_searchHint(tester), '搜索角色...');
    expect(api.characterCalls, 2);
    expect(api.characterLimits.last, 30);
    expect(api.subjectCalls, 1);
    expect(api.personCalls, 1);
  });

  testWidgets('person scope exposes career filters and sends them', (
    tester,
  ) async {
    final api = _UnifiedSearchApiClient();
    await _pumpSearchPage(tester, api);

    await tester.tap(find.text('人物'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search_advanced_filter_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('search_meta_tags_field')), findsNothing);
    expect(find.text('NSFW'), findsNothing);
    expect(find.byKey(const Key('search_person_career_seiyu')), findsOneWidget);

    await tester.tap(find.byKey(const Key('search_person_career_seiyu')));
    await tester.tap(find.byKey(const Key('search_apply_filters_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search_query_field')), '林原');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(api.personFilter?.careers, ['seiyu']);
    expect(api.personCalls, 1);
    expect(api.subjectCalls, 0);
    expect(api.characterCalls, 0);
    expect(find.byTooltip('筛选与排序（已自定义）'), findsOneWidget);
  });

  testWidgets('entity-specific controls only appear in their own scope', (
    tester,
  ) async {
    final api = _UnifiedSearchApiClient();
    await _pumpSearchPage(tester, api);

    expect(find.text('条目类型'), findsNothing);
    expect(
      find.byKey(const Key('search_advanced_filter_button')),
      findsNothing,
    );

    await tester.tap(find.text('条目'));
    await tester.pumpAndSettle();
    expect(find.text('条目类型'), findsOneWidget);
    expect(
      find.byKey(const Key('search_advanced_filter_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('search_subject_type_2')));
    await tester.tap(find.text('综合'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search_query_field')), '测试');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('条目类型'), findsNothing);
    expect(api.subjectFilter?.types, isEmpty);
  });

  testWidgets('all scope keeps successful groups when one API fails', (
    tester,
  ) async {
    final api = _UnifiedSearchApiClient(failCharacters: true);
    await _pumpSearchPage(tester, api);

    await tester.enterText(find.byKey(const Key('search_query_field')), '测试');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('BanG Dream! It’s MyGO!!!!!'), findsOneWidget);
    expect(find.text('林原めぐみ'), findsOneWidget);
    expect(find.text('角色搜索暂时不可用'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('wide layout uses a scope rail and keeps grouped results', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _UnifiedSearchApiClient();
    await _pumpSearchPage(tester, api);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(SegmentedButton<SearchScope>), findsNothing);

    await tester.enterText(find.byKey(const Key('search_query_field')), '爱音');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('search_section_subjects')), findsOneWidget);
    expect(find.byKey(const Key('search_section_characters')), findsOneWidget);
    expect(find.byKey(const Key('search_section_persons')), findsOneWidget);
  });
}

Future<void> _pumpSearchPage(
  WidgetTester tester,
  _UnifiedSearchApiClient api,
) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.init();
  final auth = AuthProvider(api: api, storage: storage);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: const MaterialApp(home: SearchPage()),
    ),
  );
}

String? _searchHint(WidgetTester tester) {
  return tester
      .widget<TextField>(find.byKey(const Key('search_query_field')))
      .decoration
      ?.hintText;
}

class _UnifiedSearchApiClient extends ApiClient {
  final bool failCharacters;
  int subjectCalls = 0;
  int characterCalls = 0;
  int personCalls = 0;
  final List<int> subjectLimits = [];
  final List<int> characterLimits = [];
  final List<int> personLimits = [];
  SubjectSearchFilter? subjectFilter;
  CharacterSearchFilter? characterFilter;
  PersonSearchFilter? personFilter;

  _UnifiedSearchApiClient({this.failCharacters = false});

  @override
  Future<PagedResult<SlimSubject>> searchSubjects({
    required String keyword,
    SubjectSearchSort sort = SubjectSearchSort.match,
    SubjectSearchFilter filter = const SubjectSearchFilter(),
    int limit = 30,
    int offset = 0,
  }) async {
    subjectCalls++;
    subjectLimits.add(limit);
    subjectFilter = filter;
    return PagedResult(
      total: 1,
      limit: limit,
      offset: offset,
      data: [_subject],
    );
  }

  @override
  Future<PagedResult<Character>> searchCharacters({
    required String keyword,
    CharacterSearchFilter filter = const CharacterSearchFilter(),
    int limit = 30,
    int offset = 0,
  }) async {
    characterCalls++;
    characterLimits.add(limit);
    characterFilter = filter;
    if (failCharacters) throw Exception('角色接口失败');
    return PagedResult(
      total: 1,
      limit: limit,
      offset: offset,
      data: [_character],
    );
  }

  @override
  Future<PagedResult<PersonSummary>> searchPersons({
    required String keyword,
    PersonSearchFilter filter = const PersonSearchFilter(),
    int limit = 30,
    int offset = 0,
  }) async {
    personCalls++;
    personLimits.add(limit);
    personFilter = filter;
    return PagedResult(total: 1, limit: limit, offset: offset, data: [_person]);
  }
}

final _subject = SlimSubject(
  id: 428735,
  type: 2,
  name: 'BanG Dream! It’s MyGO!!!!!',
  nameCn: '',
  shortSummary: '迷子也要前进。',
  eps: 13,
  volumes: 0,
  collectionTotal: 100,
  score: 8.1,
  rank: 100,
);

final _character = Character(
  id: 141354,
  name: '千早愛音',
  type: '角色',
  images: const [],
  comment: '',
  collects: 233,
  comments: 17,
  relation: '',
  summary: '月之森女子学园的转学生。',
);

const _person = PersonSummary(
  id: 3,
  name: '林原めぐみ',
  type: 1,
  career: ['seiyu', 'actor'],
  shortSummary: '日本女性声优、歌手。',
);
