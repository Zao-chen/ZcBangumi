import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'scroll_aware_chrome.dart';

class MonoDetailTab {
  final String label;
  final IconData icon;

  const MonoDetailTab({required this.label, required this.icon});
}

class MonoDetailTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController? controller;
  final List<Widget> tabs;

  const MonoDetailTabBar({super.key, this.controller, required this.tabs});

  @override
  Size get preferredSize => const Size.fromHeight(kTextTabBarHeight);

  @override
  Widget build(BuildContext context) {
    final scrollBehavior = ScrollConfiguration.of(context);
    return ScrollConfiguration(
      behavior: scrollBehavior.copyWith(
        dragDevices: {...scrollBehavior.dragDevices, PointerDeviceKind.mouse},
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: tabs,
      ),
    );
  }
}

class MonoDetailScaffold extends StatelessWidget {
  static const double defaultExpandedHeight = 200;

  final ScrollController scrollController;
  final TabController tabController;
  final List<MonoDetailTab> tabs;
  final List<Widget> tabChildren;
  final int selectedTabIndex;
  final bool showCollapsedTitle;
  final String title;
  final Widget header;
  final List<Widget> actions;
  final VoidCallback? onTitleTap;
  final ScrollPhysics? nestedScrollPhysics;
  final ScrollPhysics? tabViewPhysics;
  final double expandedHeight;
  final bool contentSizedHeader;

  const MonoDetailScaffold({
    super.key,
    required this.scrollController,
    required this.tabController,
    required this.tabs,
    required this.tabChildren,
    required this.selectedTabIndex,
    required this.showCollapsedTitle,
    required this.title,
    required this.header,
    this.actions = const [],
    this.onTitleTap,
    this.nestedScrollPhysics,
    this.tabViewPhysics,
    this.expandedHeight = defaultExpandedHeight,
    this.contentSizedHeader = false,
  }) : assert(tabs.length == tabChildren.length);

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final tabView = TabBarView(
      controller: tabController,
      physics: tabViewPhysics,
      children: tabChildren,
    );

    return ScrollAwareChrome(
      resetKey: selectedTabIndex,
      builder: (context, chrome) {
        final toolbarHeight = chrome.toolbarHeight(kToolbarHeight);
        return Scaffold(
          body: NestedScrollView(
            controller: scrollController,
            physics: nestedScrollPhysics,
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                pinned: true,
                toolbarHeight: toolbarHeight,
                elevation: 0,
                scrolledUnderElevation: 0,
                expandedHeight: contentSizedHeader
                    ? null
                    : expandedHeight - kToolbarHeight + toolbarHeight,
                actions: actions,
                title: showCollapsedTitle ? _buildCollapsedTitle() : null,
                flexibleSpace: contentSizedHeader
                    ? null
                    : FlexibleSpaceBar(
                        collapseMode: CollapseMode.pin,
                        background: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              12,
                              toolbarHeight + 2,
                              12,
                              0,
                            ),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: header,
                            ),
                          ),
                        ),
                      ),
              ),
              if (contentSizedHeader)
                SliverToBoxAdapter(
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: expandedHeight - kToolbarHeight - 2,
                        ),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: header,
                        ),
                      ),
                    ),
                  ),
                ),
              if (!isLandscape)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _MonoDetailTabBarHeaderDelegate(
                    height: kTextTabBarHeight * chrome.animation.value,
                    child: chrome.collapse(
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          border: Border(
                            bottom: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                        ),
                        child: MonoDetailTabBar(
                          controller: tabController,
                          tabs: tabs
                              .map((tab) => Tab(text: tab.label))
                              .toList(),
                        ),
                      ),
                      fullHeight: kTextTabBarHeight,
                    ),
                  ),
                ),
            ],
            body: isLandscape ? _buildLandscapeBody(context, tabView) : tabView,
          ),
        );
      },
    );
  }

  Widget _buildCollapsedTitle() {
    final child = Text(title, maxLines: 1, overflow: TextOverflow.ellipsis);
    return onTitleTap == null
        ? child
        : GestureDetector(onTap: onTitleTap, child: child);
  }

  Widget _buildLandscapeBody(BuildContext context, Widget tabView) {
    final colorScheme = Theme.of(context).colorScheme;
    final topInset = showCollapsedTitle ? (kToolbarHeight + 8) : 0.0;
    return Row(
      children: [
        AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(top: topInset),
          child: NavigationRail(
            selectedIndex: selectedTabIndex,
            onDestinationSelected: tabController.animateTo,
            backgroundColor: colorScheme.surface,
            indicatorColor: colorScheme.primaryContainer,
            labelType: NavigationRailLabelType.all,
            destinations: tabs
                .map(
                  (tab) => NavigationRailDestination(
                    icon: Icon(tab.icon),
                    label: Text(tab.label),
                  ),
                )
                .toList(),
          ),
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(child: tabView),
      ],
    );
  }
}

class _MonoDetailTabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  const _MonoDetailTabBarHeaderDelegate({
    required this.child,
    required this.height,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _MonoDetailTabBarHeaderDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}
