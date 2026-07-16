import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/character.dart';
import 'package:zc_bangumi/models/comment.dart';
import 'package:zc_bangumi/models/person.dart';
import 'package:zc_bangumi/pages/character_page.dart';
import 'package:zc_bangumi/providers/auth_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/storage_service.dart';
import 'package:zc_bangumi/widgets/bangumi_post_widgets.dart';

void main() {
  testWidgets('character page shows related persons and opens person detail', (
    tester,
  ) async {
    final api = _CharacterPersonsApiClient();
    await _pumpCharacterPage(tester, api);

    expect(find.text('声优'), findsOneWidget);

    const personKey = ValueKey('character_person_3818');
    expect(find.byKey(personKey), findsOneWidget);
    expect(find.text('福山潤'), findsOneWidget);
    expect(find.text('Code Geass 反叛的鲁路修、闪耀幻想曲'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(personKey), matching: find.text('主角')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(personKey), matching: find.text('配角')),
      findsOneWidget,
    );
    expect(find.text('动画'), findsOneWidget);
    expect(find.text('游戏'), findsOneWidget);

    await tester.tap(find.byKey(personKey));
    await tester.pumpAndSettle();

    expect(find.text('人物详情'), findsOneWidget);
  });

  testWidgets('character page exposes a retryable person loading error', (
    tester,
  ) async {
    await _pumpCharacterPage(
      tester,
      _CharacterPersonsApiClient(failPersons: true),
    );

    expect(find.text('声优'), findsOneWidget);
    expect(find.text('加载关联人物失败'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
  });

  testWidgets('character overview hides the voice actor section when empty', (
    tester,
  ) async {
    await _pumpCharacterPage(
      tester,
      _CharacterPersonsApiClient(persons: const []),
    );

    expect(find.text('声优'), findsNothing);
  });

  testWidgets(
    'character overview limits voice actors and opens the full list',
    (tester) async {
      await _pumpCharacterPage(
        tester,
        _CharacterPersonsApiClient(
          persons: const [
            CharacterPerson(
              id: 1,
              name: '声优一',
              type: 1,
              subjectId: 101,
              subjectType: 2,
              subjectName: '作品一',
              subjectNameCn: '',
              staff: '主角',
            ),
            CharacterPerson(
              id: 2,
              name: '声优二',
              type: 1,
              subjectId: 102,
              subjectType: 2,
              subjectName: '作品二',
              subjectNameCn: '',
              staff: '配角',
            ),
            CharacterPerson(
              id: 3,
              name: '声优三',
              type: 1,
              subjectId: 103,
              subjectType: 2,
              subjectName: '作品三',
              subjectNameCn: '',
              staff: '客串',
            ),
            CharacterPerson(
              id: 4,
              name: '声优四',
              type: 1,
              subjectId: 104,
              subjectType: 2,
              subjectName: '作品四',
              subjectNameCn: '',
              staff: '客串',
            ),
          ],
        ),
      );

      expect(find.byKey(const ValueKey('character_person_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('character_person_4')), findsNothing);
      expect(find.text('查看全部（4）'), findsOneWidget);

      await tester.ensureVisible(find.text('查看全部（4）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看全部（4）'));
      await tester.pumpAndSettle();

      expect(find.text('全部声优（4）'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('all_character_person_4')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'character comments display createdAt instead of missing updatedAt',
    (tester) async {
      await _pumpCharacterPage(
        tester,
        _CharacterPersonsApiClient(
          comments: [
            Comment(
              id: 1,
              content: '测试吐槽',
              rating: 0,
              spoiler: 0,
              state: 0,
              createdAt: DateTime(2020, 1, 2),
              updatedAt: DateTime.now(),
              user: const {'id': 1, 'nickname': '测试用户', 'avatar': ''},
              usable: 1,
              replies: 0,
            ),
          ],
        ),
      );

      await tester.tap(find.text('吐槽'));
      await tester.pumpAndSettle();

      expect(find.text('测试吐槽'), findsOneWidget);
      expect(find.text('#1  2020-1-2 00:00'), findsOneWidget);
      expect(find.text('2020年1月2日'), findsNothing);
      expect(find.text('刚刚'), findsNothing);
    },
  );

  testWidgets('character comments render nested replies with Rakuen style', (
    tester,
  ) async {
    final createdAt = DateTime(2020, 1, 2);
    await _pumpCharacterPage(
      tester,
      _CharacterPersonsApiClient(
        comments: [
          Comment(
            id: 10,
            content: '主吐槽',
            rating: 0,
            spoiler: 0,
            state: 0,
            createdAt: createdAt,
            updatedAt: createdAt,
            user: const {'id': 1, 'nickname': '主楼用户', 'avatar': ''},
            usable: 1,
            replies: 2,
            replyItems: [
              Comment(
                id: 11,
                content: '第一条楼中楼',
                rating: 0,
                spoiler: 0,
                state: 0,
                createdAt: createdAt,
                updatedAt: createdAt,
                user: const {'id': 2, 'nickname': '回复用户', 'avatar': ''},
                usable: 1,
                replies: 0,
              ),
              Comment(
                id: 12,
                content: '',
                rating: 0,
                spoiler: 0,
                state: 6,
                createdAt: createdAt,
                updatedAt: createdAt,
                user: const {'id': 3, 'nickname': '已删除用户', 'avatar': ''},
                usable: 0,
                replies: 0,
              ),
            ],
          ),
        ],
      ),
    );

    await tester.tap(find.text('吐槽'));
    await tester.pumpAndSettle();

    expect(find.text('2 条回复'), findsNothing);
    expect(find.byType(BangumiPostCard), findsOneWidget);
    expect(find.byType(BangumiPostBlock), findsOneWidget);
    expect(find.byKey(const ValueKey('comment_replies_10')), findsOneWidget);
    expect(find.byType(BangumiNestedReplyList), findsOneWidget);
    expect(find.byKey(const ValueKey('comment_reply_11')), findsOneWidget);
    expect(find.text('第一条楼中楼'), findsOneWidget);
    expect(find.text('回复用户', findRichText: true), findsOneWidget);
    expect(find.text('#1-1  2020-1-2 00:00'), findsOneWidget);
    expect(find.text('该回复已删除'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('comment_replies_toggle_10')),
      findsNothing,
    );
  });

  testWidgets('deleted character comment displays a placeholder', (
    tester,
  ) async {
    final createdAt = DateTime(2020, 1, 2);
    await _pumpCharacterPage(
      tester,
      _CharacterPersonsApiClient(
        comments: [
          Comment(
            id: 20,
            content: '',
            rating: 0,
            spoiler: 0,
            state: 6,
            createdAt: createdAt,
            updatedAt: createdAt,
            user: const {'id': 1, 'nickname': '已删除用户', 'avatar': ''},
            usable: 0,
            replies: 0,
          ),
        ],
      ),
    );

    await tester.tap(find.text('吐槽'));
    await tester.pumpAndSettle();

    expect(find.text('该评论已删除'), findsOneWidget);
    expect(find.text('#1  2020-1-2 00:00'), findsOneWidget);
  });
}

Future<void> _pumpCharacterPage(WidgetTester tester, ApiClient api) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.init();
  final auth = AuthProvider(api: api, storage: storage);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storage),
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: const MaterialApp(home: CharacterPage(characterId: 1)),
    ),
  );
  await tester.pumpAndSettle();
}

class _CharacterPersonsApiClient extends ApiClient {
  final bool failPersons;
  final List<CharacterPerson>? persons;
  final List<Comment> comments;

  _CharacterPersonsApiClient({
    this.failPersons = false,
    this.persons,
    this.comments = const [],
  });

  @override
  Future<Character> getCharacter(int characterId) async {
    return Character(
      id: 1,
      name: '测试角色',
      type: '角色',
      images: const [],
      comment: '角色简介',
      collects: 12,
      relation: '主角',
    );
  }

  @override
  Future<List<CharacterSubject>> getCharacterSubjects(int characterId) async {
    return const [];
  }

  @override
  Future<List<CharacterPerson>> getCharacterPersons(int characterId) async {
    if (failPersons) throw Exception('network error');
    if (persons != null) return persons!;
    return const [
      CharacterPerson(
        id: 3818,
        name: '福山潤',
        type: 1,
        subjectId: 253,
        subjectType: 2,
        subjectName: 'コードギアス 反逆のルルーシュ',
        subjectNameCn: 'Code Geass 反叛的鲁路修',
        staff: '主角',
      ),
      CharacterPerson(
        id: 3818,
        name: '福山潤',
        type: 1,
        subjectId: 999,
        subjectType: 4,
        subjectName: 'きららファンタジア',
        subjectNameCn: '闪耀幻想曲',
        staff: '配角',
      ),
    ];
  }

  @override
  Future<PagedResult<Comment>> getCharacterComments({
    required int characterId,
    int limit = 30,
    int offset = 0,
  }) async {
    return PagedResult(
      total: comments.length,
      limit: limit,
      offset: offset,
      data: comments,
    );
  }

  @override
  Future<PersonDetail> getPerson(int personId) async {
    return const PersonDetail(
      id: 3818,
      name: '人物详情',
      type: 1,
      career: ['seiyu'],
      summary: '人物简介',
    );
  }

  @override
  Future<List<PersonSubject>> getPersonSubjects(int personId) async {
    return const [];
  }

  @override
  Future<List<PersonCharacter>> getPersonCharacters(int personId) async {
    return const [];
  }
}
