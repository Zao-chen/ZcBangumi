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
  _FakeMikanService() : super(baseUrl: MikanService.defaultBaseUrl);
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
    MikanSubjectMapping? mapping,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final storage = loggedIn ? await storageWithSession() : StorageService();
    if (!loggedIn) {
      await storage.init();
    }
    final mikan = MikanProvider(service: _FakeMikanService(), storage: storage);
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

    expect(find.text('Mikan'), findsOneWidget);
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

    expect(find.text('已订阅'), findsOneWidget);
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
