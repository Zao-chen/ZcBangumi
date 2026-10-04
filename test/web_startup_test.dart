import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/main.dart' as app;
import 'package:zc_bangumi/pages/log_page.dart';
import 'package:zc_bangumi/services/app_log_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Web logging', () {
    late AppLogService logs;

    setUp(() {
      logs = AppLogService(now: () => DateTime(2026, 10, 5, 12));
    });

    tearDown(() {
      logs.dispose();
    });

    test('initializes without a filesystem plugin', () async {
      await logs.init();
      final entries = await logs.readEntries();
      expect(entries.single.category, 'app');
      expect(entries.single.message, '日志服务已启动');
    });

    test('records all levels and returns newest entries first', () async {
      await logs.info('app', 'first');
      await logs.warning('network', 'second');
      await logs.error('network', 'third');

      final entries = await logs.readEntries(limit: 2);
      expect(entries.map((entry) => entry.level), ['ERROR', 'WARN']);
      expect(entries.map((entry) => entry.message), ['third', 'second']);
      expect(await logs.readText(), contains('[INFO] app first\n'));
    });

    test('sanitizes whitespace and preserves concurrent writes', () async {
      await Future.wait([
        logs.info(' app ', 'first\nline'),
        logs.warning('network', ' second\tline '),
      ]);

      final entries = await logs.readEntries();
      expect(entries.map((entry) => entry.message), [
        'second line',
        'first line',
      ]);
      expect(entries.last.category, 'app');
    });

    test('reads and clears wait for pending writes', () async {
      final pending = logs.info('app', 'pending');
      expect(await logs.readText(), contains('pending'));
      await pending;

      final beforeClear = logs.info('app', 'before clear');
      await logs.clear();
      await beforeClear;
      expect(await logs.readText(), isEmpty);
      expect(await logs.readEntries(), isEmpty);

      await logs.info('app', 'after clear');
      expect((await logs.readEntries()).single.message, 'after clear');
    });

    test('bounds memory by UTF-8 byte size', () async {
      final message = List.filled(100000, '中').join();
      for (var index = 0; index < 5; index++) {
        await logs.info('app', '$index$message');
      }

      expect(
        utf8.encode(await logs.readText()).length,
        lessThanOrEqualTo(AppLogService.maxLogBytes),
      );
      final entries = await logs.readEntries();
      expect(entries, hasLength(3));
      expect(entries.first.message, startsWith('4'));
      expect(entries.last.message, startsWith('2'));

      await logs.info(
        'app',
        List.filled(AppLogService.maxLogBytes, '中').join(),
      );
      await logs.info('app', 'still usable');
      expect((await logs.readEntries()).single.message, 'still usable');
    });

    test('file export fails explicitly instead of invoking native plugins', () {
      expect(logs.exportLogFile(), throwsUnsupportedError);
    });
  }, skip: !kIsWeb);

  testWidgets('log menu only offers supported browser actions', (tester) async {
    final logs = AppLogService();
    addTearDown(logs.dispose);
    await logs.init();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppLogService>.value(
        value: logs,
        child: const MaterialApp(home: LogPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('日志服务已启动'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('复制全部'), findsOneWidget);
    expect(find.text('清空日志'), findsOneWidget);
    expect(find.text('导出日志文件'), findsNothing);
    expect(find.text('下载日志文件'), findsOneWidget);
  }, skip: !kIsWeb);

  testWidgets('Web entrypoint reaches runApp without native plugins', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'cache_app_state': jsonEncode({
        'bottomNavOrder': [
          'discover',
          'timeline',
          'rakuen',
          'progress',
          'profile',
        ],
        'hiddenBottomNavTabIds': ['discover', 'timeline', 'rakuen', 'progress'],
        'currentNavTabId': 'profile',
        'startupAutoRefresh': false,
      }),
    });
    await tester.runAsync(() => app.main());
    await tester.pump();
    expect(find.byType(app.ZCBangumiApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, skip: !kIsWeb);
}
