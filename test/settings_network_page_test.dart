import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/pages/settings_page.dart';
import 'package:zc_bangumi/providers/app_state_provider.dart';
import 'package:zc_bangumi/providers/auth_provider.dart';
import 'package:zc_bangumi/providers/mikan_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/mikan_service.dart';
import 'package:zc_bangumi/services/storage_service.dart';
import 'package:zc_bangumi/widgets/bangumi_mirror_settings_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StorageService storage;
  late ApiClient api;
  late AppStateProvider appState;
  late AuthProvider auth;
  late MikanProvider mikan;
  late Dio mikanClient;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'ZcBangumi',
      packageName: 'com.zaochen.zcbangumi',
      version: '1.10.0',
      buildNumber: '1',
      buildSignature: '',
    );
    storage = StorageService();
    await storage.init();
    api = ApiClient();
    appState = AppStateProvider(storage: storage);
    auth = AuthProvider(api: api, storage: storage);
    mikanClient = Dio();
    mikan = MikanProvider(
      service: MikanService(dio: mikanClient),
      storage: storage,
    );
  });

  tearDown(() {
    mikan.dispose();
    auth.dispose();
    appState.dispose();
    api.dispose();
    mikanClient.close(force: true);
  });

  Future<void> showSettings(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider<AppStateProvider>.value(value: appState),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<MikanProvider>.value(value: mikan),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(390, 844), Size(1100, 800)]) {
    testWidgets('network groups mirror and proxy settings at ${size.width}px', (
      tester,
    ) async {
      await showSettings(tester, size);
      expect(find.text('Bangumi 镜像站'), findsNothing);
      final network = find.text('网络');
      await tester.ensureVisible(network);
      await tester.tap(network);
      await tester.pumpAndSettle();
      expect(find.byType(BangumiMirrorSettingsCard), findsOneWidget);
      expect(find.text('网络代理'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
      expect(find.text('代理主机'), findsNothing);
      expect(find.text('端口'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('proxy fields appear only for manual configuration', (
    tester,
  ) async {
    await showSettings(tester, const Size(1100, 800));
    await tester.tap(find.text('网络'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动'));
    await tester.pumpAndSettle();
    expect(find.text('代理主机'), findsOneWidget);
    expect(find.text('端口'), findsOneWidget);
    await tester.tap(find.text('直连').last);
    await tester.pumpAndSettle();
    expect(find.text('代理主机'), findsNothing);
    expect(find.text('端口'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
