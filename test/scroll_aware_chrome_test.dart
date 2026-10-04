import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zc_bangumi/providers/connectivity_provider.dart';
import 'package:zc_bangumi/widgets/mono_detail_scaffold.dart';
import 'package:zc_bangumi/widgets/responsive_scaffold.dart';
import 'package:zc_bangumi/widgets/scroll_aware_scaffold.dart';

void main() {
  final list = find.byKey(const ValueKey('reading_list'));
  final bottomNavigation = find.byKey(
    const ValueKey('scroll_aware_bottom_navigation'),
  );

  Widget contentList({int itemCount = 80}) => ListView.builder(
    key: const ValueKey('reading_list'),
    itemExtent: 72,
    itemCount: itemCount,
    itemBuilder: (_, index) => Text('内容 $index'),
  );

  Future<void> showContent(
    WidgetTester tester,
    Widget page, {
    bool shell = false,
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final connectivity = ConnectivityProvider(canReachBangumi: () => true);
    addTearDown(connectivity.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ConnectivityProvider>.value(
        value: connectivity,
        child: MaterialApp(
          home: shell
              ? ResponsiveScaffold(
                  currentIndex: 0,
                  onIndexChanged: (_) {},
                  pages: [page, const SizedBox()],
                  items: const [
                    NavigationItem(
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home,
                      label: '首页',
                    ),
                    NavigationItem(
                      icon: Icons.person_outline,
                      selectedIcon: Icons.person,
                      label: '我的',
                    ),
                  ],
                )
              : page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> wheel(WidgetTester tester, double delta) async {
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: Offset(0, delta),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shared app bar compacts while preserving title and essential actions',
    (tester) async {
      var backTaps = 0;
      var refreshTaps = 0;
      await showContent(
        tester,
        DefaultTabController(
          length: 2,
          child: ScrollAwareScaffold(
            appBar: AppBar(
              title: const Text('阅读'),
              leading: IconButton(
                tooltip: '返回',
                onPressed: () => backTaps++,
                icon: const Icon(Icons.arrow_back),
              ),
              actions: [
                IconButton(
                  tooltip: '刷新',
                  onPressed: () => refreshTaps++,
                  icon: const Icon(Icons.refresh),
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(text: '概览'),
                  Tab(text: '讨论'),
                ],
              ),
            ),
            body: contentList(),
          ),
        ),
      );
      await wheel(tester, 120);
      final compactBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(compactBar.toolbarHeight, 48);
      expect(compactBar.bottom!.preferredSize.height, 0);
      expect(find.text('阅读').hitTestable(), findsOneWidget);
      expect(find.text('概览').hitTestable(), findsNothing);
      await tester.tap(find.byTooltip('返回'));
      await tester.tap(find.byTooltip('刷新'));
      expect(backTaps, 1);
      expect(refreshTaps, 1);
      await wheel(tester, -1);
      final expandedBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(expandedBar.toolbarHeight, kToolbarHeight);
      expect(expandedBar.bottom!.preferredSize.height, kTextTabBarHeight);
      expect(find.text('概览').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('top and bottom chrome share one animation at every frame', (
    tester,
  ) async {
    late ScrollChromeData pageChrome;
    await showContent(
      tester,
      ScrollAwareScaffold(
        appBar: AppBar(title: const Text('阅读')),
        body: Builder(
          builder: (context) {
            pageChrome = ScrollAwareChrome.maybeOf(context)!;
            return contentList();
          },
        ),
      ),
      shell: true,
    );
    final bottomAnimation = tester
        .widget<SizeTransition>(bottomNavigation)
        .sizeFactor;
    expect(identical(pageChrome.animation, bottomAnimation), isTrue);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(bottomAnimation.value, inExclusiveRange(0, 1));
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight,
      closeTo(48 + 8 * bottomAnimation.value, 0.001),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(bottomNavigation).height, 0);
    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 48);
    await wheel(tester, -1);
    expect(tester.getSize(bottomNavigation).height, greaterThan(0));
    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 56);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'collapsible filters keep input state and return on upward scroll',
    (tester) async {
      final input = TextEditingController(text: '保留查询');
      addTearDown(input.dispose);
      await showContent(
        tester,
        ScrollAwareScaffold(
          appBar: AppBar(title: const Text('搜索')),
          body: Column(
            children: [
              ScrollChromeCollapse(
                key: const ValueKey('filters'),
                child: SizedBox(
                  height: 72,
                  child: TextField(controller: input),
                ),
              ),
              Expanded(child: contentList()),
            ],
          ),
        ),
      );
      await wheel(tester, 120);
      expect(tester.getSize(find.byKey(const ValueKey('filters'))).height, 0);
      expect(find.byType(TextField).hitTestable(), findsNothing);
      expect(input.text, '保留查询');
      await wheel(tester, -1);
      expect(tester.getSize(find.byKey(const ValueKey('filters'))).height, 72);
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      expect(input.text, '保留查询');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'auxiliary toolbar selectors use the shared horizontal collapse',
    (tester) async {
      await showContent(
        tester,
        ScrollAwareScaffold(
          appBar: AppBar(
            title: const Text('动态'),
            actions: const [
              ScrollChromeCollapse(
                key: ValueKey('toolbar_selector'),
                axis: Axis.horizontal,
                child: SizedBox(width: 160, child: Text('全站 好友 我的')),
              ),
            ],
          ),
          body: contentList(),
        ),
      );
      await wheel(tester, 120);
      expect(
        tester.getSize(find.byKey(const ValueKey('toolbar_selector'))).width,
        0,
      );
      await wheel(tester, -1);
      expect(
        tester.getSize(find.byKey(const ValueKey('toolbar_selector'))).width,
        160,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('detail sliver toolbar and pinned tabs reuse shared compaction', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await showContent(
      tester,
      DefaultTabController(
        length: 2,
        child: Builder(
          builder: (context) => MonoDetailScaffold(
            scrollController: controller,
            tabController: DefaultTabController.of(context),
            tabs: const [
              MonoDetailTab(label: '概览', icon: Icons.home),
              MonoDetailTab(label: '讨论', icon: Icons.chat),
            ],
            tabChildren: [contentList(), const SizedBox()],
            selectedTabIndex: 0,
            showCollapsedTitle: true,
            title: '详情',
            header: const SizedBox(height: 122, child: Text('条目信息')),
            contentSizedHeader: true,
          ),
        ),
      ),
    );
    expect(find.byType(MonoDetailTabBar), findsOneWidget);
    expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isTrue);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(TabBar)),
        scrollDelta: const Offset(100, 0),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<SliverAppBar>(find.byType(SliverAppBar)).toolbarHeight,
      56,
    );
    expect(find.text('概览').hitTestable(), findsOneWidget);
    await wheel(tester, 240);
    expect(
      tester.widget<SliverAppBar>(find.byType(SliverAppBar)).toolbarHeight,
      48,
    );
    expect(find.text('概览').hitTestable(), findsNothing);
    await wheel(tester, -1);
    expect(
      tester.widget<SliverAppBar>(find.byType(SliverAppBar)).toolbarHeight,
      56,
    );
    expect(find.text('概览').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('native web scroll follows the same down and slight-up rules', (
    tester,
  ) async {
    late ScrollChromeData chrome;
    await showContent(
      tester,
      ScrollAwareScaffold(
        appBar: AppBar(title: const Text('网页')),
        body: Builder(
          builder: (context) {
            chrome = ScrollAwareChrome.maybeOf(context)!;
            return contentList();
          },
        ),
      ),
    );
    chrome.handleNativeScroll(100);
    await tester.pumpAndSettle();
    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 48);
    chrome.handleNativeScroll(99);
    await tester.pumpAndSettle();
    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 56);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'navigation recovers when compaction makes content stop scrolling',
    (tester) async {
      await showContent(
        tester,
        ScrollAwareScaffold(
          appBar: AppBar(title: const Text('阅读')),
          body: Column(
            children: [
              const ScrollChromeCollapse(child: SizedBox(height: 220)),
              Expanded(child: contentList(itemCount: 7)),
            ],
          ),
        ),
        shell: true,
      );
      await wheel(tester, 20);
      expect(tester.getSize(bottomNavigation).height, greaterThan(0));
      expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 56);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'non-scrollable embedded grids do not reopen chrome while reading',
    (tester) async {
      await showContent(
        tester,
        ScrollAwareScaffold(
          appBar: AppBar(title: const Text('发现')),
          body: ListView(
            key: const ValueKey('reading_list'),
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: const [Text('封面一'), Text('封面二')],
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      );
      await wheel(tester, 120);
      expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 48);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'wide layouts compact the same toolbar and keep the navigation rail',
    (tester) async {
      await showContent(
        tester,
        ScrollAwareScaffold(
          appBar: AppBar(title: const Text('阅读')),
          body: contentList(),
        ),
        shell: true,
        size: const Size(900, 600),
      );
      await wheel(tester, 120);
      expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 48);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('首页').hitTestable(), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await wheel(tester, -1);
      expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 56);
      expect(tester.takeException(), isNull);
    },
  );

  test('all page scaffolds use the shared reading layout', () {
    final unsharedScaffold = RegExp(r'\bScaffold\s*\(');
    final pages = Directory(
      'lib/pages',
    ).listSync().whereType<File>().where((file) => file.path.endsWith('.dart'));
    for (final page in pages) {
      expect(
        unsharedScaffold.hasMatch(page.readAsStringSync()),
        isFalse,
        reason:
            '${page.path} must reuse ScrollAwareScaffold or MonoDetailScaffold',
      );
    }
  });
}
