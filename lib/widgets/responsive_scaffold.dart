import 'package:flutter/material.dart';

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
      body: IndexedStack(
        index: currentIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onIndexChanged,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        destinations: items
            .map((item) => NavigationDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: item.label,
                ))
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
                .map((item) => NavigationRailDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: Text(item.label),
                    ))
                .toList(),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: IndexedStack(
              index: currentIndex,
              children: pages,
            ),
          ),
        ],
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
