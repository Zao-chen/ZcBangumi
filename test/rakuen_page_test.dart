import 'package:flutter/material.dart';
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

  testWidgets('rakuen stops at the end of the current topic window', (
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

    expect(find.text('已加载当前可见的全部讨论'), findsOneWidget);
    expect(api.topicRequests, 1);
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
