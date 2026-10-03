import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/models/bangumi_mirror_session.dart';
import 'package:zc_bangumi/models/bangumi_web_session.dart';

void main() {
  test(
    'mirror cookies enforce origin, host-only domain, path, expiry and TLS',
    () {
      final session = BangumiMirrorSession(
        fingerprint: 'profile',
        origin: 'https://mirror.example',
        userAgent: 'test',
        cookies: [
          const BangumiWebSessionCookie(
            name: 'root',
            value: 'ok',
            domain: 'mirror.example',
            path: '/',
            isSecure: true,
          ),
          const BangumiWebSessionCookie(
            name: 'deep',
            value: 'ok',
            domain: '.mirror.example',
            path: '/group',
          ),
          const BangumiWebSessionCookie(
            name: 'foreign',
            value: 'no',
            domain: '.bgm.tv',
            path: '/',
          ),
          const BangumiWebSessionCookie(
            name: 'expired',
            value: 'no',
            domain: 'mirror.example',
            path: '/',
            expiresDate: 1,
          ),
          const BangumiWebSessionCookie(
            name: 'empty',
            value: 'no',
            domain: '',
            path: '/',
          ),
        ],
      );
      expect(
        session.cookieHeader(Uri.parse('https://mirror.example/group/topic/1')),
        'deep=ok; root=ok',
      );
      expect(
        session.cookieHeader(Uri.parse('https://mirror.example/subject/1')),
        'root=ok',
      );
      expect(
        session.cookieHeader(Uri.parse('https://api.mirror.example/group')),
        isNull,
      );
      expect(
        session.cookieHeader(Uri.parse('https://mirror.example:8443/group')),
        isNull,
      );
      expect(
        session.cookieHeader(Uri.parse('http://mirror.example/group')),
        isNull,
      );
      expect(
        BangumiMirrorSession.fromJson(
          session.toJson(),
        ).cookieHeader(Uri.parse('https://mirror.example/group')),
        'deep=ok; root=ok',
      );
    },
  );
}
