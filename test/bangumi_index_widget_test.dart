import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/bangumi_index.dart';
import 'package:zc_bangumi/models/subject_tab_config.dart';
import 'package:zc_bangumi/models/user.dart';
import 'package:zc_bangumi/pages/index_page.dart';
import 'package:zc_bangumi/providers/auth_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/storage_service.dart';
import 'package:zc_bangumi/widgets/bangumi_index_list_view.dart';

void main() {
  test('subject directory tab defaults to immediately after related', () {
    expect(SubjectTabConfig.getById(SubjectTabConfig.indexesId)?.label, '目录');
    expect(
      SubjectTabConfig.defaultOrder.indexOf(SubjectTabConfig.indexesId),
      SubjectTabConfig.defaultOrder.indexOf(SubjectTabConfig.relatedId) + 1,
    );
  });

  testWidgets('directory card renders author, count and privacy', (
    tester,
  ) async {
    final index = BangumiIndexSummary.fromJson({
      'id': 10,
      'uid': 1,
      'user': {'nickname': 'Alice', 'username': 'alice'},
      'type': 0,
      'title': '推荐目录',
      'private': true,
      'total': 5,
      'stats': {'subject': <String, dynamic>{}},
      'createdAt': 1,
      'updatedAt': 1,
    });
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BangumiIndexCard(index: index, onTap: () => tapped = true),
        ),
      ),
    );

    expect(find.text('推荐目录'), findsOneWidget);
    expect(find.textContaining('Alice'), findsOneWidget);
    expect(find.textContaining('5 项'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);

    await tester.tap(find.text('推荐目录'));
    expect(tapped, isTrue);
  });

  testWidgets('directory card lazily fills author missing from slim response', (
    tester,
  ) async {
    final summary = BangumiIndexSummary.fromJson({
      'id': 11,
      'uid': 7,
      'type': 0,
      'title': '精简目录',
      'stats': {'subject': <String, dynamic>{}},
    });

    await tester.pumpWidget(
      Provider<ApiClient>.value(
        value: _IndexDetailApiClient(),
        child: MaterialApp(
          home: Scaffold(body: BangumiIndexCard(index: summary)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('补全作者'), findsOneWidget);
  });

  testWidgets('directory list skips an empty sparse page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final offsets = <int>[];

    await tester.pumpWidget(
      Provider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(
            body: BangumiIndexListView(
              cacheKey: 'sparse_indexes_test',
              loadPage: (limit, offset) async {
                offsets.add(offset);
                return PagedResult(
                  total: 61,
                  limit: limit,
                  offset: offset,
                  data: offset == 30
                      ? [
                          BangumiIndexSummary.fromJson({
                            'id': 30,
                            'uid': 7,
                            'user': {'username': 'alice', 'nickname': 'Alice'},
                            'type': 0,
                            'title': '第二页目录',
                            'stats': {'subject': <String, dynamic>{}},
                          }),
                        ]
                      : const [],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(offsets, [0, 30]);
    expect(find.text('第二页目录'), findsOneWidget);
  });

  testWidgets('system sync directory stays read-only for its owner', (
    tester,
  ) async {
    await _pumpIndexPage(tester, _IndexPageApiClient(system: true));

    expect(find.text('系统同步目录 · 只读'), findsOneWidget);
    expect(find.byIcon(Icons.add_link_rounded), findsNothing);
    expect(
      find.descendant(
        of: find.byType(IconButton),
        matching: find.byIcon(Icons.favorite_border_rounded),
      ),
      findsNothing,
    );
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('normal user directory exposes owner management actions', (
    tester,
  ) async {
    await _pumpIndexPage(tester, _IndexPageApiClient(system: false));

    expect(find.text('系统同步目录 · 只读'), findsNothing);
    expect(find.byIcon(Icons.add_link_rounded), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(IconButton),
        matching: find.byIcon(Icons.favorite_border_rounded),
      ),
      findsOneWidget,
    );
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
  });
}

class _IndexDetailApiClient extends ApiClient {
  @override
  Future<BangumiIndex> getBangumiIndex(int indexId) async {
    return BangumiIndex.fromJson({
      'id': indexId,
      'uid': 7,
      'user': {'username': 'filled', 'nickname': '补全作者'},
      'type': 0,
      'title': '精简目录',
      'stats': {'subject': <String, dynamic>{}},
    });
  }
}

class _IndexPageApiClient extends ApiClient {
  final bool system;

  _IndexPageApiClient({required this.system});

  @override
  Future<BangumiIndex> getBangumiIndex(int indexId) async {
    return BangumiIndex.fromJson({
      'id': indexId,
      'uid': 7,
      'user': {
        'id': 7,
        'username': 'alice',
        'nickname': 'Alice',
        'avatar': <String, dynamic>{},
      },
      'type': 0,
      'title': system ? 'ZCBangumi 帖子收藏同步' : '普通目录',
      'desc': system ? '[zc_bangumi_topic_favorites_v1]' : '',
      'private': system,
      'total': 0,
      'collects': 0,
      'stats': {'subject': <String, dynamic>{}},
    });
  }

  @override
  Future<PagedResult<BangumiIndexRelated>> getIndexRelated({
    required int indexId,
    IndexRelatedCategory? category,
    int? subjectType,
    int limit = 30,
    int offset = 0,
  }) async {
    return PagedResult(total: 0, limit: limit, offset: offset, data: const []);
  }
}

class _LoggedInIndexAuthProvider extends AuthProvider {
  _LoggedInIndexAuthProvider({required super.api, required super.storage});

  final BangumiUser _testUser = BangumiUser(
    id: 7,
    username: 'alice',
    nickname: 'Alice',
    avatar: UserAvatar(large: '', medium: '', small: ''),
    sign: '',
    userGroup: 10,
  );

  @override
  BangumiUser? get user => _testUser;

  @override
  bool get isLoggedIn => true;

  @override
  String? get username => _testUser.username;
}

Future<void> _pumpIndexPage(
  WidgetTester tester,
  _IndexPageApiClient api,
) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.init();
  final auth = _LoggedInIndexAuthProvider(api: api, storage: storage);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        Provider<StorageService>.value(value: storage),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: const MaterialApp(home: BangumiIndexPage(indexId: 42)),
    ),
  );
  await tester.pumpAndSettle();
}
