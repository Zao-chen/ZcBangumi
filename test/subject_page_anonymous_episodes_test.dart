import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/character.dart';
import 'package:zc_bangumi/models/comment.dart';
import 'package:zc_bangumi/models/episode.dart';
import 'package:zc_bangumi/models/person.dart';
import 'package:zc_bangumi/models/subject.dart';
import 'package:zc_bangumi/pages/subject_page.dart';
import 'package:zc_bangumi/providers/app_state_provider.dart';
import 'package:zc_bangumi/providers/auth_provider.dart';
import 'package:zc_bangumi/providers/connectivity_provider.dart';
import 'package:zc_bangumi/providers/mikan_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/mikan_service.dart';
import 'package:zc_bangumi/services/storage_service.dart';

void main() {
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
