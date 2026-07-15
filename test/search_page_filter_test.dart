import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/subject.dart';
import 'package:zc_bangumi/models/subject_search.dart';
import 'package:zc_bangumi/pages/search_page.dart';
import 'package:zc_bangumi/providers/auth_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/storage_service.dart';

void main() {
  testWidgets('advanced search filters are visible and retain applied values', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SearchPage()));

    final searchRect = tester.getRect(
      find.byKey(const Key('search_query_field')),
    );
    final filterButtonRect = tester.getRect(
      find.byKey(const Key('search_advanced_filter_button')),
    );
    expect(filterButtonRect.left, greaterThan(searchRect.right));
    expect(filterButtonRect.center.dy, closeTo(searchRect.center.dy, 1));

    await tester.tap(find.byKey(const Key('search_advanced_filter_button')));
    await tester.pumpAndSettle();

    final drawerRect = tester.getRect(
      find.byKey(const Key('search_filter_drawer')),
    );
    expect(drawerRect.width, lessThanOrEqualTo(380));
    expect(drawerRect.right, closeTo(788, 1));
    expect(find.text('筛选与排序'), findsOneWidget);
    expect(find.text('排序'), findsOneWidget);
    expect(find.text('公共标签（维基标签）'), findsOneWidget);
    expect(find.text('用户标签'), findsOneWidget);
    expect(find.text('播出／发售日期'), findsOneWidget);
    expect(find.text('评分范围（0–10）'), findsOneWidget);
    expect(find.text('评分人数'), findsOneWidget);
    expect(find.text('排名范围'), findsOneWidget);
    expect(find.text('NSFW'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('search_meta_tags_field')),
      '原创, 童年',
    );
    await tester.enterText(find.byKey(const Key('search_tags_field')), '科幻');

    final applyButton = find.byKey(const Key('search_apply_filters_button'));
    await tester.ensureVisible(applyButton);
    await tester.tap(applyButton);
    await tester.pumpAndSettle();

    expect(find.byTooltip('筛选与排序（已自定义）'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('2')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('search_advanced_filter_button')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('search_meta_tags_field')))
          .controller!
          .text,
      '原创, 童年',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('search_tags_field')))
          .controller!
          .text,
      '科幻',
    );
  });

  testWidgets('applied advanced filters are sent to the official search API', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final api = _RecordingSearchApiClient();
    final auth = AuthProvider(api: api, storage: storage);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: const MaterialApp(home: SearchPage()),
      ),
    );

    await tester.tap(find.byKey(const Key('search_advanced_filter_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('匹配程度'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏热度').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('search_meta_tags_field')),
      '原创, 童年',
    );
    await tester.enterText(find.byKey(const Key('search_tags_field')), '科幻');
    final applyButton = find.byKey(const Key('search_apply_filters_button'));
    await tester.ensureVisible(applyButton);
    await tester.tap(applyButton);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('search_query_field')), '星际牛仔');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(api.keyword, '星际牛仔');
    expect(api.filter?.metaTags, ['原创', '童年']);
    expect(api.filter?.tags, ['科幻']);
    expect(api.filter?.types, isEmpty);
    expect(api.sort, SubjectSearchSort.heat);
  });
}

class _RecordingSearchApiClient extends ApiClient {
  String? keyword;
  SubjectSearchSort? sort;
  SubjectSearchFilter? filter;

  @override
  Future<PagedResult<SlimSubject>> searchSubjects({
    required String keyword,
    SubjectSearchSort sort = SubjectSearchSort.match,
    SubjectSearchFilter filter = const SubjectSearchFilter(),
    int limit = 30,
    int offset = 0,
  }) async {
    this.keyword = keyword;
    this.sort = sort;
    this.filter = filter;
    return PagedResult<SlimSubject>(
      total: 0,
      limit: limit,
      offset: offset,
      data: const [],
    );
  }
}
