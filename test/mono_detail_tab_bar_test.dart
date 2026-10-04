import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/widgets/mono_detail_scaffold.dart';

void main() {
  const labels = ['概述', '角色', '制作', '关联', '目录', '吐槽', '萌百'];

  Future<void> showTabs(WidgetTester tester, {double width = 320}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: labels.length,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('条目详情'),
              bottom: MonoDetailTabBar(
                tabs: labels.map((label) => Tab(text: label)).toList(),
              ),
            ),
            body: TabBarView(
              children: labels
                  .map((label) => Center(child: Text('页面 $label')))
                  .toList(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ScrollableState tabScrollState(WidgetTester tester) {
    return tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(MonoDetailTabBar),
        matching: find.byType(Scrollable),
      ),
    );
  }

  testWidgets('detail tabs keep their content width when the window resizes', (
    tester,
  ) async {
    await showTabs(tester, width: 800);
    final widths = tester
        .widgetList<Tab>(find.byType(Tab))
        .map((tab) => tester.getSize(find.byWidget(tab)).width)
        .toList();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.isScrollable, isTrue);
    expect(tabBar.tabAlignment, TabAlignment.start);
    expect(tabScrollState(tester).position.maxScrollExtent, 0);

    tester.view.physicalSize = const Size(320, 1000);
    await tester.pumpAndSettle();

    final resizedWidths = tester
        .widgetList<Tab>(find.byType(Tab))
        .map((tab) => tester.getSize(find.byWidget(tab)).width)
        .toList();
    expect(resizedWidths, widths);
    expect(tabScrollState(tester).position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('overflow tabs can be dragged and selected', (tester) async {
    await showTabs(tester);
    await tester.drag(find.byType(TabBar), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(tabScrollState(tester).position.pixels, greaterThan(0));
    expect(find.text('萌百').hitTestable(), findsOneWidget);
    await tester.tap(find.text('萌百'));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(MonoDetailTabBar));
    expect(DefaultTabController.of(context).index, 6);
    expect(find.text('页面 萌百').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop mouse drag scrolls overflowing detail tabs', (
    tester,
  ) async {
    await showTabs(tester);
    await tester.drag(
      find.byType(TabBar),
      const Offset(-220, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(tabScrollState(tester).position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal wheel events scroll overflowing detail tabs', (
    tester,
  ) async {
    await showTabs(tester);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(TabBar)),
        scrollDelta: const Offset(200, 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(tabScrollState(tester).position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('controller changes bring an offscreen detail tab into view', (
    tester,
  ) async {
    await showTabs(tester);
    final context = tester.element(find.byType(MonoDetailTabBar));
    DefaultTabController.of(context).animateTo(6);
    await tester.pumpAndSettle();

    expect(tabScrollState(tester).position.pixels, greaterThan(0));
    expect(find.text('萌百').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
