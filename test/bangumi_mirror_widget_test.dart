import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zc_bangumi/models/bangumi_mirror_settings.dart';
import 'package:zc_bangumi/services/bangumi_endpoint_service.dart';
import 'package:zc_bangumi/widgets/bangumi_mirror_settings_card.dart';
import 'package:zc_bangumi/widgets/bangumi_network_image.dart';

void main() {
  Future<void> showCard(
    WidgetTester tester,
    BangumiEndpointService endpoints, {
    Future<void> Function(BuildContext, BangumiServiceKind)? onVerify,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BangumiMirrorSettingsCard(
              endpoints: endpoints,
              onVerify: onVerify,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.byKey(const ValueKey('mirror-source')));
    await tester.tap(find.byKey(const ValueKey('mirror-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('mirror-save')));
    await tester.tap(find.byKey(const ValueKey('mirror-save')));
    await tester.pumpAndSettle();
  }

  testWidgets('risk cancellation keeps the official route and no consent', (
    tester,
  ) async {
    final endpoints = BangumiEndpointService();
    await showCard(tester, endpoints);
    await choose(tester, 'bangumi.vip');
    await save(tester);
    expect(find.text('第三方镜像安全风险'), findsOneWidget);
    expect(find.textContaining('api.bangumi.vip'), findsWidgets);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(endpoints.settings.isOfficial, isTrue);
    expect(
      endpoints.hasConsent(
        const BangumiMirrorSettings(source: BangumiMirrorSource.bangumiVip),
      ),
      isFalse,
    );
  });

  testWidgets('risk acceptance enables the preset and its verification entry', (
    tester,
  ) async {
    final endpoints = BangumiEndpointService();
    BangumiServiceKind? verified;
    await showCard(
      tester,
      endpoints,
      onVerify: (context, kind) async {
        verified = kind;
      },
    );
    await choose(tester, 'bangumi.vip');
    await save(tester);
    await tester.tap(find.byKey(const ValueKey('mirror-confirm-risk')));
    await tester.pumpAndSettle();
    expect(endpoints.settings.source, BangumiMirrorSource.bangumiVip);
    expect(endpoints.hasConsent(endpoints.settings), isTrue);
    await tester.tap(find.text('连接详情'));
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('mirror-verify-web'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(verified, BangumiServiceKind.web);
  });

  testWidgets('custom invalid address is rejected before asking for consent', (
    tester,
  ) async {
    final endpoints = BangumiEndpointService();
    await showCard(tester, endpoints);
    await choose(tester, '自定义镜像');
    await tester.enterText(
      find.byKey(const ValueKey('mirror-web-address')),
      'http://mirror.example/api',
    );
    await save(tester);
    expect(find.textContaining('地址必须是 HTTPS 根地址'), findsOneWidget);
    expect(find.text('第三方镜像安全风险'), findsNothing);
    expect(endpoints.settings.isOfficial, isTrue);
  });

  testWidgets('default mirror settings hide addresses and long explanations', (
    tester,
  ) async {
    final endpoints = BangumiEndpointService();
    await showCard(tester, endpoints);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.text('尚未检查'), findsOneWidget);
    expect(find.textContaining('Token'), findsNothing);
    expect(find.textContaining('检查时间'), findsNothing);
    await tester.tap(find.text('连接详情'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNWidgets(5));
    expect(find.text('https://bgm.tv'), findsOneWidget);
    await tester.tap(find.text('连接详情'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('help and session cleanup are grouped under the more menu', (
    tester,
  ) async {
    final endpoints = BangumiEndpointService();
    await endpoints.applySettings(
      const BangumiMirrorSettings(source: BangumiMirrorSource.bangumiVip),
      acceptRisk: true,
    );
    await showCard(tester, endpoints);
    expect(find.text('使用说明'), findsNothing);
    expect(find.text('清除验证会话'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mirror-more')));
    await tester.pumpAndSettle();
    expect(find.text('使用说明'), findsOneWidget);
    expect(find.text('清除验证会话'), findsOneWidget);
    await tester.tap(find.text('使用说明'));
    await tester.pumpAndSettle();
    expect(find.text('镜像使用说明'), findsOneWidget);
    expect(find.textContaining('不发送 Token 或登录 Cookie'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('镜像使用说明'), findsNothing);
  });

  testWidgets('verification challenges stay visible in the collapsed summary', (
    tester,
  ) async {
    final endpoints = BangumiEndpointService();
    await endpoints.applySettings(
      const BangumiMirrorSettings(source: BangumiMirrorSource.bangumiVip),
      acceptRisk: true,
    );
    endpoints.reportChallenge(
      BangumiMirrorChallengeException(
        BangumiServiceKind.web,
        endpoints.baseUri(BangumiServiceKind.web),
      ),
    );
    BangumiServiceKind? verified;
    await showCard(
      tester,
      endpoints,
      onVerify: (context, kind) async {
        verified = kind;
      },
    );
    expect(find.textContaining('1 项需验证'), findsOneWidget);
    expect(find.byKey(const ValueKey('mirror-verify-web')), findsNothing);
    await tester.tap(find.text('连接详情'));
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('mirror-verify-web'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(verified, BangumiServiceKind.web);
  });

  testWidgets(
    'an advanced address change requires a fresh consent and can be cancelled',
    (tester) async {
      final endpoints = BangumiEndpointService();
      await endpoints.applySettings(
        const BangumiMirrorSettings(
          source: BangumiMirrorSource.custom,
          customWeb: 'https://mirror.example',
        ),
        acceptRisk: true,
      );
      final original = endpoints.settings.fingerprint;
      await showCard(tester, endpoints);
      await tester.tap(find.byKey(const ValueKey('mirror-advanced')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('mirror-api-address')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('mirror-api-address')),
        'https://api.other.example',
      );
      await save(tester);
      expect(find.text('第三方镜像安全风险'), findsOneWidget);
      expect(find.textContaining('api.other.example'), findsWidgets);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(endpoints.settings.fingerprint, original);
    },
  );

  testWidgets(
    'images follow the selected endpoint without changing their canonical cache key',
    (tester) async {
      final endpoints = BangumiEndpointService();
      await tester.pumpWidget(
        ChangeNotifierProvider<BangumiEndpointService>.value(
          value: endpoints,
          child: const MaterialApp(
            home: Scaffold(
              body: BangumiNetworkImage(
                imageUrl: 'https://lain.bgm.tv/pic/cover.jpg',
                width: 30,
                height: 30,
              ),
            ),
          ),
        ),
      );
      var image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.imageUrl, 'https://lain.bgm.tv/pic/cover.jpg');
      await endpoints.applySettings(
        const BangumiMirrorSettings(source: BangumiMirrorSource.bangumiVip),
        acceptRisk: true,
      );
      await tester.pump();
      image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.imageUrl, 'https://lain.bangumi.vip/pic/cover.jpg');
      expect(image.cacheKey, 'https://lain.bgm.tv/pic/cover.jpg');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
