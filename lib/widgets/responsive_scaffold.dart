import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/mikan_provider.dart';
import '../services/link_navigator.dart';
import '../services/platform_feature_support.dart';

/// 响应式 Scaffold
/// 竖屏时底部导航栏，横屏时左侧导航栏
class ResponsiveScaffold extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final List<Widget> pages;
  final List<NavigationItem> items;

  const ResponsiveScaffold({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
    required this.pages,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        final isWide = constraints.maxWidth > 600;

        if (isLandscape || isWide) {
          return _buildLandscapeLayout(context);
        } else {
          return _buildPortraitLayout(context);
        }
      },
    );
  }

  /// 竖屏布局 - 底部导航栏
  Widget _buildPortraitLayout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: _CacheAwareContent(
        child: IndexedStack(index: currentIndex, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onIndexChanged,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        destinations: items
            .map(
              (item) => NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.selectedIcon),
                label: item.label,
              ),
            )
            .toList(),
      ),
    );
  }

  /// 横屏布局 - 左侧导航栏
  Widget _buildLandscapeLayout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: currentIndex,
            onDestinationSelected: onIndexChanged,
            backgroundColor: colorScheme.surface,
            indicatorColor: colorScheme.primaryContainer,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Image.asset(
                  'assets/images/bangumi_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            destinations: items
                .map(
                  (item) => NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: Text(item.label),
                  ),
                )
                .toList(),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: _CacheAwareContent(
              child: IndexedStack(index: currentIndex, children: pages),
            ),
          ),
        ],
      ),
    );
  }
}

class _CacheAwareContent extends StatefulWidget {
  final Widget child;

  const _CacheAwareContent({required this.child});

  @override
  State<_CacheAwareContent> createState() => _CacheAwareContentState();
}

class _CacheAwareContentState extends State<_CacheAwareContent> {
  bool _webLimitationsDismissed = false;

  Future<void> _openFullAppReleasePage() async {
    final ok = await LinkNavigator.openBrowser(
      Uri.parse(BgmConst.githubReleasesUrl),
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开完整应用版页面')));
    }
  }

  Future<bool> _retryConnectionAndRestoreSession() async {
    final connected = await context
        .read<ConnectivityProvider>()
        .retryConnection();
    if (!connected || !mounted) return connected;

    await context.read<AuthProvider>().tryRestoreSession();
    if (PlatformFeatureSupport.mikan && mounted) {
      await context.read<MikanProvider>().tryRestoreSession();
    }
    return connected;
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityProvider>();
    final showCacheBanner = connectivity.shouldShowBanner;
    final showWebLimitationsBanner = kIsWeb && !_webLimitationsDismissed;

    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: showWebLimitationsBanner
              ? _WebLimitationsBanner(
                  onOpenFullApp: _openFullAppReleasePage,
                  onClose: () {
                    setState(() => _webLimitationsDismissed = true);
                  },
                )
              : const SizedBox.shrink(),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: showCacheBanner
              ? _OfflineCacheBanner(
                  message: connectivity.bannerMessage,
                  rechecking: connectivity.rechecking,
                  onRetry: _retryConnectionAndRestoreSession,
                  onClose: context.read<ConnectivityProvider>().dismissBanner,
                  safeAreaTop: !showWebLimitationsBanner,
                )
              : const SizedBox.shrink(),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

class _WebLimitationsBanner extends StatelessWidget {
  final VoidCallback onOpenFullApp;
  final VoidCallback onClose;

  const _WebLimitationsBanner({
    required this.onOpenFullApp,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.secondaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.public_off_rounded,
                color: colorScheme.onSecondaryContainer,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '静态网页版部分跨站功能不可用',
                  style: TextStyle(
                    color: colorScheme.onSecondaryContainer,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: '查看完整应用版',
                onPressed: onOpenFullApp,
                icon: const Icon(Icons.open_in_new_rounded),
                color: colorScheme.onSecondaryContainer,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
                color: colorScheme.onSecondaryContainer,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineCacheBanner extends StatelessWidget {
  final String message;
  final bool rechecking;
  final Future<bool> Function() onRetry;
  final VoidCallback onClose;
  final bool safeAreaTop;

  const _OfflineCacheBanner({
    required this.message,
    required this.rechecking,
    required this.onRetry,
    required this.onClose,
    this.safeAreaTop = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.tertiaryContainer,
      child: SafeArea(
        top: safeAreaTop,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.cloud_off_rounded,
                color: colorScheme.onTertiaryContainer,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: colorScheme.onTertiaryContainer,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: '重新连接',
                onPressed: rechecking ? null : onRetry,
                icon: rechecking
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onTertiaryContainer,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded),
                color: colorScheme.onTertiaryContainer,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
                color: colorScheme.onTertiaryContainer,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 导航项
class NavigationItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}
