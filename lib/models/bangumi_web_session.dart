class BangumiWebSessionCookie {
  final String name;
  final String value;
  final String domain;
  final String path;
  final int? expiresDate;
  final bool isSecure;
  final bool isHttpOnly;

  const BangumiWebSessionCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    this.expiresDate,
    this.isSecure = false,
    this.isHttpOnly = false,
  });

  factory BangumiWebSessionCookie.fromJson(Map<String, dynamic> json) {
    return BangumiWebSessionCookie(
      name: json['name'] as String? ?? '',
      value: json['value'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
      path: json['path'] as String? ?? '/',
      expiresDate: (json['expiresDate'] as num?)?.toInt(),
      isSecure: json['isSecure'] as bool? ?? false,
      isHttpOnly: json['isHttpOnly'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'value': value,
      'domain': domain,
      'path': path,
      'expiresDate': expiresDate,
      'isSecure': isSecure,
      'isHttpOnly': isHttpOnly,
    };
  }

  bool matchesUri(Uri uri) {
    if (name.isEmpty) return false;
    if (_isExpired) return false;
    if (!_matchesHost(uri.host)) return false;
    return _matchesPath(uri.path.isEmpty ? '/' : uri.path);
  }

  bool get _isExpired {
    if (expiresDate == null) return false;
    final normalizedExpiresDate = _normalizeExpiresDate(expiresDate!);
    return DateTime.now().millisecondsSinceEpoch >= normalizedExpiresDate;
  }

  static int _normalizeExpiresDate(int rawValue) {
    // Some WebView implementations report Unix seconds while others use
    // Unix milliseconds. Normalize both into milliseconds before comparing.
    if (rawValue > 0 && rawValue < 100000000000) {
      return rawValue * 1000;
    }
    return rawValue;
  }

  bool _matchesHost(String host) {
    final normalizedHost = host.toLowerCase();
    final normalizedDomain = domain.trim().toLowerCase().replaceFirst(
      RegExp(r'^\.+'),
      '',
    );
    if (normalizedDomain.isEmpty) return true;
    return normalizedHost == normalizedDomain ||
        normalizedHost.endsWith('.$normalizedDomain');
  }

  bool _matchesPath(String requestPath) {
    final normalizedCookiePath = path.isEmpty ? '/' : path;
    final normalizedRequestPath = requestPath.isEmpty ? '/' : requestPath;
    return normalizedRequestPath == normalizedCookiePath ||
        normalizedRequestPath.startsWith(
          normalizedCookiePath.endsWith('/')
              ? normalizedCookiePath
              : '$normalizedCookiePath/',
        ) ||
        normalizedCookiePath == '/';
  }
}

class BangumiWebSession {
  final String username;
  final int uid;
  final DateTime capturedAt;
  final DateTime validatedAt;
  final String primaryHost;
  final List<BangumiWebSessionCookie> cookies;

  const BangumiWebSession({
    required this.username,
    required this.uid,
    required this.capturedAt,
    required this.validatedAt,
    required this.primaryHost,
    required this.cookies,
  });

  bool get hasCookies => cookies.isNotEmpty;
  bool get isValid => username.isNotEmpty && uid > 0 && cookies.isNotEmpty;

  factory BangumiWebSession.fromJson(Map<String, dynamic> json) {
    return BangumiWebSession(
      username: json['username'] as String? ?? '',
      uid: (json['uid'] as num?)?.toInt() ?? 0,
      capturedAt: DateTime.tryParse(json['capturedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      validatedAt: DateTime.tryParse(json['validatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      primaryHost: json['primaryHost'] as String? ?? 'bgm.tv',
      cookies: (json['cookies'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => BangumiWebSessionCookie.fromJson(
              item.map((key, value) => MapEntry('$key', value)),
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'uid': uid,
      'capturedAt': capturedAt.toIso8601String(),
      'validatedAt': validatedAt.toIso8601String(),
      'primaryHost': primaryHost,
      'cookies': cookies.map((cookie) => cookie.toJson()).toList(),
    };
  }

  BangumiWebSession copyWith({
    String? username,
    int? uid,
    DateTime? capturedAt,
    DateTime? validatedAt,
    String? primaryHost,
    List<BangumiWebSessionCookie>? cookies,
  }) {
    return BangumiWebSession(
      username: username ?? this.username,
      uid: uid ?? this.uid,
      capturedAt: capturedAt ?? this.capturedAt,
      validatedAt: validatedAt ?? this.validatedAt,
      primaryHost: primaryHost ?? this.primaryHost,
      cookies: cookies ?? this.cookies,
    );
  }

  List<BangumiWebSessionCookie> cookiesForUri(Uri uri) {
    final matches = cookies.where((cookie) => cookie.matchesUri(uri)).toList();
    matches.sort((a, b) {
      final pathLengthCompare = b.path.length.compareTo(a.path.length);
      if (pathLengthCompare != 0) return pathLengthCompare;
      return a.name.compareTo(b.name);
    });
    return matches;
  }

  String? buildCookieHeaderForUri(Uri uri) {
    final matches = cookiesForUri(uri);
    if (matches.isEmpty) return null;
    return matches
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
  }
}
