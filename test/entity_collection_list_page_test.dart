import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/bangumi_index.dart';
import 'package:zc_bangumi/models/collection.dart';
import 'package:zc_bangumi/models/user.dart';
import 'package:zc_bangumi/pages/profile_page.dart';
import 'package:zc_bangumi/providers/app_state_provider.dart';
import 'package:zc_bangumi/providers/auth_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/storage_service.dart';
import 'package:zc_bangumi/widgets/entity_collection_list_view.dart';

void main() {
  testWidgets(
    'switches between character and person collections and searches',
    (tester) async {
      final storage = await _createStorage();
      final api = _EntityCollectionApiClient();

      await _pumpPage(
        tester,
        storage: storage,
        api: api,
        child: _entityCollectionHost(EntityCollectionKind.character),
      );

      expect(
        find.byKey(const ValueKey('entity_collection_character_10')),
        findsOneWidget,
      );
      expect(find.text('测试角色'), findsOneWidget);
      expect(find.text('角色收藏 · 1'), findsNothing);
      expect(api.characterRequests, 1);
      expect(api.personRequests, 0);

      await _pumpPage(
        tester,
        storage: storage,
        api: api,
        child: _entityCollectionHost(EntityCollectionKind.person),
      );

      expect(
        find.byKey(const ValueKey('entity_collection_person_20')),
        findsOneWidget,
      );
      expect(find.text('测试人物'), findsOneWidget);
      expect(find.text('声优'), findsOneWidget);
      expect(find.text('人物收藏 · 1'), findsNothing);
      expect(api.personRequests, 1);

      await tester.enterText(
        find.byKey(const ValueKey('entity_collection_search')),
        '不存在',
      );
      await tester.pumpAndSettle();

      expect(find.text('没有找到相关收藏'), findsOneWidget);
    },
  );

  testWidgets('keeps cached collections visible when refresh fails', (
    tester,
  ) async {
    final storage = await _createStorage();
    await storage.setCache('entity_collections_alice_character', [
      UserCharacterCollection(
        id: 30,
        name: '缓存角色',
        type: 1,
        createdAt: DateTime.utc(2026, 7, 1),
      ).toJson(),
    ]);

    await _pumpPage(
      tester,
      storage: storage,
      api: _FailingEntityCollectionApiClient(),
      child: _entityCollectionHost(EntityCollectionKind.character),
    );

    expect(find.text('缓存角色'), findsOneWidget);
    expect(find.textContaining('加载失败'), findsNothing);
  });

  testWidgets('user profile switches entity collections inline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = await _createStorage();
    final appState = AppStateProvider(storage: storage);
    final api = _ProfileApiClient();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StorageService>.value(value: storage),
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider<AppStateProvider>.value(value: appState),
          ChangeNotifierProvider<AuthProvider>.value(
            value: AuthProvider(api: api, storage: storage),
          ),
        ],
        child: const MaterialApp(home: OtherUserProfilePage(username: 'alice')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('profile_collection_destination_bar')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('profile_character_collections')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile_person_collections')),
      findsOneWidget,
    );
    expect(
      tester.widget(
        find.byKey(const ValueKey('profile_character_collections')),
      ),
      isA<ChoiceChip>(),
    );
    expect(
      tester.widget(find.byKey(const ValueKey('profile_person_collections'))),
      isA<ChoiceChip>(),
    );
    expect(find.byType(VerticalDivider), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('profile_index_collection_chip_divider')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('profile_person_collections')));
    await tester.pumpAndSettle();

    expect(find.text('角色与人物收藏'), findsNothing);
    expect(find.text('Alice的收藏'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('entity_collection_person_20')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('profile_person_collections')),
          )
          .selected,
      isTrue,
    );
    expect(api.personRequests, 1);

    await tester.tap(
      find.byKey(const ValueKey('profile_character_collections')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('entity_collection_character_10')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('profile_index_collections')));
    await tester.pumpAndSettle();

    expect(find.text('创建的'), findsOneWidget);
    expect(find.text('收藏的'), findsOneWidget);
    expect(api.createdIndexRequests, 1);

    await tester.tap(find.text('收藏的'));
    await tester.pumpAndSettle();

    expect(api.collectedIndexRequests, 1);
  });

  testWidgets('landscape profile rail switches entity collections inline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = await _createStorage();
    final appState = AppStateProvider(storage: storage);
    final api = _ProfileApiClient();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StorageService>.value(value: storage),
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider<AppStateProvider>.value(value: appState),
          ChangeNotifierProvider<AuthProvider>.value(
            value: AuthProvider(api: api, storage: storage),
          ),
        ],
        child: const MaterialApp(home: OtherUserProfilePage(username: 'alice')),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget(
        find.byKey(const ValueKey('profile_character_collections')),
      ),
      isA<Icon>(),
    );
    expect(
      tester.widget(find.byKey(const ValueKey('profile_index_collections'))),
      isA<Icon>(),
    );
    expect(
      find.byKey(const ValueKey('profile_entity_collection_section_divider')),
      findsOneWidget,
    );
    final dividerRect = tester.getRect(
      find.byKey(const ValueKey('profile_entity_collection_section_divider')),
    );
    final characterIconRect = tester.getRect(
      find.byKey(const ValueKey('profile_character_collections')),
    );
    expect(dividerRect.bottom, lessThan(characterIconRect.top));
    final indexDividerRect = tester.getRect(
      find.byKey(const ValueKey('profile_index_collection_section_divider')),
    );
    final personIconRect = tester.getRect(
      find.byKey(const ValueKey('profile_person_collections')),
    );
    final indexIconRect = tester.getRect(
      find.byKey(const ValueKey('profile_index_collections')),
    );
    expect(indexDividerRect.top, greaterThan(personIconRect.bottom));
    expect(indexDividerRect.bottom, lessThan(indexIconRect.top));

    await tester.tap(find.byKey(const ValueKey('profile_person_collections')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      6,
    );
    expect(
      find.byKey(const ValueKey('entity_collection_person_20')),
      findsOneWidget,
    );
    expect(find.text('角色与人物收藏'), findsNothing);
  });
}

Widget _entityCollectionHost(EntityCollectionKind kind) {
  return Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: EntityCollectionListView(username: 'alice', kind: kind),
    ),
  );
}

Future<StorageService> _createStorage() async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.init();
  return storage;
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required StorageService storage,
  required ApiClient api,
  required Widget child,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storage),
        Provider<ApiClient>.value(value: api),
      ],
      child: MaterialApp(home: child),
    ),
  );
  await tester.pumpAndSettle();
}

class _EntityCollectionApiClient extends ApiClient {
  int characterRequests = 0;
  int personRequests = 0;

  @override
  Future<PagedResult<UserCharacterCollection>> getUserCharacterCollections({
    required String username,
    int limit = 30,
    int offset = 0,
  }) async {
    characterRequests++;
    return PagedResult(
      total: 1,
      limit: limit,
      offset: offset,
      data: [
        UserCharacterCollection(
          id: 10,
          name: '测试角色',
          type: 1,
          createdAt: DateTime.utc(2026, 7, 15),
        ),
      ],
    );
  }

  @override
  Future<PagedResult<UserPersonCollection>> getUserPersonCollections({
    required String username,
    int limit = 30,
    int offset = 0,
  }) async {
    personRequests++;
    return PagedResult(
      total: 1,
      limit: limit,
      offset: offset,
      data: [
        UserPersonCollection(
          id: 20,
          name: '测试人物',
          type: 1,
          career: const ['seiyu'],
          createdAt: DateTime.utc(2026, 7, 16),
        ),
      ],
    );
  }
}

class _FailingEntityCollectionApiClient extends ApiClient {
  @override
  Future<PagedResult<UserCharacterCollection>> getUserCharacterCollections({
    required String username,
    int limit = 30,
    int offset = 0,
  }) {
    throw Exception('network error');
  }
}

class _ProfileApiClient extends _EntityCollectionApiClient {
  int createdIndexRequests = 0;
  int collectedIndexRequests = 0;

  @override
  Future<BangumiUser> getUser(String username) async {
    return BangumiUser(
      id: 1,
      username: username,
      nickname: 'Alice',
      avatar: UserAvatar(large: '', medium: '', small: ''),
      sign: '',
      userGroup: 10,
    );
  }

  @override
  Future<PagedResult<UserCollection>> getUserCollections({
    required String username,
    int? subjectType,
    int? collectionType,
    int limit = 30,
    int offset = 0,
  }) async {
    return PagedResult(total: 0, limit: limit, offset: offset, data: const []);
  }

  @override
  Future<PagedResult<BangumiIndexSummary>> getUserCreatedIndexes({
    required String username,
    int limit = 30,
    int offset = 0,
  }) async {
    createdIndexRequests++;
    return PagedResult(total: 0, limit: limit, offset: offset, data: const []);
  }

  @override
  Future<PagedResult<BangumiIndexSummary>> getUserCollectedIndexes({
    required String username,
    int limit = 30,
    int offset = 0,
  }) async {
    collectedIndexRequests++;
    return PagedResult(total: 0, limit: limit, offset: offset, data: const []);
  }
}
