import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/constants.dart';
import 'package:zc_bangumi/models/calendar.dart';
import 'package:zc_bangumi/models/character.dart';
import 'package:zc_bangumi/models/person.dart';
import 'package:zc_bangumi/models/rakuen_topic.dart';
import 'package:zc_bangumi/models/recent_view_item.dart';
import 'package:zc_bangumi/models/subject.dart';
import 'package:zc_bangumi/models/subject_browse.dart';
import 'package:zc_bangumi/providers/discovery_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('calendar model round-trips through cache JSON', () {
    final day = _calendarDay();
    final restored = CalendarDay.fromJson(day.toJson());

    expect(restored.weekday.id, 4);
    expect(restored.items.single.displayName, '测试动画');
    expect(restored.items.single.rating?.score, 8.5);
  });

  test(
    'provider restores fresh home cache without a network request',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      await storage.setCache('discovery_calendar_v1', [
        _calendarDay().toJson(),
      ]);
      await storage.setCache('discovery_ranking_2_v1', _pageJson());
      final api = _DiscoveryApi();
      final provider = DiscoveryProvider(
        api: api,
        storage: storage,
        now: () => DateTime.now(),
      );

      await provider.initialize(rankingType: BgmConst.subjectAnime);

      expect(provider.calendar, hasLength(1));
      expect(provider.rankingFor(BgmConst.subjectAnime), hasLength(1));
      expect(api.calendarCalls, 0);
      expect(api.browseCalls, 0);
    },
  );

  test('stale browse cache is retained when refresh fails', () async {
    final old = DateTime(2025);
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.setCache(
      'discovery_browse_2_-_-__-_-_rank_30_v1',
      _pageJson(),
    );
    final api = _DiscoveryApi(error: StateError('offline'));
    final provider = DiscoveryProvider(
      api: api,
      storage: storage,
      now: () => old.add(const Duration(days: 2)),
    );

    final result = await provider.browseSubjects(
      filter: const SubjectBrowseFilter(),
      forceNetwork: true,
    );

    expect(result.fromCache, isTrue);
    expect(result.refreshError, isNotNull);
    expect(result.page.data.single.id, 1);
  });

  test('latest preview uses date sorting and reuses its fresh cache', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final api = _DiscoveryApi();
    final provider = DiscoveryProvider(api: api, storage: storage);

    await provider.loadPreview(BgmConst.subjectAnime, SubjectBrowseSort.date);
    await provider.loadPreview(BgmConst.subjectAnime, SubjectBrowseSort.date);

    expect(api.browseCalls, 1);
    expect(api.requestedSorts, [SubjectBrowseSort.date]);
    expect(
      provider.previewFor(BgmConst.subjectAnime, SubjectBrowseSort.date),
      hasLength(1),
    );
  });

  test('concurrent identical browse requests share one network call', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final gate = Completer<void>();
    final api = _DiscoveryApi(browseGate: gate);
    final provider = DiscoveryProvider(api: api, storage: storage);

    final first = provider.browseSubjects(
      filter: const SubjectBrowseFilter(),
      forceNetwork: true,
    );
    final second = provider.browseSubjects(
      filter: const SubjectBrowseFilter(),
      forceNetwork: true,
    );

    expect(api.browseCalls, 1);
    gate.complete();
    final results = await Future.wait([first, second]);

    expect(results, hasLength(2));
    expect(api.browseCalls, 1);
    expect(results.first.page.data.single.id, 1);
  });

  test('recent subjects can be refreshed and cleared', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.saveRecentSubjectDetail(Subject.fromSlimSubject(_subject()));
    final provider = DiscoveryProvider(api: _DiscoveryApi(), storage: storage);

    provider.refreshRecentItems();
    expect(provider.recentItems.single.id, '1');
    expect(provider.recentItems.single.kind, RecentViewKind.subject);

    await provider.clearRecentItems();
    expect(provider.recentItems, isEmpty);
    expect(storage.getRecentSubjectDetails(), isEmpty);
    expect(storage.getRecentViewItems(), isEmpty);
  });

  test('unified recent history mixes every supported detail type', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.saveRecentSubjectDetail(Subject.fromSlimSubject(_subject()));
    await Future<void>.delayed(const Duration(milliseconds: 2));
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
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await storage.saveRecentCharacter(
      Character(
        id: 7,
        name: '测试角色',
        type: '角色',
        images: const [],
        comment: '',
        collects: 0,
        relation: '',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await storage.saveRecentPerson(
      const PersonSummary(id: 8, name: '测试人物', type: 1),
    );

    final recent = storage.getRecentViewItems();

    expect(recent, hasLength(4));
    expect(recent.map((item) => item.kind), [
      RecentViewKind.person,
      RecentViewKind.character,
      RecentViewKind.topic,
      RecentViewKind.subject,
    ]);
    expect(recent[2].title, '测试帖子');
    expect(recent.last.kind, RecentViewKind.subject);
    expect(recent.last.title, '测试动画');
  });

  test('recent history survives service restart and cache clearing', () async {
    SharedPreferences.setMockInitialValues({});
    final firstStorage = StorageService();
    await firstStorage.init();
    await firstStorage.saveRecentTopic(
      const RakuenTopic(
        id: 'group_42',
        type: 'group',
        title: '持久化帖子',
        topicUrl: 'https://bgm.tv/group/topic/42',
        avatarUrl: '',
        replyCount: 3,
        timeText: '',
      ),
    );

    await firstStorage.clearDataCache();
    final restartedStorage = StorageService();
    await restartedStorage.init();

    final recent = restartedStorage.getRecentViewItems();
    expect(recent, hasLength(1));
    expect(recent.single.kind, RecentViewKind.topic);
    expect(recent.single.title, '持久化帖子');
  });

  test('legacy cached recent history migrates to persistent storage', () async {
    SharedPreferences.setMockInitialValues({});
    final firstStorage = StorageService();
    await firstStorage.init();
    await firstStorage.setCache('recent_view_items_v1', [
      RecentViewItem.fromPerson(
        const PersonSummary(id: 8, name: '迁移人物', type: 1),
      ).toJson(),
    ]);

    final migratedStorage = StorageService();
    await migratedStorage.init();
    await migratedStorage.clearAllCache();

    final recent = migratedStorage.getRecentViewItems();
    expect(recent, hasLength(1));
    expect(recent.single.kind, RecentViewKind.person);
    expect(recent.single.title, '迁移人物');
  });
}

Map<String, dynamic> _pageJson() => {
  'total': 1,
  'limit': 30,
  'offset': 0,
  'data': [_subject().toJson()],
};

CalendarDay _calendarDay() => CalendarDay(
  weekday: CalendarWeekday(en: 'Thu', cn: '星期四', ja: '木', id: 4),
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
      rating: CalendarRating(total: 100, score: 8.5),
      rank: 10,
    ),
  ],
);

SlimSubject _subject() => SlimSubject(
  id: 1,
  type: BgmConst.subjectAnime,
  name: 'Test Anime',
  nameCn: '测试动画',
  shortSummary: '',
  eps: 12,
  volumes: 0,
  collectionTotal: 10,
  score: 8.5,
  rank: 10,
  date: '2026-07-30',
);

class _DiscoveryApi extends ApiClient {
  final Object? error;
  final Completer<void>? browseGate;
  int calendarCalls = 0;
  int browseCalls = 0;
  final List<SubjectBrowseSort> requestedSorts = [];

  _DiscoveryApi({this.error, this.browseGate});

  @override
  Future<List<CalendarDay>> getCalendar() async {
    calendarCalls++;
    final failure = error;
    if (failure != null) throw failure;
    return [_calendarDay()];
  }

  @override
  Future<PagedResult<SlimSubject>> browseSubjects({
    required SubjectBrowseFilter filter,
    int limit = 30,
    int offset = 0,
  }) async {
    browseCalls++;
    requestedSorts.add(filter.sort);
    await browseGate?.future;
    final failure = error;
    if (failure != null) throw failure;
    return PagedResult(
      total: 1,
      limit: limit,
      offset: offset,
      data: [_subject()],
    );
  }
}
