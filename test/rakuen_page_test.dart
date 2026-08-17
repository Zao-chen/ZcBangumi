import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/rakuen_topic.dart';
import 'package:zc_bangumi/pages/rakuen_page.dart';
import 'package:zc_bangumi/providers/app_state_provider.dart';
import 'package:zc_bangumi/providers/auth_provider.dart';
import 'package:zc_bangumi/providers/rakuen_favorite_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('rakuen end offers an explicit refresh that returns to the top', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final api = _RakuenPageApi();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<StorageService>.value(value: storage),
          ChangeNotifierProvider(
            create: (_) => AppStateProvider(storage: storage),
          ),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(api: api, storage: storage),
          ),
          ChangeNotifierProvider(
            create: (_) => RakuenFavoriteProvider(api: api, storage: storage),
          ),
        ],
        child: const MaterialApp(home: RakuenPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.topicRequests, 1);

    await tester.dragUntilVisible(
      find.byKey(const Key('rakuen_list_end')),
      find.byType(ListView).first,
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();

    final list = find.byType(ListView).first;
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    expect(find.text('已加载当前可见的全部讨论'), findsOneWidget);
    expect(find.byKey(const Key('rakuen_refresh_from_end')), findsOneWidget);
    expect(api.topicRequests, 1);

    await tester.tap(find.byKey(const Key('rakuen_refresh_from_end')));
    await tester.pumpAndSettle();

    expect(api.topicRequests, 2);
    expect(scrollable.position.pixels, scrollable.position.minScrollExtent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rakuen refreshes after an armed bottom pull is released', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final api = _RakuenPageApi();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<StorageService>.value(value: storage),
          ChangeNotifierProvider(
            create: (_) => AppStateProvider(storage: storage),
          ),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(api: api, storage: storage),
          ),
          ChangeNotifierProvider(
            create: (_) => RakuenFavoriteProvider(api: api, storage: storage),
          ),
        ],
        child: const MaterialApp(home: RakuenPage()),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byType(ListView).first;
    await tester.dragUntilVisible(
      find.byKey(const Key('rakuen_list_end')),
      list,
      const Offset(0, -600),
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();

    final gesture = await tester.startGesture(tester.getCenter(list));
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();

    expect(find.text('松开刷新'), findsOneWidget);
    expect(api.topicRequests, 1);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(api.topicRequests, 2);
    expect(scrollable.position.pixels, scrollable.position.minScrollExtent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rakuen refreshes when desktop scroll continues at the end', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final api = _RakuenPageApi();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<StorageService>.value(value: storage),
          ChangeNotifierProvider(
            create: (_) => AppStateProvider(storage: storage),
          ),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(api: api, storage: storage),
          ),
          ChangeNotifierProvider(
            create: (_) => RakuenFavoriteProvider(api: api, storage: storage),
          ),
        ],
        child: const MaterialApp(home: RakuenPage()),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byType(ListView).first;
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.topicRequests, 2);
    expect(scrollable.position.pixels, scrollable.position.minScrollExtent);

    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    await tester.tap(find.byTooltip('回到顶部并刷新当前分区'));
    await tester.pumpAndSettle();

    expect(api.topicRequests, 3);
    expect(scrollable.position.pixels, scrollable.position.minScrollExtent);
    expect(tester.takeException(), isNull);
  });
}

class _RakuenPageApi extends ApiClient {
  int topicRequests = 0;

  @override
  Future<List<RakuenTopic>> getRakuenTopics({
    String? type,
    String? filter,
  }) async {
    topicRequests += 1;
    return List.generate(
      40,
      (index) => RakuenTopic(
        id: 'group_$index',
        type: 'group',
        title: '测试帖子 $index',
        topicUrl: 'https://bgm.tv/group/topic/$index',
        avatarUrl: '',
        replyCount: index,
        timeText: '${index + 1}m ago',
      ),
    );
  }
}
