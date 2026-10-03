import 'bangumi_web_session.dart';

class BangumiMirrorSession {
  const BangumiMirrorSession({
    required this.fingerprint,
    required this.origin,
    required this.userAgent,
    required this.cookies,
  });

  final String fingerprint;
  final String origin;
  final String userAgent;
  final List<BangumiWebSessionCookie> cookies;

  String get key => '$fingerprint|$origin';

  String? cookieHeader(Uri uri) {
    if (uri.origin != origin) return null;
    final matching =
        cookies.where((cookie) {
          if (cookie.domain.isEmpty) return false;
          if (cookie.isSecure && uri.scheme != 'https') return false;
          final domain = cookie.domain.toLowerCase();
          if (!domain.startsWith('.') && uri.host.toLowerCase() != domain) {
            return false;
          }
          return cookie.matchesUri(uri);
        }).toList()..sort(
          (first, second) => second.path.length.compareTo(first.path.length),
        );
    if (matching.isEmpty) return null;
    return matching
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
  }

  Map<String, dynamic> toJson() => {
    'fingerprint': fingerprint,
    'origin': origin,
    'user_agent': userAgent,
    'cookies': cookies.map((cookie) => cookie.toJson()).toList(),
  };

  factory BangumiMirrorSession.fromJson(Map<String, dynamic> json) {
    return BangumiMirrorSession(
      fingerprint: json['fingerprint'] as String,
      origin: json['origin'] as String,
      userAgent: json['user_agent'] as String,
      cookies: (json['cookies'] as List).whereType<Map>().map((cookie) {
        return BangumiWebSessionCookie.fromJson(
          Map<String, dynamic>.from(cookie),
        );
      }).toList(),
    );
  }
}
