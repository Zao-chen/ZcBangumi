import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zc_bangumi/models/bangumi_mirror_settings.dart';
import 'package:zc_bangumi/services/bangumi_endpoint_service.dart';
import 'package:zc_bangumi/widgets/bangumi_content_view.dart';
import 'package:zc_bangumi/widgets/bangumi_network_image.dart';

void main() {
  Future<void> showContent(
    WidgetTester tester, {
    String text = '',
    String? html,
    double? smileSize,
    BangumiEndpointService? endpoints,
  }) async {
    Widget content = BangumiContentView(
      text: text,
      html: html,
      smileSize: smileSize,
      style: const TextStyle(fontSize: 16),
    );
    if (endpoints != null) {
      content = ChangeNotifierProvider<BangumiEndpointService>.value(
        value: endpoints,
        child: content,
      );
    }
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: content)));
    await tester.pump();
  }

  void expectSmileSizes(WidgetTester tester, double standardSize) {
    final images = tester.widgetList<BangumiNetworkImage>(
      find.byType(BangumiNetworkImage),
    );
    final standard = images.firstWhere(
      (image) => image.imageUrl.contains('/smiles/tv/'),
    );
    final large = images.firstWhere(
      (image) => image.imageUrl.contains('/smiles/musume/'),
    );
    expect(standard.width, standardSize);
    expect(standard.height, standardSize);
    expect(large.width, standardSize * 2);
    expect(large.height, standardSize * 2);
    expect(tester.getSize(find.byWidget(standard)), Size.square(standardSize));
    expect(tester.getSize(find.byWidget(large)), Size.square(standardSize * 2));
    expect(tester.takeException(), isNull);
  }

  for (final smileSize in [null, 20.0]) {
    testWidgets('plain-text large smiles use twice the size $smileSize', (
      tester,
    ) async {
      await showContent(
        tester,
        text: '普通 (bgm38) 大表情 (musume_1)',
        smileSize: smileSize,
      );
      expectSmileSizes(tester, smileSize ?? 16 * 1.35);
    });
  }

  for (final route in ['no provider', 'official', 'mirror']) {
    testWidgets('HTML large smiles use twice the size through $route', (
      tester,
    ) async {
      final endpoints = route == 'no provider'
          ? null
          : BangumiEndpointService(
              settings: route == 'mirror'
                  ? const BangumiMirrorSettings(
                      source: BangumiMirrorSource.bangumiVip,
                    )
                  : null,
            );
      if (route == 'mirror') {
        await endpoints!.applySettings(
          const BangumiMirrorSettings(source: BangumiMirrorSource.bangumiVip),
          acceptRisk: true,
        );
      }
      if (endpoints != null) addTearDown(endpoints.dispose);

      await showContent(
        tester,
        smileSize: 20,
        endpoints: endpoints,
        html:
            '<img src="https://bgm.tv/img/smiles/tv/15.gif" alt="(bgm38)">'
            '<img src="https://bgm.tv/img/smiles/musume/musume_1.gif" '
            'alt="(musume_1)" width="500" height="500" '
            'style="width: 500px; height: 500px;">',
      );
      expectSmileSizes(tester, 20);
      if (route == 'mirror') {
        final images = tester.widgetList<BangumiNetworkImage>(
          find.byType(BangumiNetworkImage),
        );
        expect(
          images.every((image) => image.imageUrl.contains('bangumi.vip')),
          isTrue,
        );
      }
    });
  }

  testWidgets('normal HTML images retain their requested dimensions', (
    tester,
  ) async {
    final endpoints = BangumiEndpointService();
    addTearDown(endpoints.dispose);
    await showContent(
      tester,
      endpoints: endpoints,
      html:
          '<img src="https://bgm.tv/pic/photo.jpg" '
          'style="width: 240px; height: 120px;">',
    );
    final image = tester.widget<BangumiNetworkImage>(
      find.byType(BangumiNetworkImage),
    );
    expect(image.width, 240);
    expect(image.height, 120);
    expect(tester.takeException(), isNull);
  });
}
