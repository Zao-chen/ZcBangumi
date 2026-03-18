import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'constants.dart';
import 'services/api_client.dart';
import 'services/storage_service.dart';
import 'services/update_service.dart';
import 'models/navigation_config.dart';
import 'providers/auth_provider.dart';
import 'providers/collection_provider.dart';
import 'providers/app_state_provider.dart';
import 'providers/update_provider.dart';
import 'widgets/responsive_scaffold.dart';
import 'widgets/update_dialog.dart';
import 'pages/timeline_page.dart';
import 'pages/rakuen_page.dart';
import 'pages/progress_page.dart';
import 'pages/profile_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化存储
  final storage = StorageService();
  await storage.init();

  // 初始化 API 客户端
  final apiClient = ApiClient();
  apiClient.setWebSession(storage.webSession);

  // 初始化更新服务
  final updateService = UpdateService(apiClient.dio, storage);

  runApp(
    ZCBangumiApp(
      apiClient: apiClient,
      storage: storage,
      updateService: updateService,
    ),
  );
}

class ZCBangumiApp extends StatelessWidget {
  final ApiClient apiClient;
  final StorageService storage;
  final UpdateService updateService;

  const ZCBangumiApp({
    super.key,
    required this.apiClient,
    required this.storage,
    required this.updateService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        Provider<StorageService>.value(value: storage),
        Provider<UpdateService>.value(value: updateService),
        ChangeNotifierProvider(
          create: (_) => AppStateProvider(storage: storage),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(api: apiClient, storage: storage),
        ),
        ChangeNotifierProvider(
          create: (_) => CollectionProvider(api: apiClient, storage: storage),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              UpdateProvider(updateService: updateService, storage: storage),
        ),
      ],
      child: MaterialApp(
        title: 'ZC Bangumi',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFFF09199), // Bangumi 粉色
          useMaterial3: true,
          brightness: Brightness.light,
          fontFamily: 'Roboto',
          fontFamilyFallback: const [
            'PingFang SC',
            'Microsoft YaHei',
            'SimHei',
          ],
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFFF09199),
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: 'Roboto',
          fontFamilyFallback: const [
            'PingFang SC',
            'Microsoft YaHei',
            'SimHei',
          ],
        ),
        themeMode: ThemeMode.system,
        home: const _AppShell(),
      ),
    );
  }
}

/// App 外壳 - 管理底部/侧边导航
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  Widget _pageForTab(String tabId) {
    switch (tabId) {
      case AppNavTabId.timeline:
        return const TimelinePage();
      case AppNavTabId.rakuen:
        return const RakuenPage();
      case AppNavTabId.progress:
        return const ProgressPage();
      case AppNavTabId.profile:
        return const ProfilePage();
      default:
        return const TimelinePage();
    }
  }

  @override
  void initState() {
    super.initState();
    // 后台初始化：恢复登录状态 + 检查更新（不阻塞 UI）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _backgroundInit();
    });
  }

  /// 后台初始化（无感执行）
  Future<void> _backgroundInit() async {
    try {
      // 0. 预加载所有缓存数据（立刻替换骨架屏）
      if (mounted) {
        final collectionProvider = context.read<CollectionProvider>();
        collectionProvider.preloadCachesIfAvailable();
      }

      // 1. 尝试恢复登录状态
      final authProvider = context.read<AuthProvider>();
      await authProvider.tryRestoreSession();

      // 1.5 启动后自动刷新关键数据（可配置）
      if (mounted) {
        final appState = context.read<AppStateProvider>();
        if (appState.startupAutoRefresh &&
            authProvider.isLoggedIn &&
            authProvider.username != null) {
          final collectionProvider = context.read<CollectionProvider>();
          await Future.wait([
            collectionProvider.loadDoingCollections(
              username: authProvider.username!,
              subjectType: BgmConst.subjectAnime,
              refresh: true,
              forceNetwork: true,
            ),
            collectionProvider.loadDoingCollections(
              username: authProvider.username!,
              subjectType: BgmConst.subjectGame,
              refresh: true,
              forceNetwork: true,
            ),
            collectionProvider.loadDoingCollections(
              username: authProvider.username!,
              subjectType: BgmConst.subjectBook,
              refresh: true,
              forceNetwork: true,
            ),
          ]);
        }
      }

      // 2. 检查更新
      if (mounted) {
        await _checkForUpdateOnStartup();
      }
    } catch (e) {
      debugPrint('后台初始化失败: $e');
    }
  }

  /// 启动时检查更新
  Future<void> _checkForUpdateOnStartup() async {
    final updateProvider = context.read<UpdateProvider>();
    await updateProvider.autoCheckUpdate();

    // 如果有更新，显示对话框
    if (mounted && updateProvider.state == UpdateState.available) {
      UpdateDialog.show(
        context,
        forceUpdate: updateProvider.updateInfo?.forceUpdate ?? false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    final tabIds = appState.enabledBottomNavTabIds;

    final shellTabs = tabIds
        .map((id) {
          final spec = AppNavigationConfig.getById(id);
          if (spec == null) return null;
          return _ShellTab(
            item: NavigationItem(
              icon: spec.icon,
              selectedIcon: spec.selectedIcon,
              label: spec.label,
            ),
            page: _pageForTab(spec.id),
          );
        })
        .whereType<_ShellTab>()
        .toList(growable: false);

    final safeTabs = shellTabs.isEmpty
        ? [
            _ShellTab(
              item: const NavigationItem(
                icon: Icons.rss_feed_outlined,
                selectedIcon: Icons.rss_feed,
                label: '动态',
              ),
              page: const TimelinePage(),
            ),
          ]
        : shellTabs;

    final safeIndex = appState.currentNavIndex
        .clamp(0, safeTabs.length - 1)
        .toInt();
    if (safeIndex != appState.currentNavIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<AppStateProvider>().setCurrentNavIndex(safeIndex);
        }
      });
    }

    return ResponsiveScaffold(
      currentIndex: safeIndex,
      onIndexChanged: (i) {
        appState.setCurrentNavIndex(i);
      },
      items: safeTabs.map((tab) => tab.item).toList(growable: false),
      pages: safeTabs.map((tab) => tab.page).toList(growable: false),
    );
  }
}

class _ShellTab {
  final NavigationItem item;
  final Widget page;

  const _ShellTab({required this.item, required this.page});
}
