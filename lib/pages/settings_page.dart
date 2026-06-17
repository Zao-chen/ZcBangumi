import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/navigation_config.dart';
import '../models/subject_tab_config.dart';
import '../providers/app_state_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../providers/mikan_provider.dart';
import '../services/mikan_service.dart';
import '../services/platform_feature_support.dart';
import '../services/link_navigator.dart';
import '../services/storage_service.dart';
import '../widgets/update_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _selectedSectionIndex = 0;
  String _version = '';
  final TextEditingController _mikanUsernameController =
      TextEditingController();
  final TextEditingController _mikanPasswordController =
      TextEditingController();

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
  void dispose() {
    _mikanUsernameController.dispose();
    _mikanPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTwoPane =
            constraints.maxWidth >= 720 ||
            (constraints.maxWidth > constraints.maxHeight &&
                constraints.maxWidth >= 600);

        if (isTwoPane) {
          return _buildTwoPaneLayout(context, auth, colorScheme);
        }

        return _buildCompactLayout(context, auth, colorScheme);
      },
    );
  }

  Widget _buildCompactLayout(
    BuildContext context,
    AuthProvider auth,
    ColorScheme colorScheme,
  ) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildAppInfoCard(colorScheme),
                const SizedBox(height: 16),
                _buildCategoryMenuCard(context, isTwoPane: false),
                const SizedBox(height: 16),
                _buildAccountCard(auth),
              ],
            ),
          ),
          if (auth.isLoggedIn) _buildLogoutArea(context),
        ],
      ),
    );
  }

  Widget _buildTwoPaneLayout(
    BuildContext context,
    AuthProvider auth,
    ColorScheme colorScheme,
  ) {
    final sections = _settingsSections(context);
    final selectedIndex = _selectedSectionIndex
        .clamp(0, sections.length - 1)
        .toInt();
    final selectedSection = sections[selectedIndex];

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Row(
        children: [
          SizedBox(
            width: 320,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                    children: [
                      _buildAppInfoCard(colorScheme, compact: true),
                      const SizedBox(height: 12),
                      _buildCategoryMenuCard(context, isTwoPane: true),
                      const SizedBox(height: 12),
                      _buildAccountCard(auth),
                    ],
                  ),
                ),
                if (auth.isLoggedIn) _buildLogoutArea(context, horizontal: 12),
              ],
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    Icon(selectedSection.icon),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        selectedSection.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  selectedSection.subtitle,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                ...selectedSection.builder(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppInfoCard(ColorScheme colorScheme, {bool compact = false}) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 20),
        child: compact
            ? Row(
                children: [
                  _buildAppIcon(size: 56, radius: 12),
                  const SizedBox(width: 12),
                  Expanded(child: _buildAppInfoText(colorScheme)),
                ],
              )
            : Column(
                children: [
                  _buildAppIcon(size: 80, radius: 16),
                  const SizedBox(height: 16),
                  _buildAppInfoText(colorScheme, centered: true),
                ],
              ),
      ),
    );
  }

  Widget _buildAppIcon({required double size, required double radius}) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          'assets/images/bangumi_icon.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildAppInfoText(ColorScheme colorScheme, {bool centered = false}) {
    final align = centered ? TextAlign.center : TextAlign.start;

    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          'ZC Bangumi',
          textAlign: align,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Bangumi 番组计划第三方客户端',
          textAlign: align,
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Text(
          _version,
          textAlign: align,
          style: TextStyle(fontSize: 11, color: colorScheme.outline),
        ),
      ],
    );
  }

  Widget _buildAccountCard(AuthProvider auth) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person_outline),
        title: const Text('账号'),
        subtitle: Text(auth.user != null ? '@${auth.user!.username}' : '未登录'),
      ),
    );
  }

  Widget _buildLogoutArea(BuildContext context, {double horizontal = 16}) {
    return SafeArea(
      top: false,
      minimum: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 16),
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
    );
  }

  Widget _buildCategoryMenuCard(
    BuildContext context, {
    required bool isTwoPane,
  }) {
    final sections = _settingsSections(context);

    return Card(
      child: Column(
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _CategoryEntryTile(
              icon: sections[i].icon,
              title: sections[i].title,
              subtitle: sections[i].subtitle,
              selected: isTwoPane && i == _selectedSectionIndex,
              onTap: () {
                if (isTwoPane) {
                  setState(() => _selectedSectionIndex = i);
                  return;
                }
                _openSectionPage(
                  context,
                  title: sections[i].title,
                  builder: sections[i].builder,
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  List<_SettingsSection> _settingsSections(BuildContext context) {
    return [
      _SettingsSection(
        icon: Icons.tune_rounded,
        title: '底栏自定义',
        subtitle: '排序、显隐与恢复默认',
        builder: (ctx) {
          final appState = ctx.watch<AppStateProvider>();
          return [_buildBottomNavSettingsCard(ctx, appState)];
        },
      ),
      _SettingsSection(
        icon: Icons.sync_rounded,
        title: '刷新与缓存',
        subtitle: '自动刷新、下拉策略与缓存清理',
        builder: (ctx) {
          final appState = ctx.watch<AppStateProvider>();
          return [_buildDataAndRefreshSettingsCard(ctx, appState)];
        },
      ),
      _SettingsSection(
        icon: Icons.playlist_play_outlined,
        title: '进度分区',
        subtitle: '控制进度页显示的条目类型',
        builder: (ctx) {
          final appState = ctx.watch<AppStateProvider>();
          return [_buildProgressSubjectTypeSettingsCard(ctx, appState)];
        },
      ),
      _SettingsSection(
        icon: Icons.palette_outlined,
        title: '阅读与显示',
        subtitle: '密度、圆角与信息展示',
        builder: (ctx) {
          final appState = ctx.watch<AppStateProvider>();
          return [_buildDisplaySettingsCard(ctx, appState)];
        },
      ),
      if (kIsWeb)
        _SettingsSection(
          icon: Icons.public_outlined,
          title: '静态网页版',
          subtitle: '跨域与站点会话限制',
          builder: _buildStaticWebLimitationsCards,
        ),
      if (PlatformFeatureSupport.timeline || PlatformFeatureSupport.rakuen)
        _SettingsSection(
          icon: Icons.view_day_outlined,
          title: '默认分区',
          subtitle: PlatformFeatureSupport.rakuen ? '动态与超展开进入分区' : '动态进入分区',
          builder: (ctx) {
            final appState = ctx.watch<AppStateProvider>();
            return [_buildDefaultTabSettingsCard(ctx, appState)];
          },
        ),
      _SettingsSection(
        icon: Icons.dashboard_customize_outlined,
        title: '\u6761\u76ee\u9875\u6807\u7b7e',
        subtitle:
            '\u6392\u5e8f\u3001\u663e\u9690\u4e0e\u6062\u590d\u9ed8\u8ba4',
        builder: (ctx) {
          final appState = ctx.watch<AppStateProvider>();
          return [_buildSubjectTabSettingsCard(ctx, appState)];
        },
      ),
      if (PlatformFeatureSupport.appUpdate)
        _SettingsSection(
          icon: Icons.system_update_alt_rounded,
          title: '更新设置',
          subtitle: '检查频率、版本策略与手动检查',
          builder: (ctx) {
            final appState = ctx.watch<AppStateProvider>();
            return [
              const Card(child: CheckUpdateButton()),
              _buildUpdateSettingsCard(ctx, appState),
            ];
          },
        ),
      if (PlatformFeatureSupport.mikan)
        _SettingsSection(
          icon: Icons.cloud_sync_outlined,
          title: 'Mikan 订阅',
          subtitle: '账号、镜像与本地映射',
          builder: (ctx) {
            final mikan = ctx.watch<MikanProvider>();
            return [_buildMikanSettingsCard(ctx, mikan)];
          },
        ),
    ];
  }

  List<Widget> _buildStaticWebLimitationsCards(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return [
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('GitHub Pages 静态部署'),
              subtitle: const Text('浏览器无法代替客户端发送跨站 Cookie 或绕过目标站跨域策略'),
              iconColor: colorScheme.primary,
            ),
            ListTile(
              leading: const Icon(Icons.system_update_alt_rounded),
              title: const Text('查看完整应用版'),
              subtitle: const Text('下载 Android / Windows 版本，或查看完整更新说明'),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: () => _openFullAppReleasePage(context),
            ),
            const Divider(height: 1),
            const ListTile(
              leading: Icon(Icons.hide_source_outlined),
              title: Text('动态与超展开'),
              subtitle: Text('静态网页版隐藏相关入口，可在桌面或移动端使用'),
            ),
            const ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Mikan 订阅'),
              subtitle: Text('登录、订阅和取消订阅需要站点会话，静态网页版不显示入口'),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _openFullAppReleasePage(BuildContext context) async {
    final ok = await LinkNavigator.openBrowser(
      Uri.parse(BgmConst.githubReleasesUrl),
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开完整应用版页面')));
    }
  }

  Widget _buildMikanSettingsCard(BuildContext context, MikanProvider mikan) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_sync_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mikan 订阅',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (mikan.isEnabled)
                  DropdownButton<String>(
                    value:
                        MikanService.availableBaseUrls.contains(mikan.baseUrl)
                        ? mikan.baseUrl
                        : MikanService.defaultBaseUrl,
                    onChanged: mikan.loading
                        ? null
                        : (value) {
                            if (value != null) {
                              mikan.setBaseUrl(value);
                            }
                          },
                    items: const [
                      DropdownMenuItem(
                        value: 'https://mikanani.me',
                        child: Text('mikanani'),
                      ),
                      DropdownMenuItem(
                        value: 'https://mikanime.tv',
                        child: Text('mikanime'),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用 Mikan 功能'),
              subtitle: const Text('关闭后条目页不显示 Mikan 订阅按钮和资源入口'),
              value: mikan.isEnabled,
              onChanged: mikan.loading ? null : mikan.setEnabled,
            ),
            if (!mikan.isEnabled) ...[
              const SizedBox(height: 4),
              Text(
                'Mikan 功能已关闭，登录态和本地映射会保留。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                mikan.isLoggedIn
                    ? '已登录 @${mikan.session?.username ?? mikan.user?.name ?? ''}'
                    : '登录后可在动画条目页同步 Mikan 订阅',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (mikan.error != null) ...[
                const SizedBox(height: 10),
                Text(
                  mikan.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              if (!mikan.isLoggedIn) ...[
                TextField(
                  controller: _mikanUsernameController,
                  enabled: !mikan.loading,
                  decoration: const InputDecoration(
                    labelText: 'Mikan 用户名 / 邮箱',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _mikanPasswordController,
                  enabled: !mikan.loading,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mikan 密码',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  onSubmitted: (_) => _loginMikan(mikan),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: mikan.loading ? null : () => _loginMikan(mikan),
                    icon: mikan.loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login_rounded),
                    label: const Text('登录 Mikan'),
                  ),
                ),
              ] else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: mikan.loading ? null : mikan.logout,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('退出 Mikan'),
                    ),
                    OutlinedButton.icon(
                      onPressed: mikan.loading ? null : _clearMikanData,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('清理 Mikan 缓存'),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
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
            subtitle: const Text('登录后自动刷新进度页当前启用的分区'),
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

  Widget _buildProgressSubjectTypeSettingsCard(
    BuildContext context,
    AppStateProvider appState,
  ) {
    final enabledCount = appState.enabledProgressSubjectTypes.length;
    final hidden = appState.hiddenProgressSubjectTypes;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.playlist_play_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '进度页分区',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: hidden.isEmpty
                      ? null
                      : appState.resetProgressSubjectTypes,
                  child: const Text('恢复默认'),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '选择进度页和启动自动刷新包含的条目类型。至少保留 1 个分区。',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            for (final type in AppStateProvider.progressSubjectTypeOrder)
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                secondary: Icon(_progressSubjectIcon(type)),
                title: Text(BgmConst.subjectTypeName(type)),
                value: appState.isProgressSubjectTypeVisible(type),
                onChanged:
                    appState.isProgressSubjectTypeVisible(type) &&
                        enabledCount <= 1
                    ? null
                    : (value) {
                        appState.setProgressSubjectTypeVisible(type, value);
                      },
              ),
          ],
        ),
      ),
    );
  }

  IconData _progressSubjectIcon(int type) {
    switch (type) {
      case BgmConst.subjectAnime:
        return Icons.movie_outlined;
      case BgmConst.subjectGame:
        return Icons.sports_esports_outlined;
      case BgmConst.subjectBook:
        return Icons.menu_book_outlined;
      case BgmConst.subjectMusic:
        return Icons.music_note_outlined;
      case BgmConst.subjectReal:
        return Icons.live_tv_outlined;
      default:
        return Icons.category_outlined;
    }
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
          if (PlatformFeatureSupport.timeline)
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
          if (PlatformFeatureSupport.rakuen)
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
    final order = appState.bottomNavOrder
        .where(_isSupportedBottomNavTab)
        .toList(growable: false);

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
                final enabledCount = appState.enabledBottomNavTabIds
                    .where(_isSupportedBottomNavTab)
                    .length;
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

  Widget _buildSubjectTabSettingsCard(
    BuildContext context,
    AppStateProvider appState,
  ) {
    final order = appState.subjectTabOrder;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dashboard_customize_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '\u6761\u76ee\u9875\u6807\u7b7e',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed:
                      appState.hiddenSubjectTabIds.isEmpty &&
                          _isDefaultSubjectTabOrder(order)
                      ? null
                      : appState.resetSubjectTabConfig,
                  child: const Text('\u6062\u590d\u9ed8\u8ba4'),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '\u62d6\u52a8\u53ef\u6392\u5e8f\uff0c\u53f3\u4fa7\u5f00\u5173\u53ef\u9690\u85cf\u3002\u81f3\u5c11\u4fdd\u7559 1 \u4e2a\u6807\u7b7e\u3002',
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
                appState.setSubjectTabOrder(next);
              },
              itemBuilder: (context, index) {
                final tabId = order[index];
                final tab = SubjectTabConfig.getById(tabId);
                if (tab == null) {
                  return const SizedBox.shrink();
                }

                final isVisible = appState.isSubjectTabVisible(tabId);
                final enabledCount = appState.enabledSubjectTabIds.length;
                final canToggle = !isVisible || enabledCount > 1;
                final hiddenColor = Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant;

                return ListTile(
                  key: ValueKey('subject-tab-$tabId'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Icon(
                    tab.icon,
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
                                appState.setSubjectTabVisible(tabId, value);
                              }
                            : null,
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
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
    final defaultOrder = AppNavigationConfig.defaultOrder
        .where(_isSupportedBottomNavTab)
        .toList(growable: false);
    if (order.length != defaultOrder.length) {
      return false;
    }
    for (var i = 0; i < order.length; i++) {
      if (order[i] != defaultOrder[i]) {
        return false;
      }
    }
    return true;
  }

  bool _isSupportedBottomNavTab(String tabId) {
    if (tabId == AppNavTabId.timeline && !PlatformFeatureSupport.timeline) {
      return false;
    }
    if (tabId == AppNavTabId.rakuen && !PlatformFeatureSupport.rakuen) {
      return false;
    }
    return true;
  }

  bool _isDefaultSubjectTabOrder(List<String> order) {
    if (order.length != SubjectTabConfig.defaultOrder.length) {
      return false;
    }
    for (var i = 0; i < order.length; i++) {
      if (order[i] != SubjectTabConfig.defaultOrder[i]) {
        return false;
      }
    }
    return true;
  }

  Future<void> _loginMikan(MikanProvider mikan) async {
    final username = _mikanUsernameController.text.trim();
    final password = _mikanPasswordController.text;
    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入 Mikan 账号和密码')));
      return;
    }

    final ok = await mikan.login(username, password);
    if (!mounted) return;
    if (ok) {
      _mikanPasswordController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Mikan 登录成功')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Mikan 登录失败')));
    }
  }

  Future<void> _clearMikanData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理 Mikan 缓存'),
        content: const Text('将清理 Mikan 登录态和本地条目映射，Bangumi 登录不受影响。'),
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
    await context.read<MikanProvider>().clearLocalMikanData();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mikan 缓存已清理')));
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
  final bool selected;
  final VoidCallback onTap;

  const _CategoryEntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      selected: selected,
      onTap: onTap,
    );
  }
}

class _SettingsSection {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> Function(BuildContext context) builder;

  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
  });
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
