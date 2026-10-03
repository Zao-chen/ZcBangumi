import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/bangumi_mirror_settings.dart';
import 'package:zc_bangumi/services/bangumi_endpoint_service.dart';
import 'package:zc_bangumi/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('official is the default and the preset covers all services', () {
    const official = BangumiMirrorSettings();
    const mirror = BangumiMirrorSettings(
      source: BangumiMirrorSource.bangumiVip,
    );
    expect(official.isOfficial, isTrue);
    expect(
      official.endpoints[BangumiServiceKind.api].toString(),
      'https://api.bgm.tv',
    );
    expect(
      mirror.endpoints[BangumiServiceKind.web].toString(),
      'https://bangumi.vip',
    );
    expect(
      mirror.endpoints[BangumiServiceKind.fast].toString(),
      'https://fast.bangumi.vip',
    );
  });

  test('custom domain generates services and honors overrides and ports', () {
    const settings = BangumiMirrorSettings(
      source: BangumiMirrorSource.custom,
      customWeb: ' mirror.example:8443/ ',
      customApi: 'https://api.other.example:9443',
    );
    expect(
      settings.endpoints[BangumiServiceKind.web].toString(),
      'https://mirror.example:8443',
    );
    expect(
      settings.endpoints[BangumiServiceKind.next].toString(),
      'https://next.mirror.example:8443',
    );
    expect(
      settings.endpoints[BangumiServiceKind.api].toString(),
      'https://api.other.example:9443',
    );
    expect(
      BangumiMirrorSettings.fromJson(settings.toJson()).fingerprint,
      settings.fingerprint,
    );
  });

  test('rejects HTTP, paths, user info, query, fragment and invalid ports', () {
    for (final input in [
      '',
      'http://mirror.example',
      'https://mirror.example/api',
      'https://user:pass@mirror.example',
      'https://mirror.example?q=1',
      'https://mirror.example#part',
      'https://mirror.example:0',
      'https://mirror.example:65536',
    ]) {
      expect(
        () => BangumiMirrorSettings.normalizeBaseUrl(input),
        throwsFormatException,
        reason: input,
      );
    }
  });

  test(
    'unconfirmed saved mirrors never restore with existing credentials',
    () async {
      SharedPreferences.setMockInitialValues({
        'bangumi_mirror_settings': '{"source":"bangumiVip"}',
        'access_token': 'test-token',
      });
      final storage = StorageService();
      await storage.init();
      final service = BangumiEndpointService(storage: storage);
      expect(service.settings.isOfficial, isTrue);
      expect(storage.accessToken, 'test-token');
    },
  );

  test(
    'consent, endpoints and history restore without clearing data or auth',
    () async {
      SharedPreferences.setMockInitialValues({'access_token': 'test-token'});
      final storage = StorageService();
      await storage.init();
      final service = BangumiEndpointService(storage: storage);
      const custom = BangumiMirrorSettings(
        source: BangumiMirrorSource.custom,
        customWeb: 'mirror.example:8443',
      );
      await expectLater(service.applySettings(custom), throwsStateError);
      await service.applySettings(custom, acceptRisk: true);
      await storage.setCache('subject', {
        'images': {'large': 'https://lain.mirror.example:8443/pic/cover.jpg'},
        'topicUrl': 'https://mirror.example:8443/group/topic/123',
        'content': 'https://mirror.example:8443/group/topic/123',
        'custom_text': 'https://mirror.example:8443/group/topic/123',
        'external_url': 'https://external.example/image.jpg',
      });
      final restored = BangumiEndpointService(storage: storage);
      expect(restored.settings.fingerprint, custom.fingerprint);
      expect(restored.hasConsent(custom), isTrue);
      final cached = storage.getCache('subject') as Map;
      expect(cached['images']['large'], 'https://lain.bgm.tv/pic/cover.jpg');
      expect(cached['topicUrl'], 'https://bgm.tv/group/topic/123');
      expect(cached['content'], 'https://mirror.example:8443/group/topic/123');
      expect(cached['custom_text'], cached['content']);
      expect(cached['external_url'], 'https://external.example/image.jpg');
      await restored.applySettings(const BangumiMirrorSettings());
      final official = BangumiEndpointService(storage: storage);
      expect(
        official.resolveUrl('https://mirror.example:8443/subject/123'),
        'https://bgm.tv/subject/123',
      );
      expect(storage.accessToken, 'test-token');
      expect(storage.getCache('subject'), isNotNull);
    },
  );

  test('changed service addresses require a new consent', () async {
    final service = BangumiEndpointService();
    const first = BangumiMirrorSettings(
      source: BangumiMirrorSource.custom,
      customWeb: 'mirror.example',
    );
    const changed = BangumiMirrorSettings(
      source: BangumiMirrorSource.custom,
      customWeb: 'mirror.example',
      customApi: 'https://api.other.example',
    );
    await service.applySettings(first, acceptRisk: true);
    expect(service.hasConsent(changed), isFalse);
    await expectLater(service.applySettings(changed), throwsStateError);
    expect(service.settings.fingerprint, first.fingerprint);
  });

  test(
    'exact hosts only, encoded paths and query fragments are preserved',
    () async {
      final service = BangumiEndpointService();
      await service.applySettings(
        const BangumiMirrorSettings(source: BangumiMirrorSource.bangumiVip),
        acceptRisk: true,
      );
      expect(
        service.resolveUrl('https://bangumi.tv/subject/1?a=x%2Fy#part'),
        'https://bangumi.vip/subject/1?a=x%2Fy#part',
      );
      expect(
        service.resolveUrl('//lain.bgm.tv/r/200/pic/a.jpg'),
        'https://lain.bangumi.vip/r/200/pic/a.jpg',
      );
      for (final url in [
        'https://bgm.tv.evil.example/subject/1',
        'https://evil.bgm.tv/subject/1',
        'https://external.example/bg m.tv',
        'https://bgm.tv:8443/subject/1',
        'https://bgm.tv:80/subject/1',
        'http://bgm.tv:443/subject/1',
      ]) {
        expect(service.resolveUrl(url), url);
      }
      await service.applySettings(const BangumiMirrorSettings());
      expect(
        service.resolveUrl('https://api.bangumi.vip/v0/subjects/1'),
        'https://api.bgm.tv/v0/subjects/1',
      );
    },
  );

  test(
    'HTML rewrites attributes but never ordinary text or external resources',
    () async {
      final service = BangumiEndpointService();
      await service.applySettings(
        const BangumiMirrorSettings(source: BangumiMirrorSource.bangumiVip),
        acceptRisk: true,
      );
      final html = service.rewriteHtml(
        '<p>https://bgm.tv/subject/1</p><a href="/subject/1">标题</a><img src="//lain.bgm.tv/a.jpg"><img src="https://external.example/a.jpg">',
      );
      expect(html, contains('<p>https://bgm.tv/subject/1</p>'));
      expect(html, contains('href="https://bangumi.vip/subject/1"'));
      expect(html, contains('src="https://lain.bangumi.vip/a.jpg"'));
      expect(html, contains('src="https://external.example/a.jpg"'));
      final dataSrcset = 'data:image/png;base64,AAA 1x, /pic/cover.jpg 2x';
      expect(
        service.rewriteHtml('<img srcset="$dataSrcset">'),
        contains('srcset="$dataSrcset"'),
      );
    },
  );

  test(
    'HTML rewrites relative srcset candidates through the image mirror',
    () async {
      final service = BangumiEndpointService();
      await service.applySettings(
        const BangumiMirrorSettings(source: BangumiMirrorSource.bangumiVip),
        acceptRisk: true,
      );

      final html = service.rewriteHtml(
        '<img srcset="/pic/cover-small.jpg 1x, /pic/cover-large.jpg 2x">',
      );

      expect(html, contains('https://bangumi.vip/pic/cover-small.jpg 1x'));
      expect(html, contains('https://bangumi.vip/pic/cover-large.jpg 2x'));
    },
  );
}
