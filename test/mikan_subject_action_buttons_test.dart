import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/mikan.dart';
import 'package:zc_bangumi/models/subject.dart';
import 'package:zc_bangumi/providers/auth_provider.dart';
import 'package:zc_bangumi/providers/mikan_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/mikan_service.dart';
import 'package:zc_bangumi/services/storage_service.dart';
import 'package:zc_bangumi/widgets/subject_action_buttons.dart';

class _LoggedInAuthProvider extends AuthProvider {
  _LoggedInAuthProvider() : super(api: ApiClient(), storage: StorageService());

  @override
  bool get isLoggedIn => true;
}

class _FakeMikanService extends MikanService {
  final bool remoteSubscribed;

  _FakeMikanService({this.remoteSubscribed = false})
    : super(baseUrl: MikanService.defaultBaseUrl);

  @override
  Future<MikanBangumiDetail> getBangumi(String bangumiId) async {
    return MikanBangumiDetail(
      id: bangumiId,
      name: '测试动画',
      subgroupBangumis: [
        MikanSubgroupBangumi(
          dataId: '15',
          name: '字幕组',
          subscribed: remoteSubscribed,
          records: const [
            MikanRecordItem(title: '测试资源', magnet: 'magnet:?xt=urn:test'),
          ],
        ),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<StorageService> storageWithSession() async {
    final storage = StorageService();
    await storage.init();
    await storage.setMikanSession(
      MikanSession(
        username: 'tester',
        capturedAt: DateTime(2026, 5, 21),
        validatedAt: DateTime(2026, 5, 21),
        primaryHost: 'mikanani.me',
        cookies: const [
          MikanSessionCookie(
            name: 'session',
            value: 'ok',
            domain: 'mikanani.me',
            path: '/',
          ),
        ],
      ),
    );
    return storage;
  }

  Future<void> pumpEditButton(
    WidgetTester tester, {
    required Subject subject,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final mikan = MikanProvider(service: _FakeMikanService(), storage: storage);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: ApiClient()),
          Provider<StorageService>.value(value: storage),
          ChangeNotifierProvider<AuthProvider>.value(
            value: _LoggedInAuthProvider(),
          ),
          ChangeNotifierProvider<MikanProvider>.value(value: mikan),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SubjectActionButtons(
              subject: subject,
              onCollectionChanged: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
  }

  Future<MikanProvider> pumpMikanButton(
    WidgetTester tester, {
    required Subject subject,
    bool loggedIn = false,
    bool enabled = true,
    bool remoteSubscribed = false,
    MikanSubjectMapping? mapping,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final storage = loggedIn ? await storageWithSession() : StorageService();
    if (!loggedIn) {
      await storage.init();
    }
    await storage.setMikanEnabled(enabled);
    final mikan = MikanProvider(
      service: _FakeMikanService(remoteSubscribed: remoteSubscribed),
      storage: storage,
    );
    if (mapping != null) {
      await mikan.saveMapping(mapping);
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider<MikanProvider>.value(value: mikan)],
        child: MaterialApp(
          home: Scaffold(body: MikanSubscriptionButton(subject: subject)),
        ),
      ),
    );
    return mikan;
  }

  testWidgets('Mikan controls are hidden for non-anime subjects', (
    tester,
  ) async {
    await pumpEditButton(tester, subject: _subject(type: 1));

    expect(find.text('同时同步 Mikan 订阅'), findsNothing);
  });

  testWidgets('anime edit dialog keeps Mikan sync controls outside', (
    tester,
  ) async {
    await pumpEditButton(tester, subject: _subject(type: 2));

    expect(find.text('同时同步 Mikan 订阅'), findsNothing);
    expect(find.text('请先在设置中登录 Mikan'), findsNothing);
  });

  testWidgets('Mikan subscription button is hidden for non-anime subjects', (
    tester,
  ) async {
    await pumpMikanButton(tester, subject: _subject(type: 1));

    expect(find.text('Mikan'), findsNothing);
  });

  testWidgets('Mikan subscription button shows logged-out shortcut state', (
    tester,
  ) async {
    await pumpMikanButton(tester, subject: _subject(type: 2));

    expect(find.text('追番'), findsOneWidget);
  });

  testWidgets('logged-out Mikan button opens subscription dialog', (
    tester,
  ) async {
    await pumpMikanButton(
      tester,
      subject: _subject(type: 2),
      mapping: MikanSubjectMapping(
        subjectId: 12345,
        bangumiId: '681',
        bangumiName: '测试动画',
        subgroupId: '15',
        subgroupName: '字幕组',
        updatedAt: DateTime(2026, 5, 21),
      ),
    );

    await tester.tap(find.text('追番'));
    await tester.pumpAndSettle();

    expect(find.text('Mikan 订阅'), findsOneWidget);
    expect(find.text('字幕组'), findsOneWidget);
    expect(find.text('登录后订阅'), findsOneWidget);
    expect(find.text('查看资源'), findsOneWidget);
    expect(find.textContaining('Mikan 未订阅'), findsNothing);
    expect(find.text('尚未关联 Mikan 番组'), findsNothing);
    expect(find.text('更换 Mikan 番组/字幕组'), findsNothing);
    expect(find.text('订阅这个字幕组'), findsNothing);
    expect(find.text('取消订阅这个字幕组'), findsNothing);
  });

  testWidgets('Mikan subgroup row shows resources inside dialog', (
    tester,
  ) async {
    await pumpMikanButton(
      tester,
      subject: _subject(type: 2),
      loggedIn: true,
      remoteSubscribed: true,
      mapping: MikanSubjectMapping(
        subjectId: 12345,
        bangumiId: '681',
        bangumiName: '测试动画',
        subgroupId: '15',
        subgroupName: '字幕组',
        subscribed: true,
        updatedAt: DateTime(2026, 5, 21),
      ),
    );

    await tester.tap(find.text('追番'));
    await tester.pumpAndSettle();
    expect(find.text('取消订阅'), findsOneWidget);
    expect(find.text('查看资源'), findsOneWidget);

    await tester.tap(find.text('查看资源'));
    await tester.pumpAndSettle();

    expect(find.text('Mikan 资源'), findsNothing);
    expect(find.text('测试资源'), findsOneWidget);
  });

  testWidgets('portrait Mikan resources open as drawer', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpMikanButton(
      tester,
      subject: _subject(type: 2),
      loggedIn: true,
      remoteSubscribed: true,
      mapping: MikanSubjectMapping(
        subjectId: 12345,
        bangumiId: '681',
        bangumiName: '测试动画',
        subgroupId: '15',
        subgroupName: '字幕组',
        subscribed: true,
        updatedAt: DateTime(2026, 5, 21),
      ),
    );

    await tester.tap(find.text('追番'));
    await tester.pumpAndSettle();
    expect(find.text('字幕组 资源'), findsNothing);

    await tester.tap(find.text('查看资源'));
    await tester.pumpAndSettle();

    expect(find.text('字幕组 资源'), findsOneWidget);
    expect(find.text('测试资源'), findsOneWidget);
  });

  testWidgets('Mikan subscription button is hidden when feature is disabled', (
    tester,
  ) async {
    await pumpMikanButton(tester, subject: _subject(type: 2), enabled: false);

    expect(find.text('Mikan'), findsNothing);
    expect(find.text('追番'), findsNothing);
    expect(find.text('已订阅'), findsNothing);
  });

  testWidgets('Mikan subscription button reflects saved subscribed mapping', (
    tester,
  ) async {
    await pumpMikanButton(
      tester,
      subject: _subject(type: 2),
      loggedIn: true,
      mapping: MikanSubjectMapping(
        subjectId: 12345,
        bangumiId: '681',
        bangumiName: '测试动画',
        subgroupId: '15',
        subgroupName: '字幕组',
        subscribed: true,
        updatedAt: DateTime(2026, 5, 21),
      ),
    );

    expect(find.text('追番'), findsOneWidget);
    expect(find.text('已订阅'), findsNothing);
  });
}

Subject _subject({required int type}) {
  return Subject(
    id: 12345,
    type: type,
    name: 'test',
    nameCn: '测试动画',
    summary: '',
    eps: 12,
    volumes: 0,
    score: 0,
    rank: 0,
    collectionTotal: 0,
    date: '',
    tags: const [],
    infobox: const {},
  );
}
