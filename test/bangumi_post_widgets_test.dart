import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/models/comment.dart';
import 'package:zc_bangumi/widgets/bangumi_content_view.dart';
import 'package:zc_bangumi/widgets/bangumi_post_widgets.dart';

void main() {
  Comment comment({
    int id = 1,
    int state = 0,
    int replies = 0,
    List<Comment> replyItems = const [],
    Map<String, dynamic> user = const {
      'id': '42',
      'nickname': '测试用户',
      'avatar': '',
    },
  }) => Comment(
    id: id,
    content: state == 6 ? '' : '统一的吐槽正文',
    contentHtml: state == 6 ? null : '<p>统一的吐槽正文</p>',
    rating: 9,
    spoiler: 1,
    state: state,
    createdAt: DateTime(2026, 7, 16, 11, 5),
    updatedAt: DateTime(2026, 7, 17, 12, 6),
    user: user,
    usable: 1,
    replies: replies,
    replyItems: replyItems,
  );

  const post = BangumiPostData(
    id: '1',
    authorKey: '42',
    authorName: '很长的用户名也不能挤掉吐槽发布时间',
    avatarUrl: '',
    metaText: '#1  2026-7-16 11:05',
    content: '统一的吐槽正文，阅读时应保持清晰的字号和行距。',
    rating: 9,
    spoiler: true,
  );
  const reply = BangumiPostData(
    id: '2',
    authorKey: '43',
    authorName: '回复用户',
    avatarUrl: '',
    metaText: '#1-1  2026-7-16 11:06',
    content: '楼中楼正文',
  );

  Future<void> showCard(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double width = 400,
    double textScale = 1,
    BangumiPostData data = post,
    List<BangumiPostData> replies = const [reply],
    ValueChanged<BangumiPostData>? onUserTap,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.pink,
            brightness: brightness,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: BangumiPostCard(
              post: data,
              replies: replies,
              onUserTap: onUserTap,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('shared post metadata uses one floor and absolute-time format', () {
    expect(
      formatBangumiPostMeta(
        floorText: '#2',
        dateTime: DateTime(2026, 7, 16, 11, 5),
      ),
      '#2  2026-7-16 11:05',
    );
    expect(
      formatBangumiPostMeta(floorText: '#2-1', rawTime: '2026-07-16 11:06'),
      '#2-1  2026-7-16 11:06',
    );
  });

  test('comment adapter preserves metadata, html and exact odd ratings', () {
    final source = comment(replies: 3);
    final data = BangumiPostData.fromComment(source, floorText: '#2');
    expect(data.authorKey, '42');
    expect(data.metaText, '#2  2026-7-16 11:05');
    expect(data.contentHtml, source.contentHtml);
    expect(data.rating, 9);
    expect(data.spoiler, isTrue);
    expect(data.replyCount, 3);
    expect(
      BangumiPostData.fromComment(source, dateTime: source.updatedAt).metaText,
      '2026-7-17 12:06',
    );
  });

  test('loaded replies do not also show a reply count', () {
    final data = BangumiPostData.fromComment(
      comment(replies: 1, replyItems: [comment(id: 2)]),
    );
    expect(data.replyCount, 0);
  });

  test(
    'deleted comments retain a placeholder and invalid users are disabled',
    () {
      final data = BangumiPostData.fromComment(
        comment(state: 6, user: const {}),
      );
      expect(data.emptyContentLabel, '该评论已删除');
      expect(data.authorKey, isEmpty);
      expect(data.authorName, '未知用户');
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('comments reuse original Rakuen typography in $brightness', (
      tester,
    ) async {
      await showCard(tester, brightness: brightness);
      final context = tester.element(find.byType(BangumiPostCard));
      final colors = Theme.of(context).colorScheme;
      final bodies = tester
          .widgetList<BangumiContentView>(find.byType(BangumiContentView))
          .toList();
      expect(bodies.length, 2);
      expect(bodies.map((body) => body.style!.fontSize), [14, 13]);
      expect(bodies.map((body) => body.style!.height), [1.42, 1.4]);
      expect(bodies.every((body) => body.style!.color == null), isTrue);
      for (final entry in [post, reply].asMap().entries) {
        final data = entry.value;
        final author = find.text(data.authorName, findRichText: true);
        final metadata = find.text(data.metaText);
        final content = find.byWidgetPredicate(
          (widget) =>
              widget is BangumiContentView && widget.text == data.content,
        );
        expect(tester.getRect(author).top, tester.getRect(metadata).top);
        expect(
          tester.getRect(metadata).bottom,
          lessThan(tester.getRect(content).top),
        );
        expect(
          tester.getRect(metadata).left,
          greaterThan(tester.getRect(author).left),
        );
        final text = tester.widget<Text>(metadata);
        expect(text.style!.fontSize, entry.key == 0 ? 11 : 10);
        expect(text.style!.color, colors.onSurfaceVariant);
      }
      expect(find.text('9/10'), findsNothing);
      expect(find.byIcon(Icons.star), findsNWidgets(4));
      expect(find.byIcon(Icons.star_border), findsOneWidget);
      for (final star in tester.widgetList<Icon>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Icon &&
              (widget.icon == Icons.star || widget.icon == Icons.star_border),
        ),
      )) {
        expect(star.color, Colors.amber);
        expect(star.size, 12);
      }
      expect(find.text('剧透'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'original Rakuen avatar sizes and reply indentation are retained',
    (tester) async {
      await showCard(tester, width: 600);
      expect(find.text(post.metaText), findsOneWidget);
      expect(find.text(reply.metaText), findsOneWidget);
      final cardRect = tester.getRect(find.byType(BangumiPostCard));
      for (final data in [post, reply]) {
        final rect = tester.getRect(find.text(data.metaText));
        expect(rect.left, greaterThanOrEqualTo(cardRect.left));
        expect(rect.right, lessThanOrEqualTo(cardRect.right));
      }
      final avatars = tester
          .widgetList<BangumiPostAvatar>(find.byType(BangumiPostAvatar))
          .toList();
      expect(avatars.map((avatar) => avatar.size), [44, 32]);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('bangumi_nested_reply_2')))
            .left,
        tester.getRect(find.byType(BangumiPostAvatar).first).left + 44 + 12,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ordinary Rakuen posts do not gain comment-only decorations', (
    tester,
  ) async {
    await showCard(
      tester,
      data: const BangumiPostData(
        id: 'original',
        authorKey: '42',
        authorName: '超展开用户',
        avatarUrl: '',
        metaText: '#1  2026-7-16 11:05',
        content: '原来的超展开帖子',
      ),
      replies: const [],
    );
    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.byIcon(Icons.star_border), findsNothing);
    expect(find.text('剧透'), findsNothing);
    final block = tester.widget<BangumiPostBlock>(
      find.byType(BangumiPostBlock),
    );
    expect(block.avatarSize, 44);
    expect(block.titleFontSize, 14);
    expect(block.metaFontSize, 11);
    expect(block.contentFontSize, 14);
    expect(block.contentHeight, 1.42);
    expect(tester.takeException(), isNull);
  });

  testWidgets('author and avatar navigation remains available for replies', (
    tester,
  ) async {
    final opened = <String>[];
    await showCard(tester, onUserTap: (data) => opened.add(data.authorKey));
    await tester.tap(find.text(post.authorName, findRichText: true));
    await tester.tap(find.byType(BangumiPostAvatar).last);
    expect(opened, ['42', '43']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reply counts and deleted content use the shared layout', (
    tester,
  ) async {
    await showCard(
      tester,
      data: BangumiPostData.fromComment(comment(state: 6, replies: 2)),
      replies: const [],
    );
    expect(find.text('该评论已删除'), findsOneWidget);
    expect(find.text('2 条回复'), findsOneWidget);
    expect(find.text('2026-7-16 11:05'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
