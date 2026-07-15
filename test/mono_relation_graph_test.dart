import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/widgets/mono_relation_graph.dart';

void main() {
  testWidgets('relation graph groups, expands, and collapses nodes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonoRelationGraph(
            graphId: 'subject:1:characters',
            centerTitle: '测试条目',
            nodes: [
              MonoRelationGraphNode(
                key: 'character:1',
                relation: '主角',
                title: '角色 A',
                placeholderIcon: Icons.person_outline,
                loadChildren: () async => const [
                  MonoRelationGraphNode(
                    key: 'subject:2',
                    relation: '出演作品',
                    title: '作品 B',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('测试条目'), findsOneWidget);
    expect(find.text('主角'), findsOneWidget);
    expect(find.text('角色 A'), findsOneWidget);
    expect(find.text('作品 B'), findsNothing);

    await tester.tap(find.byTooltip('展开'));
    await tester.pumpAndSettle();

    expect(find.text('出演作品'), findsOneWidget);
    expect(find.text('作品 B'), findsOneWidget);

    await tester.tap(find.text('主角'));
    await tester.pumpAndSettle();

    expect(find.text('角色 A'), findsNothing);
    expect(find.text('作品 B'), findsNothing);
  });

  testWidgets('relation view switcher keeps list and graph state available', (
    tester,
  ) async {
    var mode = MonoRelationViewMode.list;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: MonoRelationViewSwitcher(
              mode: mode,
              onModeChanged: (value) => setState(() => mode = value),
              itemCount: 2,
              listView: const Text('列表内容'),
              graphView: const Text('脑图内容'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('2 项'), findsOneWidget);
    expect(find.text('列表内容'), findsOneWidget);

    await tester.tap(find.text('脑图'));
    await tester.pumpAndSettle();

    expect(mode, MonoRelationViewMode.graph);
    expect(find.text('脑图内容'), findsOneWidget);
  });

  testWidgets('large third level relation groups start collapsed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonoRelationGraph(
            graphId: 'subject:1:persons',
            centerTitle: '测试条目',
            nodes: [
              MonoRelationGraphNode(
                key: 'person:1',
                relation: '声优',
                title: '人物 A',
                loadChildren: () async => List.generate(
                  20,
                  (index) => MonoRelationGraphNode(
                    key: 'subject:$index',
                    relation: '参与作品',
                    title: '作品 $index',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('展开'));
    await tester.pumpAndSettle();

    expect(find.text('参与作品'), findsOneWidget);
    expect(find.text('作品 0'), findsNothing);
    expect(find.byIcon(Icons.add_circle_outline), findsWidgets);

    await tester.tap(find.text('参与作品'));
    await tester.pumpAndSettle();

    expect(find.text('作品 0'), findsOneWidget);
    expect(find.text('作品 19'), findsOneWidget);
  });

  testWidgets('large root entity level starts collapsed by relation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonoRelationGraph(
            graphId: 'subject:1:persons',
            centerTitle: '测试条目',
            nodes: List.generate(
              40,
              (index) => MonoRelationGraphNode(
                key: 'person:$index',
                relation: '声优',
                title: '人物 $index',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('声优'), findsOneWidget);
    expect(find.text('人物 0'), findsNothing);
    expect(find.text('人物 39'), findsNothing);

    await tester.tap(find.text('声优'));
    await tester.pumpAndSettle();

    expect(find.text('人物 0'), findsOneWidget);
    expect(find.text('人物 39'), findsOneWidget);
  });

  testWidgets('fullscreen graph adapts and preserves the graph session', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonoRelationGraph(
            graphId: 'subject:1:characters',
            centerTitle: '测试条目',
            nodes: [
              MonoRelationGraphNode(
                key: 'character:1',
                relation: '主角',
                title: '角色 A',
                loadChildren: () async => const [
                  MonoRelationGraphNode(
                    key: 'subject:2',
                    relation: '出演作品',
                    title: '作品 B',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('展开'));
    await tester.pumpAndSettle();
    expect(find.text('作品 B'), findsOneWidget);

    await tester.tap(find.byTooltip('全屏查看'));
    await tester.pumpAndSettle();

    expect(find.text('测试条目 · 脑图'), findsOneWidget);
    expect(find.text('作品 B'), findsOneWidget);
    expect(find.byTooltip('全屏查看'), findsNothing);

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final beforeDrag = viewer.transformationController!.value.clone();
    await tester.drag(find.byType(InteractiveViewer), const Offset(-80, -60));
    await tester.pumpAndSettle();
    expect(
      viewer.transformationController!.value,
      isNot(equals(beforeDrag)),
      reason: '全屏脑图应允许横向和纵向自由拖拽',
    );

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('作品 B'), findsOneWidget);
    final desktopViewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final beforeDesktopDrag = desktopViewer.transformationController!.value
        .clone();
    await tester.drag(find.byType(InteractiveViewer), const Offset(90, 70));
    await tester.pumpAndSettle();
    expect(
      desktopViewer.transformationController!.value,
      isNot(equals(beforeDesktopDrag)),
      reason: '宽屏全屏脑图也应允许自由拖拽',
    );

    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.text('作品 B'), findsOneWidget);
    expect(find.byTooltip('全屏查看'), findsOneWidget);
  });
}
