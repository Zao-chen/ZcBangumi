import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/navigation_config.dart';
import 'package:zc_bangumi/models/subject_tab_config.dart';
import 'package:zc_bangumi/pages/character_page.dart';
import 'package:zc_bangumi/pages/person_page.dart';
import 'package:zc_bangumi/pages/subject_page.dart';
import 'package:zc_bangumi/providers/app_state_provider.dart';
import 'package:zc_bangumi/providers/auth_provider.dart';
import 'package:zc_bangumi/providers/connectivity_provider.dart';
import 'package:zc_bangumi/providers/mikan_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/internal_link_handler.dart';
import 'package:zc_bangumi/services/mikan_service.dart';
import 'package:zc_bangumi/services/platform_feature_support.dart';
import 'package:zc_bangumi/services/storage_service.dart';
import 'package:zc_bangumi/widgets/mono_detail_scaffold.dart';
import 'package:zc_bangumi/widgets/bangumi_network_image.dart';
import 'package:zc_bangumi/widgets/progress_grid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'platform capabilities preserve native features and filter web tabs',
    () {
      expect(PlatformFeatureSupport.nextApi, !kIsWeb);
      expect(PlatformFeatureSupport.comments, !kIsWeb);
      expect(PlatformFeatureSupport.indexes, !kIsWeb);
      expect(PlatformFeatureSupport.webSession, !kIsWeb);
      expect(
        PlatformFeatureSupport.supportsNavigationTab(AppNavTabId.timeline),
        !kIsWeb,
      );
      expect(
        PlatformFeatureSupport.supportsNavigationTab(AppNavTabId.discover),
        isTrue,
      );
      expect(
        PlatformFeatureSupport.subjectTabs(SubjectTabConfig.defaultOrder),
        kIsWeb
            ? SubjectTabConfig.defaultOrder
                  .where(
                    (id) =>
                        id != SubjectTabConfig.commentsId &&
                        id != SubjectTabConfig.indexesId,
                  )
                  .toList()
            : SubjectTabConfig.defaultOrder,
      );
      expect(PlatformFeatureSupport.subjectTabs([]), [
        SubjectTabConfig.overviewId,
      ]);
    },
  );

  group('Web experience', () {
    late StorageService storage;
    late ApiClient api;
    late _WebFixtureAdapter adapter;
    late AuthProvider auth;
    late AppStateProvider appState;
    late ConnectivityProvider connectivity;
    late MikanProvider mikan;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      await storage.init();
      api = ApiClient();
      adapter = _WebFixtureAdapter();
      api.dio.httpClientAdapter = adapter;
      api.nextDio.httpClientAdapter = adapter;
      api.webDio.httpClientAdapter = adapter;
      auth = AuthProvider(api: api, storage: storage);
      await auth.tryRestoreSession();
      appState = AppStateProvider(storage: storage);
      connectivity = ConnectivityProvider(canReachBangumi: () => true);
      mikan = MikanProvider(service: MikanService(), storage: storage);
    });

    tearDown(() {
      mikan.dispose();
      connectivity.dispose();
      appState.dispose();
      auth.dispose();
      api.dispose();
    });

    test('unsupported saved subject tabs fall back to overview', () {
      expect(
        PlatformFeatureSupport.subjectTabs([
          SubjectTabConfig.commentsId,
          SubjectTabConfig.indexesId,
        ]),
        [SubjectTabConfig.overviewId],
      );
    });

    testWidgets('web images use browser elements without credential headers', (
      tester,
    ) async {
      late Image image;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              image =
                  const BangumiNetworkImage(
                        imageUrl: 'https://lain.bgm.tv/pic/cover/test.jpg',
                        width: 120,
                        height: 160,
                        fit: BoxFit.cover,
                      ).build(context)
                      as Image;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final provider = image.image as NetworkImage;
      expect(provider.webHtmlElementStrategy, WebHtmlElementStrategy.prefer);
      expect(provider.headers, isNull);
      expect(image.width, 120);
      expect(image.height, 160);
      expect(image.fit, BoxFit.cover);
      expect(image.errorBuilder, isNotNull);
    });

    test('unavailable routes open on the original website', () {
      for (final link in [
        '/index/1',
        '/ep/1',
        '/blog/1',
        '/subject/topic/1',
        '/group/topic/1',
        '/rakuen/topic/subject/1',
      ]) {
        expect(
          InternalLinkHandler.handleLink(
            Uri.parse('https://bgm.tv$link'),
            null,
          ),
          InternalLinkResult.openInBrowser,
          reason: link,
        );
      }
    });

    test('P1 and website requests stop before reaching the network', () async {
      api.setToken('fixture-token');
      expect(api.nextDio.options.headers.containsKey('Authorization'), isFalse);
      await expectLater(
        api.nextDio.get('/p1/indexes/1'),
        throwsA(
          isA<DioException>().having(
            (error) => error.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      await expectLater(api.webDio.get('/'), throwsA(isA<DioException>()));
      expect(adapter.requests, isEmpty);

      await api.getSubject(1);
      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer fixture-token',
      );
      await api.dio.patch('/v0/users/-/collections/1', data: {'type': 2});
      expect(adapter.requests.last.method, 'PATCH');
      expect(adapter.requests.last.uri.host, 'api.bgm.tv');
    });

    test('web feature notice dismissal survives storage recreation', () async {
      expect(storage.webFeatureNoticeDismissed, isFalse);
      await storage.dismissWebFeatureNotice();
      final reloaded = StorageService();
      await reloaded.init();
      expect(reloaded.webFeatureNoticeDismissed, isTrue);
    });

    Future<void> showPage(WidgetTester tester, Widget page, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<StorageService>.value(value: storage),
              Provider<ApiClient>.value(value: api),
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ChangeNotifierProvider<AppStateProvider>.value(value: appState),
              ChangeNotifierProvider<ConnectivityProvider>.value(
                value: connectivity,
              ),
              ChangeNotifierProvider<MikanProvider>.value(value: mikan),
            ],
            child: MaterialApp(home: page),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      for (var attempt = 0; attempt < 30; attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();
    }

    for (final size in const [Size(390, 844), Size(1280, 900)]) {
      for (final entry in <String, Widget>{
        'subject': const SubjectPage(subjectId: 1),
        'character': const CharacterPage(characterId: 1),
        'person': const PersonPage(personId: 1),
      }.entries) {
        testWidgets(
          '${entry.key} only shows browser-supported tabs at ${size.width}px',
          (tester) async {
            await showPage(tester, entry.value, size);
            expect(find.text('概述'), findsWidgets);
            expect(find.byType(MonoDetailScaffold), findsOneWidget);
            expect(find.text('目录'), findsNothing);
            expect(find.text('吐槽'), findsNothing);
            expect(find.byTooltip('加入目录'), findsNothing);
            expect(adapter.requests, isNotEmpty);
            expect(
              adapter.requests.every(
                (request) => request.uri.host == 'api.bgm.tv',
              ),
              isTrue,
            );
            expect(
              adapter.requests.any(
                (request) => request.uri.path.contains('/comments'),
              ),
              isFalse,
            );
            expect(tester.takeException(), isNull);
            if (entry.key == 'subject') {
              expect(
                tester
                    .widget<ProgressGrid>(find.byType(ProgressGrid))
                    .onAddToIndex,
                isNull,
              );
              await tester.tap(find.text('1'));
              await tester.pumpAndSettle();
              expect(find.text('加入目录'), findsNothing);
              expect(find.text('原站讨论(0)'), findsOneWidget);
            }
          },
        );
      }
    }
  }, skip: !kIsWeb);
}

class _WebFixtureAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final requestPath = options.uri.path;
    Object payload = const [];
    if (requestPath.endsWith('/subjects/1')) {
      payload = {
        'id': 1,
        'type': 2,
        'name': 'Web fixture',
        'name_cn': '网页版测试条目',
        'summary': '测试简介',
        'eps': 1,
        'infobox': [],
        'rating': {'score': 8, 'rank': 1},
      };
    } else if (requestPath.endsWith('/characters/1')) {
      payload = {
        'id': 1,
        'type': 1,
        'name': '测试角色',
        'summary': '测试简介',
        'infobox': [],
      };
    } else if (requestPath.endsWith('/persons/1')) {
      payload = {
        'id': 1,
        'type': 1,
        'name': '测试人物',
        'summary': '测试简介',
        'infobox': [],
      };
    } else if (requestPath.endsWith('/episodes')) {
      payload = {
        'total': 1,
        'limit': 200,
        'offset': 0,
        'data': [
          {'id': 1, 'type': 0, 'sort': 1, 'name': '测试章节'},
        ],
      };
    }
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
