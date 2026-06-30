class MikanSessionCookie {
  final String name;
  final String value;
  final String domain;
  final String path;
  final int? expiresDate;
  final bool isSecure;
  final bool isHttpOnly;

  const MikanSessionCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    this.expiresDate,
    this.isSecure = false,
    this.isHttpOnly = false,
  });

  factory MikanSessionCookie.fromJson(Map<String, dynamic> json) {
    return MikanSessionCookie(
      name: json['name'] as String? ?? '',
      value: json['value'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
      path: json['path'] as String? ?? '/',
      expiresDate: (json['expiresDate'] as num?)?.toInt(),
      isSecure: json['isSecure'] as bool? ?? false,
      isHttpOnly: json['isHttpOnly'] as bool? ?? false,
    );
  }

  factory MikanSessionCookie.fromSetCookieHeader(
    String header, {
    required String fallbackDomain,
  }) {
    final parts = header.split(';');
    final nameValue = parts.first.split('=');
    final name = nameValue.isNotEmpty ? nameValue.first.trim() : '';
    final value = nameValue.length > 1
        ? nameValue.sublist(1).join('=').trim()
        : '';
    var domain = fallbackDomain;
    var path = '/';
    int? expiresDate;
    var isSecure = false;
    var isHttpOnly = false;

    for (final rawPart in parts.skip(1)) {
      final part = rawPart.trim();
      final lower = part.toLowerCase();
      if (lower == 'secure') {
        isSecure = true;
      } else if (lower == 'httponly') {
        isHttpOnly = true;
      } else if (lower.startsWith('domain=')) {
        domain = part.substring(7).trim();
      } else if (lower.startsWith('path=')) {
        path = part.substring(5).trim();
      } else if (lower.startsWith('max-age=')) {
        final seconds = int.tryParse(part.substring(8).trim());
        if (seconds != null) {
          expiresDate = DateTime.now().millisecondsSinceEpoch + seconds * 1000;
        }
      } else if (lower.startsWith('expires=')) {
        final parsed = DateTime.tryParse(part.substring(8).trim());
        if (parsed != null) {
          expiresDate = parsed.millisecondsSinceEpoch;
        }
      }
    }

    return MikanSessionCookie(
      name: name,
      value: value,
      domain: domain,
      path: path.isEmpty ? '/' : path,
      expiresDate: expiresDate,
      isSecure: isSecure,
      isHttpOnly: isHttpOnly,
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
    if (name.isEmpty || value.isEmpty) return false;
    if (_isExpired) return false;
    if (!_matchesHost(uri.host)) return false;
    return _matchesPath(uri.path.isEmpty ? '/' : uri.path);
  }

  bool get _isExpired {
    if (expiresDate == null) return false;
    final normalized = expiresDate! > 0 && expiresDate! < 100000000000
        ? expiresDate! * 1000
        : expiresDate!;
    return DateTime.now().millisecondsSinceEpoch >= normalized;
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
    return normalizedCookiePath == '/' ||
        normalizedRequestPath == normalizedCookiePath ||
        normalizedRequestPath.startsWith(
          normalizedCookiePath.endsWith('/')
              ? normalizedCookiePath
              : '$normalizedCookiePath/',
        );
  }
}

class MikanSession {
  final String username;
  final DateTime capturedAt;
  final DateTime validatedAt;
  final String primaryHost;
  final List<MikanSessionCookie> cookies;

  const MikanSession({
    required this.username,
    required this.capturedAt,
    required this.validatedAt,
    required this.primaryHost,
    required this.cookies,
  });

  bool get isValid => username.isNotEmpty && cookies.isNotEmpty;

  factory MikanSession.fromJson(Map<String, dynamic> json) {
    return MikanSession(
      username: json['username'] as String? ?? '',
      capturedAt:
          DateTime.tryParse(json['capturedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      validatedAt:
          DateTime.tryParse(json['validatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      primaryHost: json['primaryHost'] as String? ?? 'mikanani.me',
      cookies: (json['cookies'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => MikanSessionCookie.fromJson(
              item.map((key, value) => MapEntry('$key', value)),
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'capturedAt': capturedAt.toIso8601String(),
      'validatedAt': validatedAt.toIso8601String(),
      'primaryHost': primaryHost,
      'cookies': cookies.map((cookie) => cookie.toJson()).toList(),
    };
  }

  String? buildCookieHeaderForUri(Uri uri) {
    final matches = cookies.where((cookie) => cookie.matchesUri(uri)).toList();
    matches.sort((a, b) {
      final pathCompare = b.path.length.compareTo(a.path.length);
      if (pathCompare != 0) return pathCompare;
      return a.name.compareTo(b.name);
    });
    if (matches.isEmpty) return null;
    return matches.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }
}

class MikanUser {
  final String name;
  final String avatar;
  final String rss;

  const MikanUser({required this.name, this.avatar = '', this.rss = ''});
}

class MikanBangumi {
  final String id;
  final String name;
  final String cover;
  final bool subscribed;
  final String updateAt;

  const MikanBangumi({
    required this.id,
    required this.name,
    this.cover = '',
    this.subscribed = false,
    this.updateAt = '',
  });
}

class MikanSubgroup {
  final String id;
  final String name;

  const MikanSubgroup({this.id = '', required this.name});
}

class MikanRecordItem {
  final String id;
  final String name;
  final String title;
  final String episode;
  final String subtitleType;
  final String publishAt;
  final String url;
  final String magnet;
  final String size;
  final String torrent;
  final List<String> tags;

  const MikanRecordItem({
    this.id = '',
    this.name = '',
    this.title = '',
    this.episode = '',
    this.subtitleType = '',
    this.publishAt = '',
    this.url = '',
    this.magnet = '',
    this.size = '',
    this.torrent = '',
    this.tags = const [],
  });
}

class MikanSubgroupBangumi {
  final String dataId;
  final String name;
  final bool subscribed;
  final String sublang;
  final String rss;
  final int state;
  final List<MikanSubgroup> subgroups;
  final List<MikanRecordItem> records;

  const MikanSubgroupBangumi({
    required this.dataId,
    required this.name,
    this.subscribed = false,
    this.sublang = '',
    this.rss = '',
    this.state = -1,
    this.subgroups = const [],
    this.records = const [],
  });
}

class MikanBangumiDetail {
  final String id;
  final String name;
  final String cover;
  final String intro;
  final bool subscribed;
  final Map<String, String> more;
  final List<MikanSubgroupBangumi> subgroupBangumis;

  const MikanBangumiDetail({
    required this.id,
    required this.name,
    this.cover = '',
    this.intro = '',
    this.subscribed = false,
    this.more = const {},
    this.subgroupBangumis = const [],
  });

  int? get bangumiSubjectId {
    final raw = more['番组计划链接'] ?? more['Bangumi'] ?? more['Bangumi链接'];
    if (raw == null || raw.isEmpty) return null;
    final match = RegExp(r'/subject/(\d+)').firstMatch(raw);
    return int.tryParse(match?.group(1) ?? raw);
  }
}

class MikanSearchResult {
  final List<MikanBangumi> bangumis;
  final List<MikanSubgroup> subgroups;
  final List<MikanRecordItem> records;

  const MikanSearchResult({
    this.bangumis = const [],
    this.subgroups = const [],
    this.records = const [],
  });
}

class MikanSubjectMapping {
  final int subjectId;
  final String bangumiId;
  final String bangumiName;
  final String bangumiCover;
  final String subgroupId;
  final String subgroupName;
  final String rss;
  final bool subscribed;
  final DateTime updatedAt;

  const MikanSubjectMapping({
    required this.subjectId,
    required this.bangumiId,
    required this.bangumiName,
    this.bangumiCover = '',
    this.subgroupId = '',
    this.subgroupName = '',
    this.rss = '',
    this.subscribed = false,
    required this.updatedAt,
  });

  factory MikanSubjectMapping.fromJson(Map<String, dynamic> json) {
    return MikanSubjectMapping(
      subjectId: (json['subjectId'] as num?)?.toInt() ?? 0,
      bangumiId: json['bangumiId'] as String? ?? '',
      bangumiName: json['bangumiName'] as String? ?? '',
      bangumiCover: json['bangumiCover'] as String? ?? '',
      subgroupId: json['subgroupId'] as String? ?? '',
      subgroupName: json['subgroupName'] as String? ?? '',
      rss: json['rss'] as String? ?? '',
      subscribed: json['subscribed'] as bool? ?? false,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  factory MikanSubjectMapping.fromSelection({
    required int subjectId,
    required MikanBangumi bangumi,
    MikanSubgroupBangumi? subgroup,
  }) {
    return MikanSubjectMapping(
      subjectId: subjectId,
      bangumiId: bangumi.id,
      bangumiName: bangumi.name,
      bangumiCover: bangumi.cover,
      subgroupId: subgroup?.dataId ?? '',
      subgroupName: subgroup?.name ?? '',
      rss: subgroup?.rss ?? '',
      subscribed: subgroup?.subscribed ?? bangumi.subscribed,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'subjectId': subjectId,
      'bangumiId': bangumiId,
      'bangumiName': bangumiName,
      'bangumiCover': bangumiCover,
      'subgroupId': subgroupId,
      'subgroupName': subgroupName,
      'rss': rss,
      'subscribed': subscribed,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  MikanSubjectMapping copyWith({
    String? bangumiName,
    String? bangumiCover,
    String? subgroupId,
    String? subgroupName,
    String? rss,
    bool? subscribed,
    DateTime? updatedAt,
  }) {
    return MikanSubjectMapping(
      subjectId: subjectId,
      bangumiId: bangumiId,
      bangumiName: bangumiName ?? this.bangumiName,
      bangumiCover: bangumiCover ?? this.bangumiCover,
      subgroupId: subgroupId ?? this.subgroupId,
      subgroupName: subgroupName ?? this.subgroupName,
      rss: rss ?? this.rss,
      subscribed: subscribed ?? this.subscribed,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
