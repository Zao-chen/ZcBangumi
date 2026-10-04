import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/character.dart';
import 'package:zc_bangumi/models/comment.dart';
import 'package:zc_bangumi/models/episode.dart';
import 'package:zc_bangumi/models/person.dart';
import 'package:zc_bangumi/models/subject.dart';
import 'package:zc_bangumi/models/subject_search.dart';
import 'package:zc_bangumi/models/subject_tab_config.dart';
import 'package:zc_bangumi/pages/search_page.dart';
import 'package:zc_bangumi/pages/subject_page.dart';
import 'package:zc_bangumi/providers/app_state_provider.dart';
import 'package:zc_bangumi/providers/auth_provider.dart';
import 'package:zc_bangumi/providers/connectivity_provider.dart';
import 'package:zc_bangumi/providers/mikan_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/mikan_service.dart';
import 'package:zc_bangumi/services/storage_service.dart';
import 'package:zc_bangumi/widgets/subject_action_buttons.dart';

void main() {
  for (final configuration in [
    (size: const Size(348, 640), textScale: 1.0),
    (size: const Size(280, 640), textScale: 1.0),
    (size: const Size(348, 640), textScale: 1.3),
    (size: const Size(1000, 800), textScale: 1.0),
  ]) {
    testWidgets('subject header fits content at $configuration', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final api = _HeaderSubjectApiClient();
      final auth = AuthProvider(api: api, storage: storage);
      final connectivity = ConnectivityProvider(canReachBangumi: () => true);
      final appState = AppStateProvider(storage: storage);
      final mikan = MikanProvider(service: MikanService(), storage: storage);
      addTearDown(connectivity.dispose);
      tester.view.physicalSize = configuration.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<StorageService>.value(value: storage),
            Provider<ApiClient>.value(value: api),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<ConnectivityProvider>.value(
              value: connectivity,
            ),
            ChangeNotifierProvider<AppStateProvider>.value(value: appState),
            ChangeNotifierProvider<MikanProvider>.value(value: mikan),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(configuration.textScale),
              ),
              child: child!,
            ),
            home: SubjectPage(subjectId: 253, subject: api.subject),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final header = find.ancestor(
        of: find.byType(SubjectActionButtons),
        matching: find.byType(Card),
      );
      final headerRect = tester.getRect(header);
      for (final button in [
        find.byType(OutlinedButton),
        find.byType(FilledButton),
      ]) {
        final buttonRect = tester.getRect(button);
        expect(headerRect.contains(buttonRect.topLeft), isTrue);
        expect(headerRect.contains(buttonRect.bottomRight), isTrue);
        expect(button.hitTestable(), findsOneWidget);
      }

      await tester.tap(find.text('编辑'));
      await tester.pump();
      expect(find.text('请先登录'), findsOneWidget);

      await tester.drag(find.byType(NestedScrollView), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(SliverAppBar, api.subject.displayName),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('game detail tags search games rather than animation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.setMikanEnabled(false);
    final api = _GameTagNavigationApi();
    final appState = AppStateProvider(storage: storage);
    for (final tabId in SubjectTabConfig.allTabIds) {
      if (tabId != SubjectTabConfig.overviewId) {
        appState.setSubjectTabVisible(tabId, false);
      }
    }
    final connectivity = ConnectivityProvider(canReachBangumi: () => true);
    addTearDown(connectivity.dispose);
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StorageService>.value(value: storage),
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(api: api, storage: storage),
          ),
          ChangeNotifierProvider<ConnectivityProvider>.value(
            value: connectivity,
          ),
          ChangeNotifierProvider<AppStateProvider>.value(value: appState),
          ChangeNotifierProvider(
            create: (_) =>
                MikanProvider(service: MikanService(), storage: storage),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(0.9)),
            child: child!,
          ),
          home: SubjectPage(subjectId: 1, subject: api.game),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final tag = find.text('剧情');
    await tester.ensureVisible(tag);
    await tester.tap(tag);
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);
    expect(find.widgetWithText(AppBar, '搜索'), findsOneWidget);
    expect(api.tagFilter!.types, [4]);
    expect(api.tagFilter!.tags, ['剧情']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('anonymous subject page loads public episodes as read-only', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.setMikanEnabled(false);

    final api = _AnonymousEpisodeApiClient();
    final auth = AuthProvider(api: api, storage: storage);
    final connectivity = ConnectivityProvider(canReachBangumi: () => true);
    final appState = AppStateProvider(storage: storage);
    final mikan = MikanProvider(service: MikanService(), storage: storage);

    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(connectivity.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StorageService>.value(value: storage),
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ConnectivityProvider>.value(
            value: connectivity,
          ),
          ChangeNotifierProvider<AppStateProvider>.value(value: appState),
          ChangeNotifierProvider<MikanProvider>.value(value: mikan),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(0.9)),
            child: child!,
          ),
          home: SubjectPage(subjectId: 253, subject: api.subject),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.publicEpisodeRequests, 1);
    expect(api.collectionEpisodeRequests, 0);
    expect(find.byKey(const ValueKey('episode_1001')), findsOneWidget);

    final publicCache =
        storage.getCache('subject_public_episodes_253') as List<dynamic>;
    expect(publicCache.single, containsPair('id', 1001));
    expect(storage.getCache('subject_episodes_253'), isNull);

    await tester.tap(find.byKey(const ValueKey('episode_1001')));
    await tester.pumpAndSettle();

    expect(find.text('讨论(3)'), findsOneWidget);
    expect(find.text('看过'), findsNothing);
    expect(find.text('看到'), findsNothing);
    expect(find.text('想看'), findsNothing);
    expect(find.text('抛弃'), findsNothing);
  });

  testWidgets('subject comments API failure is not shown as an empty list', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.setMikanEnabled(false);

    final api = _FailingCommentsApiClient();
    final auth = AuthProvider(api: api, storage: storage);
    final connectivity = ConnectivityProvider(canReachBangumi: () => true);
    final appState = AppStateProvider(storage: storage);
    final mikan = MikanProvider(service: MikanService(), storage: storage);

    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(connectivity.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StorageService>.value(value: storage),
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ConnectivityProvider>.value(
            value: connectivity,
          ),
          ChangeNotifierProvider<AppStateProvider>.value(value: appState),
          ChangeNotifierProvider<MikanProvider>.value(value: mikan),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(0.9)),
            child: child!,
          ),
          home: SubjectPage(subjectId: 253, subject: api.subject),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('吐槽'));
    await tester.pumpAndSettle();

    expect(find.text('吐槽加载失败'), findsOneWidget);
    expect(find.text('获取吐槽失败，请稍后重试'), findsOneWidget);
    expect(find.text('暂无吐槽'), findsNothing);
    expect(find.text('重试'), findsOneWidget);
  });
}

class _AnonymousEpisodeApiClient extends ApiClient {
  int publicEpisodeRequests = 0;
  int collectionEpisodeRequests = 0;

  final Subject subject = Subject(
    id: 253,
    type: 2,
    name: '星际牛仔',
    nameCn: '星际牛仔',
    summary: '测试简介',
    eps: 1,
    volumes: 0,
    score: 8.9,
    rank: 2,
    collectionTotal: 100,
    date: '1998-04-03',
    tags: const [],
    infobox: const {},
  );

  @override
  Future<Subject> getSubject(int subjectId) async => subject;

  @override
  Future<List<Character>> getSubjectCharacters(int subjectId) async => const [];

  @override
  Future<List<RelatedPerson>> getSubjectPersons(int subjectId) async =>
      const [];

  @override
  Future<List<RelatedSubject>> getSubjectRelations(int subjectId) async =>
      const [];

  @override
  Future<PagedResult<Comment>> getSubjectComments({
    required int subjectId,
    int limit = 30,
    int offset = 0,
  }) async {
    return PagedResult<Comment>(
      total: 0,
      limit: limit,
      offset: offset,
      data: const [],
    );
  }

  @override
  Future<PagedResult<Episode>> getEpisodes({
    required int subjectId,
    int? type,
    int limit = 200,
    int offset = 0,
  }) async {
    publicEpisodeRequests++;
    return PagedResult<Episode>(
      total: 1,
      limit: limit,
      offset: offset,
      data: [
        Episode(
          id: 1001,
          type: 0,
          name: 'Asteroid Blues',
          nameCn: '第一集',
          sort: 1,
          ep: 1,
          airdate: '1998-04-03',
          comment: 3,
          duration: '24m',
          desc: '测试章节',
          disc: 0,
        ),
      ],
    );
  }

  @override
  Future<PagedResult<UserEpisodeCollection>> getUserEpisodeCollections({
    required int subjectId,
    int limit = 200,
    int offset = 0,
  }) async {
    collectionEpisodeRequests++;
    throw StateError('anonymous users must not request collection progress');
  }
}

class _HeaderSubjectApiClient extends _AnonymousEpisodeApiClient {
  final _headerSubject = Subject.fromJson({
    'id': 253,
    'type': 2,
    'name': 'きみが死ぬまで恋をしたい',
    'name_cn': '与你相恋到生命尽头',
    'summary': '测试简介' * 100,
    'rating': {'score': 6.6, 'rank': 4392},
    'collection_total': 14295,
  });

  @override
  Subject get subject => _headerSubject;
}

class _FailingCommentsApiClient extends _AnonymousEpisodeApiClient {
  @override
  Future<PagedResult<Comment>> getSubjectComments({
    required int subjectId,
    int limit = 30,
    int offset = 0,
  }) async {
    throw StateError('P1 comments failed');
  }
}

class _GameTagNavigationApi extends _AnonymousEpisodeApiClient {
  final game = Subject.fromJson({
    'id': 1,
    'type': 4,
    'name': '测试游戏',
    'tags': ['剧情'],
  });
  SubjectSearchFilter? tagFilter;

  @override
  Future<Subject> getSubject(int subjectId) async => game;

  @override
  Future<PagedResult<SlimSubject>> searchSubjects({
    required String keyword,
    SubjectSearchSort sort = SubjectSearchSort.match,
    SubjectSearchFilter filter = const SubjectSearchFilter(),
    int limit = 30,
    int offset = 0,
  }) async {
    tagFilter = filter;
    return PagedResult(total: 0, limit: limit, offset: offset, data: const []);
  }
}
