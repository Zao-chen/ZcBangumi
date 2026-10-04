import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/services/app_log_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late AppLogService logs;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zc_bangumi_logs_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          switch (call.method) {
            case 'getApplicationSupportDirectory':
            case 'getTemporaryDirectory':
              return directory.path;
            default:
              throw MissingPluginException(call.method);
          }
        });
    logs = AppLogService(now: () => DateTime(2026, 10, 5, 12));
  });

  tearDown(() async {
    logs.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    await directory.delete(recursive: true);
  });

  test('native logs remain file-backed and newest-first', () async {
    await logs.init();
    await Future.wait([
      logs.info('app', 'first\nline'),
      logs.warning('network', ' second\tline '),
      logs.error('network', 'third'),
    ]);

    final entries = await logs.readEntries(limit: 2);
    expect(entries.map((entry) => entry.level), ['ERROR', 'WARN']);
    expect(entries.map((entry) => entry.message), ['third', 'second line']);
    final file = File('${directory.path}/logs/zc_bangumi.log');
    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), await logs.readText());
  });

  test('native export copies all pending entries to a separate file', () async {
    final pending = logs.info('app', 'pending');
    final exported = await logs.exportLogFile();
    await pending;

    expect(
      exported.path,
      '${directory.path}/zc_bangumi_log_20261005_120000.txt',
    );
    expect(await exported.readAsString(), contains('pending'));
    await logs.clear();
    expect(await logs.readText(), isEmpty);
    expect(await exported.readAsString(), contains('pending'));
  });

  test(
    'native clearing waits for queued writes and logging continues',
    () async {
      final pending = logs.info('app', 'before clear');
      await logs.clear();
      await pending;
      expect(await logs.readEntries(), isEmpty);

      await logs.info('app', 'after clear');
      expect((await logs.readEntries()).single.message, 'after clear');
    },
  );
}
