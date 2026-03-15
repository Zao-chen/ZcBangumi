import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/api_client.dart';
import 'services/storage_service.dart';
import 'services/update_service.dart';
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

    return ResponsiveScaffold(
      currentIndex: appState.currentNavIndex,
      onIndexChanged: (i) {
        appState.setCurrentNavIndex(i);
      },
      items: const [
        NavigationItem(
          icon: Icons.rss_feed_outlined,
          selectedIcon: Icons.rss_feed,
          label: '动态',
        ),
        NavigationItem(
          icon: Icons.forum_outlined,
          selectedIcon: Icons.forum,
          label: '超展开',
        ),
        NavigationItem(
          icon: Icons.grid_view_outlined,
          selectedIcon: Icons.grid_view_rounded,
          label: '进度',
        ),
        NavigationItem(
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          label: '我的',
        ),
      ],
      pages: const [
        TimelinePage(),
        RakuenPage(),
        ProgressPage(),
        ProfilePage(),
      ],
    );
  }
}
