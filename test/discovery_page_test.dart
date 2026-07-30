import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/constants.dart';
import 'package:zc_bangumi/models/calendar.dart';
import 'package:zc_bangumi/models/rakuen_topic.dart';
import 'package:zc_bangumi/models/rakuen_topic_detail.dart';
import 'package:zc_bangumi/models/subject.dart';
import 'package:zc_bangumi/models/subject_browse.dart';
import 'package:zc_bangumi/pages/discovery_page.dart';
import 'package:zc_bangumi/pages/rakuen_topic_page.dart';
import 'package:zc_bangumi/pages/subject_browse_page.dart';
import 'package:zc_bangumi/providers/app_state_provider.dart';
import 'package:zc_bangumi/providers/auth_provider.dart';
import 'package:zc_bangumi/providers/discovery_provider.dart';
import 'package:zc_bangumi/providers/rakuen_favorite_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('discovery is usable without login and switches ranking type', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final api = _DiscoveryPageApi();
    final discovery = DiscoveryProvider(api: api, storage: storage);
    final appState = AppStateProvider(storage: storage);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: discovery),
          ChangeNotifierProvider.value(value: appState),
        ],
        child: const MaterialApp(home: DiscoveryPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('发现'), findsOneWidget);
    expect(find.byKey(const Key('discovery_search_entry')), findsOneWidget);
    expect(find.text('今日放送'), findsOneWidget);
    expect(find.text('测试动画'), findsWidgets);

    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    expect(find.text('热门条目'), findsOneWidget);
    await tester.tap(find.byKey(const Key('discovery_type_4')));
    await tester.pumpAndSettle();

    expect(api.requestedTypes, contains(BgmConst.subjectGame));
    expect(find.text('测试游戏'), findsOneWidget);
  });

  testWidgets('search entry opens the unified search page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) =>
                DiscoveryProvider(api: _DiscoveryPageApi(), storage: storage),
          ),
          ChangeNotifierProvider(
            create: (_) => AppStateProvider(storage: storage),
          ),
        ],
        child: const MaterialApp(home: DiscoveryPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('discovery_search_entry')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '搜索'), findsOneWidget);
  });

  testWidgets('wide discovery uses dashboard layout and supports latest sort', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.saveRecentSubjectDetail(
      Subject.fromSlimSubject(_testSubject(BgmConst.subjectAnime)),
    );
    await storage.saveRecentTopic(
      const RakuenTopic(
        id: 'group_42',
        type: 'group',
        title: '测试帖子',
        topicUrl: 'https://bgm.tv/group/topic/42',
        avatarUrl: '',
        replyCount: 3,
        timeText: '',
      ),
    );
    final api = _DiscoveryPageApi();
    final auth = AuthProvider(api: api, storage: storage);
    final favorites = RakuenFavoriteProvider(api: api, storage: storage);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<StorageService>.value(value: storage),
          ChangeNotifierProvider(
            create: (_) => DiscoveryProvider(api: api, storage: storage),
          ),
          ChangeNotifierProvider(
            create: (_) => AppStateProvider(storage: storage),
          ),
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: favorites),
        ],
        child: const MaterialApp(home: DiscoveryPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('discovery_wide_dashboard')), findsOneWidget);
    expect(find.text('最近浏览'), findsOneWidget);
    expect(find.text('测试帖子'), findsOneWidget);
    expect(find.textContaining('帖子 · 小组'), findsOneWidget);
    expect(find.text('分类浏览'), findsNothing);
    expect(find.text('本季新番'), findsOneWidget);
    expect(find.byKey(const Key('discovery_anime_tags_entry')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('最新'));
    await tester.pumpAndSettle();

    expect(api.requestedSorts, contains(SubjectBrowseSort.date));
    expect(find.text('最新条目'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('测试帖子'));
    await tester.pumpAndSettle();
    expect(find.byType(RakuenTopicPage), findsOneWidget);
    expect(find.text('测试帖子详情'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seasonal shortcut opens a prefiltered anime browser', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final api = _DiscoveryPageApi();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => DiscoveryProvider(api: api, storage: storage),
          ),
          ChangeNotifierProvider(
            create: (_) => AppStateProvider(storage: storage),
          ),
        ],
        child: const MaterialApp(home: DiscoveryPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discovery_seasonal_entry')));
    await tester.pumpAndSettle();

    final filter = api.requestedFilters.last;
    final current = DateTime.now();
    expect(find.widgetWithText(AppBar, '浏览条目'), findsOneWidget);
    expect(filter.type, BgmConst.subjectAnime);
    expect(filter.category, 1);
    expect(filter.year, current.year);
    expect(filter.month, ((current.month - 1) ~/ 3) * 3 + 1);
    expect(filter.sort, SubjectBrowseSort.date);
  });

  testWidgets('recent subjects refresh when discovery becomes visible again', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final appState = AppStateProvider(storage: storage);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) =>
                DiscoveryProvider(api: _DiscoveryPageApi(), storage: storage),
          ),
          ChangeNotifierProvider.value(value: appState),
        ],
        child: const MaterialApp(home: DiscoveryPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('最近新增'), findsNothing);

    appState.setCurrentNavIndex(1);
    await tester.pump();
    await storage.saveRecentSubjectDetail(
      Subject.fromSlimSubject(
        SlimSubject(
          id: 99,
          type: BgmConst.subjectAnime,
          name: 'Recently Viewed',
          nameCn: '最近新增',
          shortSummary: '',
          eps: 12,
          volumes: 0,
          collectionTotal: 1,
          score: 7.5,
          rank: 99,
        ),
      ),
    );
    appState.setCurrentNavIndex(0);
    await tester.pumpAndSettle();

    expect(find.text('最近新增'), findsOneWidget);
  });

  testWidgets(
    'compact discovery keeps recent browse without category preview',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final api = _DiscoveryPageApi();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => DiscoveryProvider(api: api, storage: storage),
            ),
            ChangeNotifierProvider(
              create: (_) => AppStateProvider(storage: storage),
            ),
          ],
          child: const MaterialApp(home: DiscoveryPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('discovery_compact_recent')), findsOneWidget);
      expect(
        find.byKey(const Key('discovery_compact_categories')),
        findsNothing,
      );
      expect(find.text('分类浏览'), findsNothing);
      expect(find.byKey(const Key('discovery_search_entry')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('subject browse renders a mobile grid and filter sheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) =>
                DiscoveryProvider(api: _DiscoveryPageApi(), storage: storage),
          ),
          ChangeNotifierProvider(
            create: (_) => AppStateProvider(storage: storage),
          ),
        ],
        child: const MaterialApp(home: SubjectBrowsePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('浏览条目'), findsOneWidget);
    expect(find.text('测试动画'), findsOneWidget);
    expect(
      find.byKey(const Key('subject_browse_filter_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('subject_browse_filter_button')));
    await tester.pumpAndSettle();
    expect(find.text('筛选'), findsOneWidget);
    expect(
      find.byKey(const Key('subject_browse_apply_filter')),
      findsOneWidget,
    );
  });

  testWidgets('subject browse ignores an older request after switching type', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final gate = Completer<void>();
    final api = _DiscoveryPageApi(browseGate: gate);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => DiscoveryProvider(api: api, storage: storage),
          ),
          ChangeNotifierProvider(
            create: (_) => AppStateProvider(storage: storage),
          ),
        ],
        child: const MaterialApp(home: SubjectBrowsePage()),
      ),
    );
    await tester.pump();
    expect(api.requestedTypes, [BgmConst.subjectAnime]);

    await tester.tap(find.byKey(const Key('subject_browse_type_4')));
    await tester.pump();
    expect(api.requestedTypes, [BgmConst.subjectAnime, BgmConst.subjectGame]);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('测试游戏'), findsOneWidget);
    expect(find.text('测试动画'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'recent history refreshes after returning from a discovery child',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final api = _DiscoveryPageApi();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => DiscoveryProvider(api: api, storage: storage),
            ),
            ChangeNotifierProvider(
              create: (_) => AppStateProvider(storage: storage),
            ),
          ],
          child: const MaterialApp(home: DiscoveryPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('子页浏览记录'), findsNothing);

      await tester.tap(find.byKey(const Key('discovery_seasonal_entry')));
      await tester.pumpAndSettle();
      await storage.saveRecentSubjectDetail(
        Subject.fromSlimSubject(
          SlimSubject(
            id: 88,
            type: BgmConst.subjectAnime,
            name: 'Child Page History',
            nameCn: '子页浏览记录',
            shortSummary: '',
            eps: 12,
            volumes: 0,
            collectionTotal: 1,
            score: 8,
            rank: 88,
          ),
        ),
      );

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('子页浏览记录'), findsOneWidget);
    },
  );

  testWidgets('calendar refresh failure keeps data and shows local retry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final api = _DiscoveryPageApi();
    final discovery = DiscoveryProvider(api: api, storage: storage);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: discovery),
          ChangeNotifierProvider(
            create: (_) => AppStateProvider(storage: storage),
          ),
        ],
        child: const MaterialApp(home: DiscoveryPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('测试动画'), findsWidgets);

    api.calendarError = StateError('offline');
    await discovery.loadCalendar(forceNetwork: true);
    await tester.pump();

    expect(find.text('每日放送刷新失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('测试动画'), findsWidgets);
  });
}

class _DiscoveryPageApi extends ApiClient {
  final List<int> requestedTypes = [];
  final List<SubjectBrowseSort> requestedSorts = [];
  final List<SubjectBrowseFilter> requestedFilters = [];
  final Completer<void>? browseGate;
  Object? calendarError;

  _DiscoveryPageApi({this.browseGate});

  @override
  Future<List<CalendarDay>> getCalendar() async {
    final failure = calendarError;
    if (failure != null) throw failure;
    return [
      CalendarDay(
        weekday: CalendarWeekday(
          en: '',
          cn: '今天',
          ja: '',
          id: DateTime.now().weekday,
        ),
        items: [
          CalendarSubject(
            id: 1,
            url: '/subject/1',
            type: BgmConst.subjectAnime,
            name: 'Test Anime',
            nameCn: '测试动画',
            summary: '',
            eps: 12,
            epsCount: 12,
            rating: CalendarRating(total: 10, score: 8),
          ),
        ],
      ),
    ];
  }

  @override
  Future<RakuenTopicDetail> getRakuenTopicDetail({
    required String topicUrl,
  }) async {
    return RakuenTopicDetail(
      title: '测试帖子详情',
      topicUrl: topicUrl,
      replies: const [],
    );
  }

  @override
  Future<PagedResult<SlimSubject>> browseSubjects({
    required SubjectBrowseFilter filter,
    int limit = 30,
    int offset = 0,
  }) async {
    requestedTypes.add(filter.type);
    requestedSorts.add(filter.sort);
    requestedFilters.add(filter);
    await browseGate?.future;
    final isGame = filter.type == BgmConst.subjectGame;
    return PagedResult(
      total: 1,
      limit: limit,
      offset: offset,
      data: [
        SlimSubject(
          id: isGame ? 2 : 1,
          type: filter.type,
          name: isGame ? 'Test Game' : 'Test Anime',
          nameCn: isGame ? '测试游戏' : '测试动画',
          shortSummary: '',
          eps: 0,
          volumes: 0,
          collectionTotal: 1,
          score: 8,
          rank: 1,
        ),
      ],
    );
  }
}

SlimSubject _testSubject(int type) => SlimSubject(
  id: 1,
  type: type,
  name: 'Test Anime',
  nameCn: '测试动画',
  shortSummary: '',
  eps: 12,
  volumes: 0,
  collectionTotal: 1,
  score: 8,
  rank: 1,
  date: '2026-07-30',
);
