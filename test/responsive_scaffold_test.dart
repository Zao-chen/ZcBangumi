import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zc_bangumi/providers/connectivity_provider.dart';
import 'package:zc_bangumi/widgets/responsive_scaffold.dart';

void main() {
  final navigation = find.byKey(
    const ValueKey('scroll_aware_bottom_navigation'),
  );

  Widget readingList({
    String name = 'reading_list',
    ScrollController? controller,
    Axis axis = Axis.vertical,
    int itemCount = 80,
  }) {
    return ListView.builder(
      key: ValueKey(name),
      controller: controller,
      scrollDirection: axis,
      physics: const ClampingScrollPhysics(),
      itemExtent: 72,
      itemCount: itemCount,
      itemBuilder: (_, index) => Center(child: Text('$name $index')),
    );
  }

  Future<ValueNotifier<int>> showShell(
    WidgetTester tester, {
    required List<Widget> pages,
    Size size = const Size(400, 800),
    double bottomInset = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final connectivity = ConnectivityProvider(canReachBangumi: () => true);
    addTearDown(connectivity.dispose);
    final selectedIndex = ValueNotifier(0);
    addTearDown(selectedIndex.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ConnectivityProvider>.value(
        value: connectivity,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: EdgeInsets.only(bottom: bottomInset),
              viewPadding: EdgeInsets.only(bottom: bottomInset),
            ),
            child: child!,
          ),
          home: ValueListenableBuilder<int>(
            valueListenable: selectedIndex,
            builder: (_, currentIndex, _) => ResponsiveScaffold(
              currentIndex: currentIndex,
              onIndexChanged: (index) => selectedIndex.value = index,
              pages: pages,
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
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return selectedIndex;
  }

  Future<void> scrollWithWheel(
    WidgetTester tester,
    Finder list,
    Offset delta,
  ) async {
    await tester.sendEventToBinding(
      PointerScrollEvent(position: tester.getCenter(list), scrollDelta: delta),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('touch scroll hides the bar and releases its safe-area space', (
    tester,
  ) async {
    await showShell(
      tester,
      pages: [readingList(), const SizedBox()],
      bottomInset: 24,
    );
    final list = find.byKey(const ValueKey('reading_list'));
    final initialHeight = tester.getSize(navigation).height;
    final initialBodyHeight = tester.getSize(find.byType(IndexedStack)).height;
    expect(initialHeight, greaterThan(80));

    await tester.drag(list, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.getSize(navigation).height, 0);
    expect(
      tester.getSize(find.byType(IndexedStack)).height,
      closeTo(initialBodyHeight + initialHeight, 0.01),
    );
    expect(find.text('首页').hitTestable(), findsNothing);

    await tester.drag(list, const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(tester.getSize(navigation).height, initialHeight);
    expect(find.text('首页').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wheel scroll reveals the bar after just one pixel upward', (
    tester,
  ) async {
    await showShell(tester, pages: [readingList(), const SizedBox()]);
    final list = find.byKey(const ValueKey('reading_list'));
    await scrollWithWheel(tester, list, const Offset(0, 120));
    expect(tester.getSize(navigation).height, 0);
    await scrollWithWheel(tester, list, const Offset(0, -1));
    expect(tester.getSize(navigation).height, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal scrolling does not hide bottom navigation', (
    tester,
  ) async {
    await showShell(
      tester,
      pages: [
        readingList(axis: Axis.horizontal),
        const SizedBox(),
      ],
    );
    final initialHeight = tester.getSize(navigation).height;
    await tester.drag(
      find.byKey(const ValueKey('reading_list')),
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(navigation).height, initialHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reversing a drag reveals navigation before hiding finishes', (
    tester,
  ) async {
    await showShell(tester, pages: [readingList(), const SizedBox()]);
    final list = find.byKey(const ValueKey('reading_list'));
    final gesture = await tester.startGesture(tester.getCenter(list));
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      tester.widget<SizeTransition>(navigation).sizeFactor.status,
      AnimationStatus.reverse,
    );
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.widget<SizeTransition>(navigation).sizeFactor.status,
      AnimationStatus.forward,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getSize(navigation).height, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested vertical scrolling also controls navigation', (
    tester,
  ) async {
    await showShell(
      tester,
      pages: [
        NestedScrollView(
          headerSliverBuilder: (_, _) => [
            const SliverAppBar(expandedHeight: 220, pinned: true),
          ],
          body: readingList(),
        ),
        const SizedBox(),
      ],
    );
    final list = find.byKey(const ValueKey('reading_list'));
    await tester.drag(list, const Offset(0, -40));
    await tester.pumpAndSettle();
    expect(tester.getSize(navigation).height, 0);
    await scrollWithWheel(tester, list, const Offset(0, -1));
    expect(tester.getSize(navigation).height, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tab changes show navigation and ignore inactive-page scrolling',
    (tester) async {
      final firstController = ScrollController();
      addTearDown(firstController.dispose);
      final selectedIndex = await showShell(
        tester,
        pages: [
          readingList(controller: firstController),
          readingList(name: 'second_list'),
        ],
      );
      await scrollWithWheel(
        tester,
        find.byKey(const ValueKey('reading_list')),
        const Offset(0, 120),
      );
      expect(tester.getSize(navigation).height, 0);
      selectedIndex.value = 1;
      await tester.pumpAndSettle();
      expect(tester.getSize(navigation).height, greaterThan(0));

      await scrollWithWheel(
        tester,
        find.byKey(const ValueKey('second_list')),
        const Offset(0, 120),
      );
      expect(tester.getSize(navigation).height, 0);
      firstController.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.getSize(navigation).height, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'programmatic scrolling stays visible and returning to top shows it',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await showShell(
        tester,
        pages: [
          readingList(controller: controller),
          const SizedBox(),
        ],
      );
      controller.animateTo(
        120,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(navigation).height, greaterThan(0));
      await scrollWithWheel(
        tester,
        find.byKey(const ValueKey('reading_list')),
        const Offset(0, 120),
      );
      expect(tester.getSize(navigation).height, 0);
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.getSize(navigation).height, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('short content keeps navigation visible', (tester) async {
    await showShell(
      tester,
      pages: [readingList(itemCount: 2), const SizedBox()],
    );
    final initialHeight = tester.getSize(navigation).height;
    await tester.drag(
      find.byKey(const ValueKey('reading_list')),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(navigation).height, initialHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape navigation stays visible and portrait state resets', (
    tester,
  ) async {
    await showShell(tester, pages: [readingList(), const SizedBox()]);
    await scrollWithWheel(
      tester,
      find.byKey(const ValueKey('reading_list')),
      const Offset(0, 120),
    );
    expect(tester.getSize(navigation).height, 0);

    tester.view.physicalSize = const Size(900, 600);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await scrollWithWheel(
      tester,
      find.byKey(const ValueKey('reading_list')),
      const Offset(0, 120),
    );
    expect(find.text('首页').hitTestable(), findsOneWidget);

    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    expect(tester.getSize(navigation).height, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
