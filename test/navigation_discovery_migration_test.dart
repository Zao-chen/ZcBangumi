import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/navigation_config.dart';
import 'package:zc_bangumi/providers/app_state_provider.dart';
import 'package:zc_bangumi/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new installs start on discovery', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final provider = AppStateProvider(storage: storage);
    await Future<void>.delayed(Duration.zero);

    expect(provider.bottomNavOrder.first, AppNavTabId.discover);
    expect(provider.currentNavTabId, AppNavTabId.discover);
  });

  test(
    'legacy navigation inserts discovery and preserves active tab',
    () async {
      final now = DateTime.now().toIso8601String();
      SharedPreferences.setMockInitialValues({
        'cache_app_state': jsonEncode({
          '__cache_meta': {
            'version': 1,
            'createdAt': now,
            'updatedAt': now,
            'lastAccessedAt': now,
            'accessCount': 0,
          },
          'data': {
            'bottomNavOrder': [
              AppNavTabId.timeline,
              AppNavTabId.rakuen,
              AppNavTabId.progress,
              AppNavTabId.profile,
            ],
            'hiddenBottomNavTabIds': <String>[],
            'currentNavIndex': 2,
          },
        }),
      });
      final storage = StorageService();
      await storage.init();
      final provider = AppStateProvider(storage: storage);
      await Future<void>.delayed(Duration.zero);

      expect(provider.bottomNavOrder.first, AppNavTabId.discover);
      expect(provider.currentNavTabId, AppNavTabId.progress);
      expect(provider.currentNavIndex, 3);
    },
  );

  test('reordering navigation preserves the active tab id', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final provider = AppStateProvider(storage: storage);
    provider.setCurrentNavIndex(2);
    final active = provider.currentNavTabId;

    provider.setBottomNavOrder(provider.bottomNavOrder.reversed.toList());

    expect(provider.currentNavTabId, active);
  });

  test('navigation can select and preserve a tab by its stable id', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final provider = AppStateProvider(storage: storage);

    provider.setCurrentNavTabId(AppNavTabId.profile);
    provider.setBottomNavOrder([
      AppNavTabId.discover,
      AppNavTabId.profile,
      AppNavTabId.progress,
      AppNavTabId.timeline,
      AppNavTabId.rakuen,
    ]);

    expect(provider.currentNavTabId, AppNavTabId.profile);
    expect(provider.currentNavIndex, 1);
  });
}
