import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/subject.dart';
import 'package:zc_bangumi/models/subject_search.dart';
import 'package:zc_bangumi/models/subject_tag_query.dart';
import 'package:zc_bangumi/models/unified_search.dart';
import 'package:zc_bangumi/services/storage_service.dart';

void main() {
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
  });

  test('splits and deduplicates tags without splitting spaces', () {
    expect(parseSubjectTags(' 治愈，校园,治愈\n Science Fiction, '), [
      '治愈',
      '校园',
      'Science Fiction',
    ]);
  });

  test('query round-trip retains all API search criteria', () {
    final query = SubjectTagQuery(
      subjectType: 4,
      keyword: '测试游戏',
      sort: SubjectSearchSort.score,
      options: UnifiedSearchOptions(
        tags: const ['剧情', '恋爱'],
        metaTags: const ['原创', '-科幻'],
        airDateFrom: DateTime(2020),
        airDateTo: DateTime(2025, 12, 31),
        ratingMin: 7.5,
        ratingMax: 9,
        ratingCountMin: 100,
        ratingCountMax: 3000,
        rankMin: 1,
        rankMax: 500,
        nsfwMode: SearchNsfwMode.safeOnly,
      ),
    );
    final restored = SubjectTagQuery.fromJson(query.toJson());
    expect(restored.toJson(), query.toJson());
    expect(restored.filter.toJson(), {
      'type': [4],
      'meta_tags': ['原创', '-科幻'],
      'tag': ['剧情', '恋爱'],
      'air_date': ['>=2020-01-01', '<=2025-12-31'],
      'rating': ['>=7.5', '<=9'],
      'rating_count': ['>=100', '<=3000'],
      'rank': ['>=1', '<=500'],
      'nsfw': false,
    });
    expect(restored.withTags(['剧情']).options.ratingCountMin, 100);
    expect(restored.copyWith(clearSubjectType: true).filter.types, isEmpty);
  });

  test('identity ignores tag order but preserves type and sort', () {
    final query = const SubjectTagQuery().withTags(['治愈', '校园']);
    expect(query.identity, query.withTags([' 校园 ', '治愈', '治愈']).identity);
    expect(query.identity, isNot(query.copyWith(subjectType: 4).identity));
    expect(
      query.identity,
      isNot(query.copyWith(sort: SubjectSearchSort.rank).identity),
    );
  });

  test(
    'recent searches are deduplicated, newest first and limited to 20',
    () async {
      for (var index = 0; index < 25; index++) {
        await storage.recordTagSearch(
          const SubjectTagQuery().withTags(['标签$index']),
        );
      }
      expect(storage.recentTagSearches, hasLength(20));
      expect(storage.recentTagSearches.first.options.tags, ['标签24']);
      await storage.recordTagSearch(const SubjectTagQuery().withTags(['标签10']));
      expect(storage.recentTagSearches, hasLength(20));
      expect(storage.recentTagSearches.first.options.tags, ['标签10']);
      await storage.clearRecentTagSearches();
      expect(storage.recentTagSearches, isEmpty);
    },
  );

  test(
    'favorite searches survive reinitialization independently of history',
    () async {
      final query = const SubjectTagQuery(subjectType: 4).withTags(['剧情']);
      await storage.toggleFavoriteTagSearch(query);
      await storage.recordTagSearch(query);
      await storage.clearRecentTagSearches();
      final restoredStorage = StorageService();
      await restoredStorage.init();
      expect(
        restoredStorage.favoriteTagSearches.single.identity,
        query.identity,
      );
      expect(restoredStorage.recentTagSearches, isEmpty);
      await restoredStorage.toggleFavoriteTagSearch(query);
      expect(restoredStorage.favoriteTagSearches, isEmpty);
    },
  );

  test('corrupt saved entries do not discard valid queries', () async {
    final query = const SubjectTagQuery().withTags(['治愈']);
    SharedPreferences.setMockInitialValues({
      'subject_tag_recent_v1': [
        'invalid json',
        jsonEncode({'sort': 'invalid'}),
        jsonEncode(query.toJson()),
        jsonEncode({...query.toJson(), 'subject_type': 99}),
      ],
    });
    final restoredStorage = StorageService();
    await restoredStorage.init();
    expect(restoredStorage.recentTagSearches.single.identity, query.identity);
  });

  test('subject cache round-trip keeps dates, tags and distinct counts', () {
    final subject = Subject.fromJson({
      'id': 1,
      'type': 2,
      'date': '2024-04-01',
      'rating': {'score': 8, 'rank': 12, 'total': 50},
      'collection': {'wish': 20, 'collect': 60},
      'tags': [
        {'name': '治愈', 'count': 10, 'total_count': 10000},
        {'name': '治愈'},
        '校园',
        {'name': null},
      ],
    });
    final slim = SlimSubject.fromSubject(subject);
    final cached = SlimSubject.fromJson(slim.toJson());
    expect(cached.ratingTotal, 50);
    expect(cached.collectionTotal, 80);
    expect(cached.tags, ['治愈', '校园']);
    expect(cached.date, '2024-04-01');
    final restored = Subject.fromSlimSubject(cached);
    expect(restored.date, cached.date);
    expect(restored.tags, cached.tags);
    expect(Subject.fromJson(subject.toJson()).ratingTotal, 50);
    expect(SlimSubject.fromJson({'id': 1, 'type': 2}).tags, isEmpty);
  });
}
