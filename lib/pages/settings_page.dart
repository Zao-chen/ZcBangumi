import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../models/navigation_config.dart';
import '../providers/app_state_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../services/storage_service.dart';
import '../widgets/update_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = 'v${packageInfo.version}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              'assets/images/bangumi_icon.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'ZC Bangumi',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Bangumi 番组计划第三方客户端',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _version,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildCategoryMenuCard(context),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('账号'),
                    subtitle: Text(
                      auth.user != null ? '@${auth.user!.username}' : '未登录',
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (auth.isLoggedIn)
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => _confirmLogout(context),
                  style: FilledButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.logout_rounded),
                      SizedBox(width: 8),
                      Text('退出登录'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryMenuCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          _CategoryEntryTile(
            icon: Icons.tune_rounded,
            title: '底栏自定义',
            subtitle: '排序、显隐与恢复默认',
            onTap: () => _openSectionPage(
              context,
              title: '底栏自定义',
              builder: (ctx) {
                final appState = ctx.watch<AppStateProvider>();
                return [_buildBottomNavSettingsCard(ctx, appState)];
              },
            ),
          ),
          const Divider(height: 1),
          _CategoryEntryTile(
            icon: Icons.sync_rounded,
            title: '刷新与缓存',
            subtitle: '自动刷新、下拉策略与缓存清理',
            onTap: () => _openSectionPage(
              context,
              title: '刷新与缓存',
              builder: (ctx) {
                final appState = ctx.watch<AppStateProvider>();
                return [_buildDataAndRefreshSettingsCard(ctx, appState)];
              },
            ),
          ),
          const Divider(height: 1),
          _CategoryEntryTile(
            icon: Icons.palette_outlined,
            title: '阅读与显示',
            subtitle: '密度、圆角与信息展示',
            onTap: () => _openSectionPage(
              context,
              title: '阅读与显示',
              builder: (ctx) {
                final appState = ctx.watch<AppStateProvider>();
                return [_buildDisplaySettingsCard(ctx, appState)];
              },
            ),
          ),
          const Divider(height: 1),
          _CategoryEntryTile(
            icon: Icons.view_day_outlined,
            title: '默认分区',
            subtitle: '动态与超展开进入分区',
            onTap: () => _openSectionPage(
              context,
              title: '默认分区',
              builder: (ctx) {
                final appState = ctx.watch<AppStateProvider>();
                return [_buildDefaultTabSettingsCard(ctx, appState)];
              },
            ),
          ),
          const Divider(height: 1),
          _CategoryEntryTile(
            icon: Icons.system_update_alt_rounded,
            title: '更新设置',
            subtitle: '检查频率、版本策略与手动检查',
            onTap: () => _openSectionPage(
              context,
              title: '更新设置',
              builder: (ctx) {
                final appState = ctx.watch<AppStateProvider>();
                return [
                  const Card(child: CheckUpdateButton()),
                  _buildUpdateSettingsCard(ctx, appState),
                ];
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openSectionPage(
    BuildContext context, {
    required String title,
    required List<Widget> Function(BuildContext context) builder,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _SettingsSectionPage(title: title, builder: builder),
      ),
    );
  }

  Widget _buildDataAndRefreshSettingsCard(
    BuildContext context,
    AppStateProvider appState,
  ) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('启动后自动刷新关键数据'),
            subtitle: const Text('登录后自动刷新进度列表（动画/游戏/书籍）'),
            value: appState.startupAutoRefresh,
            onChanged: appState.setStartupAutoRefresh,
          ),
          SwitchListTile(
            title: const Text('下拉刷新强制走网络'),
            subtitle: const Text('关闭后会优先使用已有数据，不主动重新请求'),
            value: appState.pullToRefreshForceNetwork,
            onChanged: appState.setPullToRefreshForceNetwork,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('清理接口缓存'),
            subtitle: const Text('清理动态、进度等接口缓存，不影响设置项'),
            onTap: _clearDataCache,
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('清理图片缓存'),
            subtitle: const Text('清理内存与磁盘图片缓存'),
            onTap: _clearImageCache,
          ),
        ],
      ),
    );
  }

  Widget _buildDisplaySettingsCard(
    BuildContext context,
    AppStateProvider appState,
  ) {
    return Card(
      child: Column(
        children: [
          ListTile(
            title: const Text('列表密度'),
            subtitle: const Text('影响进度和我的页列表卡片的紧凑程度'),
            trailing: DropdownButton<int>(
              value: appState.listDensityMode,
              onChanged: (value) {
                if (value != null) appState.setListDensityMode(value);
              },
              items: const [
                DropdownMenuItem(value: 0, child: Text('紧凑')),
                DropdownMenuItem(value: 1, child: Text('标准')),
                DropdownMenuItem(value: 2, child: Text('舒适')),
              ],
            ),
          ),
          ListTile(
            title: const Text('封面圆角'),
            subtitle: Slider(
              value: appState.coverCornerRadius,
              min: 0,
              max: 16,
              divisions: 16,
              label: appState.coverCornerRadius.toStringAsFixed(0),
              onChanged: appState.setCoverCornerRadius,
            ),
            trailing: Text(
              '${appState.coverCornerRadius.toStringAsFixed(0)} px',
            ),
          ),
          SwitchListTile(
            title: const Text('显示二级信息'),
            subtitle: const Text('如评分、排名、更新时间等辅助信息'),
            value: appState.showSecondaryInfo,
            onChanged: appState.setShowSecondaryInfo,
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultTabSettingsCard(
    BuildContext context,
    AppStateProvider appState,
  ) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('恢复上次浏览分区'),
            subtitle: const Text('关闭后，按下方默认分区进入页面'),
            value: appState.restoreLastTabSelection,
            onChanged: appState.setRestoreLastTabSelection,
          ),
          ListTile(
            enabled: !appState.restoreLastTabSelection,
            title: const Text('动态默认分区'),
            trailing: DropdownButton<int>(
              value: appState.defaultTimelineTabIndex,
              onChanged: appState.restoreLastTabSelection
                  ? null
                  : (value) {
                      if (value != null) {
                        appState.setDefaultTimelineTabIndex(value);
                      }
                    },
              items: const [
                DropdownMenuItem(value: 0, child: Text('全站')),
                DropdownMenuItem(value: 1, child: Text('好友')),
                DropdownMenuItem(value: 2, child: Text('我的')),
              ],
            ),
          ),
          ListTile(
            enabled: !appState.restoreLastTabSelection,
            title: const Text('超展开默认分区'),
            trailing: DropdownButton<int>(
              value: appState.defaultRakuenTabIndex,
              onChanged: appState.restoreLastTabSelection
                  ? null
                  : (value) {
                      if (value != null) {
                        appState.setDefaultRakuenTabIndex(value);
                      }
                    },
              items: const [
                DropdownMenuItem(value: 0, child: Text('全部')),
                DropdownMenuItem(value: 1, child: Text('小组')),
                DropdownMenuItem(value: 2, child: Text('条目')),
                DropdownMenuItem(value: 3, child: Text('章节')),
                DropdownMenuItem(value: 4, child: Text('角色')),
                DropdownMenuItem(value: 5, child: Text('人物')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateSettingsCard(
    BuildContext context,
    AppStateProvider appState,
  ) {
    return Card(
      child: Column(
        children: [
          ListTile(
            title: const Text('自动检查更新频率'),
            trailing: DropdownButton<int>(
              value: appState.updateCheckIntervalHours,
              onChanged: (value) {
                if (value != null) {
                  appState.setUpdateCheckIntervalHours(value);
                }
              },
              items: const [
                DropdownMenuItem(value: 0, child: Text('仅手动')),
                DropdownMenuItem(value: 24, child: Text('每天')),
                DropdownMenuItem(value: 168, child: Text('每周')),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('仅提示稳定版更新'),
            subtitle: const Text('关闭后会包含预发布版本'),
            value: appState.updateStableOnly,
            onChanged: appState.setUpdateStableOnly,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavSettingsCard(
    BuildContext context,
    AppStateProvider appState,
  ) {
    final order = appState.bottomNavOrder;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune_rounded),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '底栏自定义',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed:
                      appState.hiddenBottomNavTabIds.isEmpty &&
                          _isDefaultOrder(order)
                      ? null
                      : appState.resetBottomNavConfig,
                  child: const Text('恢复默认'),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '拖动可排序，右侧开关可隐藏。至少保留 1 个入口。',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: order.length,
              onReorder: (oldIndex, newIndex) {
                final next = List<String>.from(order);
                if (newIndex > oldIndex) {
                  newIndex -= 1;
                }
                final moved = next.removeAt(oldIndex);
                next.insert(newIndex, moved);
                appState.setBottomNavOrder(next);
              },
              itemBuilder: (context, index) {
                final tabId = order[index];
                final tab = AppNavigationConfig.getById(tabId);
                if (tab == null) {
                  return const SizedBox.shrink();
                }

                final isVisible = appState.isBottomNavTabVisible(tabId);
                final enabledCount = appState.enabledBottomNavTabIds.length;
                final canToggle = !isVisible || enabledCount > 1;
                final hiddenColor = Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant;

                return ListTile(
                  key: ValueKey('bottom-nav-$tabId'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Icon(
                    isVisible ? tab.selectedIcon : tab.icon,
                    color: isVisible ? null : hiddenColor,
                  ),
                  title: Text(
                    tab.label,
                    style: TextStyle(color: isVisible ? null : hiddenColor),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: isVisible,
                        onChanged: canToggle
                            ? (value) {
                                appState.setBottomNavTabVisible(tabId, value);
                              }
                            : null,
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.drag_handle_rounded,
                            color: isVisible ? null : hiddenColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _isDefaultOrder(List<String> order) {
    if (order.length != AppNavigationConfig.defaultOrder.length) {
      return false;
    }
    for (var i = 0; i < order.length; i++) {
      if (order[i] != AppNavigationConfig.defaultOrder[i]) {
        return false;
      }
    }
    return true;
  }

  Future<void> _clearDataCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理接口缓存'),
        content: const Text('将清理动态、进度等缓存数据，设置项不会被清理。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清理'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final storage = context.read<StorageService>();
    final collection = context.read<CollectionProvider>();
    await storage.clearDataCache();
    collection.clearAll();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('接口缓存已清理')));
  }

  Future<void> _clearImageCache() async {
    await DefaultCacheManager().emptyCache();
    imageCache.clear();
    imageCache.clearLiveImages();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('图片缓存已清理')));
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<CollectionProvider>().clearAll();
      await auth.logout();
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

class _CategoryEntryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CategoryEntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _SettingsSectionPage extends StatelessWidget {
  final String title;
  final List<Widget> Function(BuildContext context) builder;

  const _SettingsSectionPage({required this.title, required this.builder});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: builder(context),
      ),
    );
  }
}
