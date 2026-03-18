import 'package:flutter/material.dart';

/// 底栏 Tab ID 定义
class AppNavTabId {
  AppNavTabId._();

  static const String timeline = 'timeline';
  static const String rakuen = 'rakuen';
  static const String progress = 'progress';
  static const String profile = 'profile';

  static const List<String> all = [timeline, rakuen, progress, profile];
}

/// 底栏单个 Tab 的展示配置
class AppNavTabSpec {
  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const AppNavTabSpec({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

/// 应用底栏导航配置
class AppNavigationConfig {
  AppNavigationConfig._();

  static const List<String> defaultOrder = AppNavTabId.all;
  static const List<String> allTabIds = AppNavTabId.all;

  static const List<AppNavTabSpec> tabs = [
    AppNavTabSpec(
      id: AppNavTabId.timeline,
      icon: Icons.rss_feed_outlined,
      selectedIcon: Icons.rss_feed,
      label: '动态',
    ),
    AppNavTabSpec(
      id: AppNavTabId.rakuen,
      icon: Icons.forum_outlined,
      selectedIcon: Icons.forum,
      label: '超展开',
    ),
    AppNavTabSpec(
      id: AppNavTabId.progress,
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view_rounded,
      label: '进度',
    ),
    AppNavTabSpec(
      id: AppNavTabId.profile,
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: '我的',
    ),
  ];

  static AppNavTabSpec? getById(String id) {
    for (final tab in tabs) {
      if (tab.id == id) {
        return tab;
      }
    }
    return null;
  }
}
