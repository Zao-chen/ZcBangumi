import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/api_client.dart';
import 'services/storage_service.dart';
import 'providers/auth_provider.dart';
import 'providers/collection_provider.dart';
import 'widgets/responsive_scaffold.dart';
import 'pages/timeline_page.dart';
import 'pages/progress_page.dart';
import 'pages/profile_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化存储
  final storage = StorageService();
  await storage.init();

  // 初始化 API 客户端
  final apiClient = ApiClient();

  runApp(ZCBangumiApp(apiClient: apiClient, storage: storage));
}

class ZCBangumiApp extends StatelessWidget {
  final ApiClient apiClient;
  final StorageService storage;

  const ZCBangumiApp({
    super.key,
    required this.apiClient,
    required this.storage,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        Provider<StorageService>.value(value: storage),
        ChangeNotifierProvider(
          create: (_) =>
              AuthProvider(api: apiClient, storage: storage)
                ..tryRestoreSession(),
        ),
        ChangeNotifierProvider(
          create: (_) => CollectionProvider(api: apiClient, storage: storage),
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
  int _currentIndex = 0;

  static const _navItems = [
    NavigationItem(
      icon: Icons.dynamic_feed_outlined,
      selectedIcon: Icons.dynamic_feed,
      label: '动态',
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
  ];

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      currentIndex: _currentIndex,
      onIndexChanged: (i) => setState(() => _currentIndex = i),
      items: _navItems,
      pages: const [TimelinePage(), ProgressPage(), ProfilePage()],
    );
  }
}
