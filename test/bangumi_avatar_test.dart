import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/widgets/bangumi_avatar.dart';
import 'package:zc_bangumi/widgets/bangumi_network_image.dart';
import 'package:zc_bangumi/widgets/bangumi_post_widgets.dart';

void main() {
  Future<void> showAvatar(
    WidgetTester tester,
    Widget avatar, {
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(body: Center(child: avatar)),
      ),
    );
    await tester.pump();
  }

  void expectShape(WidgetTester tester, double size) {
    final avatar = find.byType(BangumiAvatar);
    expect(tester.getSize(avatar), Size.square(size));
    final clip = tester.widget<ClipRRect>(
      find.descendant(of: avatar, matching: find.byType(ClipRRect)),
    );
    expect(clip.borderRadius, BorderRadius.circular(size * 0.24));
    expect(clip.clipBehavior, Clip.antiAlias);
    expect(find.byType(CircleAvatar), findsNothing);
    expect(find.byType(ClipOval), findsNothing);
    expect(tester.takeException(), isNull);
  }

  for (final size in [32.0, 40.0, 44.0, 48.0, 72.0]) {
    testWidgets('missing avatars use proportional square corners at $size', (
      tester,
    ) async {
      await showAvatar(tester, BangumiAvatar(url: '', size: size));
      expectShape(tester, size);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });

    testWidgets('avatar skeleton uses the same corners at $size', (
      tester,
    ) async {
      await showAvatar(tester, BangumiAvatar.skeleton(size: size));
      expectShape(tester, size);
      expect(find.byType(Icon), findsNothing);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('avatar placeholders follow the $brightness theme', (
      tester,
    ) async {
      await showAvatar(
        tester,
        const BangumiAvatar(url: '', size: 48),
        brightness: brightness,
      );
      final avatar = find.byType(BangumiAvatar);
      final context = tester.element(avatar);
      final placeholder = tester.widget<Container>(
        find.descendant(of: avatar, matching: find.byType(Container)),
      );
      expect(
        placeholder.color,
        Theme.of(context).colorScheme.surfaceContainerHighest,
      );
      expectShape(tester, 48);
    });
  }

  testWidgets('loading and failed images stay within the common square clip', (
    tester,
  ) async {
    const avatar = BangumiAvatar(
      url: 'https://example.invalid/avatar.png',
      size: 48,
      placeholderIcon: Icons.forum_outlined,
    );
    await showAvatar(tester, avatar);
    expectShape(tester, 48);
    final image = tester.widget<BangumiNetworkImage>(
      find.byType(BangumiNetworkImage),
    );
    expect(image.fit, BoxFit.cover);
    final context = tester.element(find.byType(BangumiAvatar));
    final loading = image.placeholder!(context, avatar.url) as Container;
    final failed =
        image.errorWidget!(context, avatar.url, StateError('image failed'))
            as Container;
    expect(loading.color, failed.color);
    expect(loading.child, isNull);
    expect((failed.child as Icon).icon, Icons.forum_outlined);
  });

  testWidgets('post avatars retain their original dimensions and corners', (
    tester,
  ) async {
    await showAvatar(tester, const BangumiPostAvatar(url: '', size: 44));
    expect(find.byType(BangumiAvatar), findsOneWidget);
    expectShape(tester, 44);
  });

  test('avatar surfaces cannot reintroduce independent circular avatars', () {
    final circularAvatar = RegExp(r'\b(?:CircleAvatar|ClipOval)\s*\(');
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      expect(
        circularAvatar.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: '${file.path} must use the shared rounded-square avatar',
      );
    }
    for (final path in [
      'lib/pages/character_page.dart',
      'lib/pages/index_page.dart',
      'lib/pages/profile_page.dart',
      'lib/pages/rakuen_page.dart',
      'lib/pages/subject_page.dart',
      'lib/pages/timeline_page.dart',
      'lib/widgets/bangumi_index_list_view.dart',
      'lib/widgets/bangumi_post_widgets.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source.contains('BangumiAvatar'), isTrue, reason: path);
      expect(source.contains('BoxShape.circle'), isFalse, reason: path);
    }
  });
}
