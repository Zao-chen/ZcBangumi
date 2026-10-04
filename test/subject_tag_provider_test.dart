import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/subject.dart';
import 'package:zc_bangumi/models/subject_search.dart';
import 'package:zc_bangumi/models/subject_tag_query.dart';
import 'package:zc_bangumi/models/unified_search.dart';
import 'package:zc_bangumi/providers/subject_tag_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/storage_service.dart';

import 'helpers/subject_tag_test_helpers.dart';

void main() {
  late StorageService storage;
  late TagSearchTestApi api;
  late SubjectTagProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
    api = TagSearchTestApi();
    provider = SubjectTagProvider(api: api, storage: storage, pageSize: 2);
  });

  tearDown(() => provider.dispose());

  test('landing page and type changes require no network requests', () {
    expect(provider.hasSearched, isFalse);
    provider.showHome(query: const SubjectTagQuery(subjectType: 4));
    expect(provider.query.subjectType, 4);
    expect(api.calls, isEmpty);
  });

  test(
    'sends filter-only searches with combined criteria and source type',
    () async {
      await provider.search(
        const SubjectTagQuery(
          subjectType: 4,
          sort: SubjectSearchSort.score,
          options: UnifiedSearchOptions(
            tags: ['剧情', '恋爱'],
            metaTags: ['-科幻'],
            ratingCountMin: 100,
          ),
        ),
      );
      expect(api.calls.single.keyword, '');
      expect(api.calls.single.sort, SubjectSearchSort.score);
      expect(api.calls.single.filter.toJson(), {
        'type': [4],
        'tag': ['剧情', '恋爱'],
        'meta_tags': ['-科幻'],
        'rating_count': ['>=100'],
      });
      expect(provider.subjects, hasLength(1));
      expect(storage.recentTagSearches.single.subjectType, 4);
    },
  );

  test(
    'paginates by raw result offsets while deduplicating subjects',
    () async {
      api.handler = (call) async => call.offset == 0
          ? tagSearchPage(call, [
              tagTestSubject(id: 1),
              tagTestSubject(id: 2),
            ], total: 4)
          : tagSearchPage(call, [
              tagTestSubject(id: 2),
              tagTestSubject(id: 3),
            ], total: 4);
      await provider.search(const SubjectTagQuery().withTags(['治愈']));
      expect(provider.hasMore, isTrue);
      await provider.loadMore();
      expect(api.calls.map((call) => call.offset), [0, 2]);
      expect(provider.subjects.map((subject) => subject.id), [1, 2, 3]);
      expect(provider.hasMore, isFalse);
      await provider.loadMore();
      expect(api.calls, hasLength(2));
    },
  );

  test('an empty API page stops pagination even if total is larger', () async {
    api.handler = (call) async => tagSearchPage(call, [], total: 1000);
    await provider.search(const SubjectTagQuery().withTags(['治愈']));
    expect(provider.total, 1000);
    expect(provider.hasMore, isFalse);
    expect(provider.error, isNull);
  });

  test(
    'load-more failure keeps subjects and retries the same offset',
    () async {
      var shouldFail = true;
      api.handler = (call) async {
        if (call.offset == 0) {
          return tagSearchPage(call, [
            tagTestSubject(id: 1),
            tagTestSubject(id: 2),
          ], total: 3);
        }
        if (shouldFail) throw StateError('network failure');
        return tagSearchPage(call, [tagTestSubject(id: 3)], total: 3);
      };
      await provider.search(const SubjectTagQuery().withTags(['治愈']));
      await provider.loadMore();
      expect(provider.subjects, hasLength(2));
      expect(provider.error, isNull);
      expect(provider.loadMoreError, isNotNull);
      expect(provider.loadingMore, isFalse);
      shouldFail = false;
      await provider.loadMore();
      expect(api.calls.map((call) => call.offset), [0, 2, 2]);
      expect(provider.subjects, hasLength(3));
      expect(provider.loadMoreError, isNull);
    },
  );

  test(
    'refresh failure is distinct from empty results and can be retried',
    () async {
      api.handler = (_) async => throw StateError('network failure');
      await provider.search(const SubjectTagQuery().withTags(['治愈']));
      expect(provider.error, isNotNull);
      expect(provider.loading, isFalse);
      expect(provider.recentSearches, isEmpty);
      api.handler = null;
      await provider.refresh();
      expect(provider.error, isNull);
      expect(provider.subjects, hasLength(1));
    },
  );

  test(
    'late responses cannot replace a newer search or its loading state',
    () async {
      final oldResponse = Completer<PagedResult<SlimSubject>>();
      api.handler = (call) async => call.filter.tags.contains('旧标签')
          ? oldResponse.future
          : tagSearchPage(call, [tagTestSubject(id: 2, name: '新结果')]);
      final oldSearch = provider.search(
        const SubjectTagQuery().withTags(['旧标签']),
      );
      await provider.search(const SubjectTagQuery().withTags(['新标签']));
      oldResponse.complete(
        tagSearchPage(api.calls.first, [tagTestSubject(id: 1)]),
      );
      await oldSearch;
      expect(provider.query.options.tags, ['新标签']);
      expect(provider.subjects.single.id, 2);
      expect(provider.loading, isFalse);
      expect(provider.recentSearches, hasLength(1));
    },
  );

  test('late pagination and failures do not affect a new query', () async {
    final oldPage = Completer<PagedResult<SlimSubject>>();
    api.handler = (call) async {
      if (call.offset > 0) return oldPage.future;
      return tagSearchPage(call, [tagTestSubject()], total: 3);
    };
    await provider.search(const SubjectTagQuery().withTags(['旧标签']));
    final pagination = provider.loadMore();
    await provider.search(
      const SubjectTagQuery(sort: SubjectSearchSort.rank).withTags(['新标签']),
    );
    oldPage.completeError(StateError('late error'));
    await pagination;
    expect(provider.query.sort, SubjectSearchSort.rank);
    expect(provider.loadMoreError, isNull);
    expect(provider.loadingMore, isFalse);
  });

  test('returning home invalidates in-flight requests', () async {
    final response = Completer<PagedResult<SlimSubject>>();
    api.handler = (_) => response.future;
    final request = provider.search(const SubjectTagQuery().withTags(['治愈']));
    provider.showHome();
    response.complete(tagSearchPage(api.calls.single, [tagTestSubject()]));
    await request;
    expect(provider.hasSearched, isFalse);
    expect(provider.subjects, isEmpty);
    expect(provider.recentSearches, isEmpty);
  });

  test('ignores completion after disposal', () async {
    final disposable = SubjectTagProvider(api: api, storage: storage);
    final response = Completer<PagedResult<SlimSubject>>();
    api.handler = (_) => response.future;
    final request = disposable.search(const SubjectTagQuery().withTags(['治愈']));
    disposable.dispose();
    response.complete(tagSearchPage(api.calls.single, [tagTestSubject()]));
    await request;
    expect(storage.recentTagSearches, isEmpty);
  });

  test('related counts refer only to distinct loaded subjects', () async {
    api.handler = (call) async => tagSearchPage(call, [
      tagTestSubject(id: 1, tags: ['治愈', '校园', '校园', '音乐']),
      tagTestSubject(id: 2, tags: ['治愈', '校园']),
      tagTestSubject(id: 2, tags: ['治愈', '校园']),
    ]);
    await provider.search(const SubjectTagQuery().withTags(['治愈']));
    expect(provider.relatedTags.map((tag) => tag.name), ['校园', '音乐']);
    expect(provider.relatedTags.map((tag) => tag.subjectCount), [2, 1]);
    await provider.toggleFavorite();
    expect(provider.isFavorite, isTrue);
    await provider.toggleFavorite();
    expect(provider.isFavorite, isFalse);
  });

  test('concurrent load-more calls send only one request', () async {
    final response = Completer<PagedResult<SlimSubject>>();
    api.handler = (call) async => call.offset == 0
        ? tagSearchPage(call, [tagTestSubject()], total: 3)
        : response.future;
    await provider.search(const SubjectTagQuery().withTags(['治愈']));
    final pagination = provider.loadMore();
    await provider.loadMore();
    expect(api.calls, hasLength(2));
    response.complete(
      tagSearchPage(api.calls.last, [tagTestSubject(id: 2)], total: 3),
    );
    await pagination;
  });
}
