import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/subject_search.dart';
import 'package:zc_bangumi/models/subject_tag_query.dart';
import 'package:zc_bangumi/models/unified_search.dart';
import 'package:zc_bangumi/pages/subject_tag_page.dart';
import 'package:zc_bangumi/providers/app_state_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/storage_service.dart';
import 'package:zc_bangumi/widgets/search_result_cards.dart';

import 'helpers/subject_tag_test_helpers.dart';

void main() {
  late StorageService storage;
  late TagSearchTestApi api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
    api = TagSearchTestApi();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    String? tag,
    int? type = 2,
    AppStateProvider? appState,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<StorageService>.value(value: storage),
          if (appState != null) ChangeNotifierProvider.value(value: appState),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
          home: SubjectTagPage(initialTag: tag, initialSubjectType: type),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('home uses local common tags and does not request a website', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.widgetWithText(AppBar, '动画标签'), findsOneWidget);
    expect(find.text('常用标签'), findsOneWidget);
    expect(find.textContaining('不是 Bangumi 全站标签目录'), findsOneWidget);
    expect(api.calls, isEmpty);
    expect(find.text('日期'), findsNothing);
    expect(find.text('名称'), findsNothing);
  });

  testWidgets('initial tag preserves its exact name and source subject type', (
    tester,
  ) async {
    await pumpPage(tester, tag: ' Science Fiction ', type: 4);
    expect(find.widgetWithText(AppBar, '游戏标签'), findsOneWidget);
    expect(api.calls.single.filter.types, [4]);
    expect(api.calls.single.filter.tags, ['Science Fiction']);
    expect(api.calls.single.keyword, '');
    expect(api.calls.single.sort, SubjectSearchSort.heat);
    await tester.ensureVisible(find.text('测试条目'));
    expect(find.text('测试条目'), findsOneWidget);
    expect(find.textContaining('50 人评分'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tag input supports multiple tags, keyword and API sort', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.enterText(find.byKey(const Key('tag_input')), '治愈，校园, 治愈');
    await tester.enterText(find.byKey(const Key('tag_keyword_input')), ' 测试 ');
    await tester.tap(find.byKey(const Key('tag_search_submit')));
    await tester.pumpAndSettle();
    expect(api.calls.single.filter.tags, ['治愈', '校园']);
    expect(api.calls.single.keyword, '测试');
    await tester.ensureVisible(find.byKey(const Key('tag_sort_score')));
    await tester.tap(find.byKey(const Key('tag_sort_score')));
    await tester.pumpAndSettle();
    expect(api.calls.last.sort, SubjectSearchSort.score);
    expect(api.calls.last.filter.tags, ['治愈', '校园']);
  });

  testWidgets('advanced filters preserve tags and are sent without a keyword', (
    tester,
  ) async {
    await pumpPage(tester, tag: '治愈');
    await tester.tap(find.byKey(const Key('tag_filter_button')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('search_tags_field')))
          .controller!
          .text,
      '治愈',
    );
    await tester.enterText(
      find.byKey(const Key('search_meta_tags_field')),
      '原创, -科幻',
    );
    final minRatingCount = find.widgetWithText(TextField, '最小值').at(1);
    await tester.ensureVisible(minRatingCount);
    await tester.enterText(minRatingCount, '100');
    final apply = find.byKey(const Key('search_apply_filters_button'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(api.calls.last.keyword, '');
    expect(api.calls.last.filter.tags, ['治愈']);
    expect(api.calls.last.filter.metaTags, ['原创', '-科幻']);
    expect(api.calls.last.filter.ratingCounts, ['>=100']);
    await tester.tap(find.byKey(const Key('tag_filter_button')));
    await tester.pumpAndSettle();
    final restored = find.widgetWithText(TextField, '最小值').at(1);
    expect(tester.widget<TextField>(restored).controller!.text, '100');
  });

  testWidgets('related tags append AND criteria and show sample counts', (
    tester,
  ) async {
    await pumpPage(tester, tag: '治愈');
    expect(find.text('相关标签（当前已加载条目）'), findsOneWidget);
    final related = find.byKey(const Key('tag_related_校园'));
    await tester.ensureVisible(related);
    await tester.tap(related);
    await tester.pumpAndSettle();
    expect(api.calls.last.filter.tags, ['治愈', '校园']);
    expect(find.byKey(const Key('tag_related_校园')), findsNothing);
  });

  testWidgets('saved searches restore type, tags, keyword, sort and filters', (
    tester,
  ) async {
    final saved = SubjectTagQuery(
      subjectType: 4,
      keyword: '测试游戏',
      sort: SubjectSearchSort.score,
      options: UnifiedSearchOptions(
        tags: const ['剧情', '恋爱'],
        ratingCountMin: 100,
        airDateFrom: DateTime(2020),
      ),
    );
    await storage.toggleFavoriteTagSearch(saved);
    await pumpPage(tester);
    expect(api.calls, isEmpty);
    final entry = find.text(saved.label);
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(api.calls.single.keyword, '测试游戏');
    expect(api.calls.single.sort, SubjectSearchSort.score);
    expect(api.calls.single.filter.types, [4]);
    expect(api.calls.single.filter.tags, ['剧情', '恋爱']);
    expect(api.calls.single.filter.ratingCounts, ['>=100']);
    expect(api.calls.single.filter.airDates, ['>=2020-01-01']);
    expect(find.byTooltip('取消收藏此筛选'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tag_home_button')));
    await tester.pumpAndSettle();
    expect(find.text('最近搜索'), findsOneWidget);
    expect(api.calls, hasLength(1));
    final clear = find.byKey(const Key('tag_clear_history'));
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(storage.recentTagSearches, isEmpty);
    expect(storage.favoriteTagSearches, hasLength(1));
  });

  testWidgets('favorite button stores the complete current query', (
    tester,
  ) async {
    await pumpPage(tester, tag: '治愈');
    await tester.tap(find.byKey(const Key('tag_save_search')));
    await tester.pumpAndSettle();
    expect(storage.favoriteTagSearches.single.options.tags, ['治愈']);
    expect(find.byTooltip('取消收藏此筛选'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tag_save_search')));
    await tester.pumpAndSettle();
    expect(storage.favoriteTagSearches, isEmpty);
  });

  testWidgets(
    'API failure has a retry action rather than an empty-state message',
    (tester) async {
      api.handler = (_) async => throw StateError('offline');
      await pumpPage(tester, tag: '治愈');
      expect(find.textContaining('标签搜索失败'), findsOneWidget);
      expect(find.textContaining('没有符合条件'), findsNothing);
      api.handler = null;
      final retry = find.text('重试');
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.textContaining('标签搜索失败'), findsNothing);
      expect(api.calls, hasLength(2));
    },
  );

  testWidgets('empty results retain input, filters and sorting controls', (
    tester,
  ) async {
    api.handler = (call) async => tagSearchPage(call, []);
    await pumpPage(tester, tag: '治愈');
    expect(find.textContaining('没有符合条件的条目'), findsOneWidget);
    expect(find.byKey(const Key('tag_input')), findsOneWidget);
    expect(find.byKey(const Key('tag_sort_rank')), findsOneWidget);
    expect(find.byKey(const Key('tag_filter_button')), findsOneWidget);
  });

  testWidgets('short result lists offer pagination and keep data on failure', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var shouldFail = true;
    api.handler = (call) async {
      if (call.offset == 0) {
        return tagSearchPage(call, [tagTestSubject()], total: 2);
      }
      if (shouldFail) throw StateError('offline');
      return tagSearchPage(call, [
        tagTestSubject(id: 2, name: '第二条目'),
      ], total: 2);
    };
    await pumpPage(tester, tag: '治愈');
    final loadMore = find.byKey(const Key('tag_load_more'));
    if (loadMore.evaluate().isNotEmpty) {
      await tester.ensureVisible(loadMore);
      await tester.pumpAndSettle();
    }
    if (find.text('重试').evaluate().isEmpty) {
      await tester.tap(loadMore);
      await tester.pumpAndSettle();
    }
    expect(find.text('测试条目'), findsOneWidget);
    expect(find.text('加载更多失败，已保留当前条目'), findsOneWidget);
    shouldFail = false;
    final retry = find.text('重试');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(api.calls.map((call) => call.offset), [0, 1, 1]);
    expect(find.text('第二条目'), findsOneWidget);
  });

  testWidgets(
    'all-type search omits type and rejects a completely empty query',
    (tester) async {
      await pumpPage(tester, type: null);
      await tester.tap(find.byKey(const Key('tag_search_submit')));
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
      expect(find.text('请输入标签、关键词或至少一项筛选条件'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('tag_input')), '治愈');
      await tester.tap(find.byKey(const Key('tag_search_submit')));
      await tester.pumpAndSettle();
      expect(api.calls.single.filter.types, isEmpty);
    },
  );

  testWidgets('sorting preserves commas in unchanged deep-linked tags', (
    tester,
  ) async {
    await pumpPage(tester, tag: '标签,含逗号');
    await tester.tap(find.byKey(const Key('tag_sort_rank')));
    await tester.pumpAndSettle();
    expect(api.calls.last.filter.tags, ['标签,含逗号']);
  });

  testWidgets('selected tags remain interactive and can be removed', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.enterText(find.byKey(const Key('tag_input')), '治愈，校园');
    await tester.tap(find.byKey(const Key('tag_search_submit')));
    await tester.pumpAndSettle();
    final chip = tester.widget<InputChip>(find.byType(InputChip).first);
    expect(chip.selected, isTrue);
    expect(chip.onSelected, isNotNull);
    await tester.tap(find.byTooltip('移除标签：校园'));
    await tester.pumpAndSettle();
    expect(api.calls.last.filter.tags, ['治愈']);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('tag_input')))
          .controller!
          .text,
      '治愈',
    );
  });

  testWidgets('removing the final all-type tag returns to an empty home', (
    tester,
  ) async {
    await pumpPage(tester, tag: '治愈', type: null);
    final remove = find.byTooltip('移除标签：治愈');
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsNothing);
    expect(find.text('常用标签'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('tag_input')))
          .controller!
          .text,
      isEmpty,
    );
    expect(api.calls, hasLength(1));
    expect(find.text('请输入标签、关键词或至少一项筛选条件'), findsNothing);
  });

  testWidgets('type-only results can switch back to the all-type home', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('tag_search_submit')));
    await tester.pumpAndSettle();
    expect(api.calls.single.filter.types, [2]);
    final dropdown = find.byKey(const Key('tag_subject_type'));
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部类型').last);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<int>>(dropdown).value, 0);
    expect(find.widgetWithText(AppBar, '全部类型标签'), findsOneWidget);
    expect(find.text('常用标签'), findsOneWidget);
    expect(api.calls, hasLength(1));
  });

  testWidgets('resetting all-type filters clears results without a request', (
    tester,
  ) async {
    await pumpPage(tester, tag: '治愈', type: null);
    await tester.tap(find.byKey(const Key('tag_filter_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置'));
    final apply = find.byKey(const Key('search_apply_filters_button'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsNothing);
    expect(find.text('常用标签'), findsOneWidget);
    expect(api.calls, hasLength(1));
  });

  for (final tag in ['标签,含逗号', '标签，含逗号']) {
    testWidgets('unchanged advanced filters preserve the literal tag $tag', (
      tester,
    ) async {
      await pumpPage(tester, tag: tag);
      await tester.tap(find.byKey(const Key('tag_filter_button')));
      await tester.pumpAndSettle();
      final apply = find.byKey(const Key('search_apply_filters_button'));
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(api.calls.last.filter.tags, [tag]);
    });
  }

  testWidgets('advanced filters preserve saved literal user and public tags', (
    tester,
  ) async {
    final saved = SubjectTagQuery(
      options: const UnifiedSearchOptions(
        tags: ['用户,完整', '第二个标签'],
        metaTags: ['公共，完整', '-另一个公共标签'],
        ratingCountMin: 100,
      ),
    );
    await storage.toggleFavoriteTagSearch(saved);
    await pumpPage(tester);
    await tester.ensureVisible(find.text(saved.label));
    await tester.tap(find.text(saved.label));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tag_filter_button')));
    await tester.pumpAndSettle();
    final minRating = find.widgetWithText(TextField, '最小值').first;
    await tester.ensureVisible(minRating);
    await tester.enterText(minRating, '8');
    final apply = find.byKey(const Key('search_apply_filters_button'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(api.calls.last.filter.tags, saved.options.tags);
    expect(api.calls.last.filter.metaTags, saved.options.metaTags);
    expect(api.calls.last.filter.ratings, ['>=8']);
    expect(api.calls.last.filter.ratingCounts, ['>=100']);
  });

  testWidgets('edited advanced tags still split and deduplicate input', (
    tester,
  ) async {
    await pumpPage(tester, tag: '原始,标签');
    await tester.tap(find.byKey(const Key('tag_filter_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('search_tags_field')),
      '治愈，校园, 治愈',
    );
    final apply = find.byKey(const Key('search_apply_filters_button'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(api.calls.last.filter.tags, ['治愈', '校园']);
  });

  testWidgets('wide results retain two columns with an odd result count', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    api.handler = (call) async => tagSearchPage(call, [
      tagTestSubject(id: 1),
      tagTestSubject(id: 2),
      tagTestSubject(id: 3),
    ]);
    await pumpPage(tester, tag: '治愈');
    final cards = find.byType(SubjectSearchResultCard);
    await tester.ensureVisible(cards.last);
    await tester.pumpAndSettle();
    expect(cards, findsNWidgets(3));
    final first = tester.getRect(cards.at(0));
    final second = tester.getRect(cards.at(1));
    final third = tester.getRect(cards.at(2));
    expect(second.top, first.top);
    expect(second.left, greaterThan(first.right));
    expect(third.left, first.left);
    expect(third.width, first.width);
    expect(third.top, greaterThan(first.bottom));
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 700), const Size(1280, 900)]) {
    for (final density in [0, 1, 2]) {
      for (final textScale in [1.0, 1.5]) {
        testWidgets(
          'long tag cards fit at ${size.width} pixels, density $density, text $textScale',
          (tester) async {
            await tester.binding.setSurfaceSize(size);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final appState = AppStateProvider(storage: storage);
            appState.setListDensityMode(density);
            const longTitle = '这是一部具有很长很长很长名称的动画作品用来检查两行标题是否可以正确完整显示在卡片中';
            api.handler = (call) async =>
                tagSearchPage(call, [tagTestSubject(name: longTitle)]);
            await pumpPage(
              tester,
              tag: '治愈',
              appState: appState,
              textScaler: TextScaler.linear(textScale),
            );
            await tester.scrollUntilVisible(
              find.text(longTitle),
              200,
              scrollable: find
                  .descendant(
                    of: find.byKey(const Key('tag_results_scroll')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.pumpAndSettle();
            expect(find.text(longTitle), findsOneWidget);
            expect(find.textContaining('50 人评分'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final size in [const Size(320, 700), const Size(1280, 900)]) {
    testWidgets(
      'tag results fit at ${size.width.toInt()} pixels with large cards',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final appState = AppStateProvider(storage: storage);
        appState.setListDensityMode(2);
        await pumpPage(tester, tag: '治愈', appState: appState);
        await tester.ensureVisible(find.text('测试条目'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
