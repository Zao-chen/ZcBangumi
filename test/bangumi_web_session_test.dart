import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/models/bangumi_web_session.dart';

void main() {
  test('cookie matching preserves host and path semantics', () {
    const rootCookie = BangumiWebSessionCookie(
      name: 'root',
      value: 'a',
      domain: '.bgm.tv',
      path: '/',
    );
    const deepCookie = BangumiWebSessionCookie(
      name: 'deep',
      value: 'b',
      domain: '.bgm.tv',
      path: '/group/topic',
    );

    expect(rootCookie.matchesUri(Uri.parse('https://bgm.tv/group/topic/1')), isTrue);
    expect(deepCookie.matchesUri(Uri.parse('https://bgm.tv/group/topic/1')), isTrue);
    expect(deepCookie.matchesUri(Uri.parse('https://bgm.tv/subject/1')), isFalse);
    expect(rootCookie.matchesUri(Uri.parse('https://example.com/group/topic/1')), isFalse);
  });

  test('buildCookieHeaderForUri keeps multiple matching cookies ordered by path', () {
    final session = BangumiWebSession(
      username: 'tester',
      uid: 1,
      capturedAt: DateTime(2026, 3, 13),
      validatedAt: DateTime(2026, 3, 13),
      primaryHost: 'bgm.tv',
      cookies: const [
        BangumiWebSessionCookie(
          name: 'sid',
          value: 'root',
          domain: '.bgm.tv',
          path: '/',
        ),
        BangumiWebSessionCookie(
          name: 'sid',
          value: 'topic',
          domain: '.bgm.tv',
          path: '/group/topic',
        ),
        BangumiWebSessionCookie(
          name: 'auth',
          value: 'ok',
          domain: '.bgm.tv',
          path: '/',
        ),
      ],
    );

    expect(
      session.buildCookieHeaderForUri(Uri.parse('https://bgm.tv/group/topic/1')),
      'sid=topic; auth=ok; sid=root',
    );
  });

  test('cookie expiry accepts Unix seconds timestamps from WebView stores', () {
    final futureSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    final session = BangumiWebSession(
      username: 'tester',
      uid: 1,
      capturedAt: DateTime(2026, 3, 13),
      validatedAt: DateTime(2026, 3, 13),
      primaryHost: 'bgm.tv',
      cookies: [
        BangumiWebSessionCookie(
          name: 'auth',
          value: 'ok',
          domain: '.bgm.tv',
          path: '/',
          expiresDate: futureSeconds,
        ),
      ],
    );

    expect(
      session.buildCookieHeaderForUri(Uri.parse('https://bgm.tv/')),
      'auth=ok',
    );
  });
}
