import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bangumi_web_session.dart';
import '../models/mikan.dart';
import '../models/subject.dart';

/// 本地存储服务
class StorageService {
  static const int _cacheSchemaVersion = 1;
  static const int defaultCacheMaxAgeDays = 90;
  static const int hotCacheAccessThreshold = 8;

  static const String _keyAccessToken = 'access_token';
  static const String _keyUsername = 'username';
  static const String _keyWebCookie = 'web_cookie';
  static const String _keyWebCookieJar = 'web_cookie_jar';
  static const String _keyWebSession = 'web_session';
  static const String _keyLegacyWebSessionInvalidated =
      'legacy_web_session_invalidated';
  static const String _keyLastUpdateCheck = 'last_update_check';
  static const String _keyIgnoredVersion = 'ignored_version';
  static const String _keyRecentSubjectDetails = 'recent_subject_details';
  static const String _keyMikanSession = 'mikan_session';
  static const String _keyMikanBaseUrl = 'mikan_base_url';
  static const String _keyMikanEnabled = 'mikan_enabled';
  static const String _keyMikanSubjectMappings = 'mikan_subject_mappings';

  late final SharedPreferences _prefs;

  /// 初始化
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _migrateLegacyWebSession();
  }

  /// 读取 Access Token
  String? get accessToken => _prefs.getString(_keyAccessToken);

  /// 保存 Access Token
  Future<void> setAccessToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _prefs.remove(_keyAccessToken);
    } else {
      await _prefs.setString(_keyAccessToken, token);
    }
  }

  /// 读取用户名
  String? get username => _prefs.getString(_keyUsername);

  /// 保存用户名
  Future<void> setUsername(String? username) async {
    if (username == null || username.isEmpty) {
      await _prefs.remove(_keyUsername);
    } else {
      await _prefs.setString(_keyUsername, username);
    }
  }

  BangumiWebSession? get webSession {
    final raw = _prefs.getString(_keyWebSession);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return BangumiWebSession.fromJson(
        decoded.map((key, value) => MapEntry('$key', value)),
      );
    } catch (_) {
      return null;
    }
  }

  bool get legacyWebSessionInvalidated =>
      _prefs.getBool(_keyLegacyWebSessionInvalidated) ?? false;

  Future<void> setWebSession(BangumiWebSession? session) async {
    if (session == null || !session.isValid) {
      await _prefs.remove(_keyWebSession);
      return;
    }
    await _prefs.setString(_keyWebSession, jsonEncode(session.toJson()));
    await _prefs.remove(_keyLegacyWebSessionInvalidated);
  }

  Future<void> setLegacyWebSessionInvalidated(bool value) async {
    if (value) {
      await _prefs.setBool(_keyLegacyWebSessionInvalidated, true);
    } else {
      await _prefs.remove(_keyLegacyWebSessionInvalidated);
    }
  }

  /// 清除所有登录信息
  Future<void> clearAuth() async {
    await _prefs.remove(_keyAccessToken);
    await _prefs.remove(_keyUsername);
  }

  MikanSession? get mikanSession {
    final raw = _prefs.getString(_keyMikanSession);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return MikanSession.fromJson(
        decoded.map((key, value) => MapEntry('$key', value)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> setMikanSession(MikanSession? session) async {
    if (session == null || !session.isValid) {
      await _prefs.remove(_keyMikanSession);
      return;
    }
    await _prefs.setString(_keyMikanSession, jsonEncode(session.toJson()));
  }

  String get mikanBaseUrl =>
      _prefs.getString(_keyMikanBaseUrl) ?? 'https://mikanani.me';

  bool get mikanEnabled => _prefs.getBool(_keyMikanEnabled) ?? true;

  Future<void> setMikanEnabled(bool value) async {
    await _prefs.setBool(_keyMikanEnabled, value);
  }

  Future<void> setMikanBaseUrl(String baseUrl) async {
    final normalized = baseUrl.trim();
    if (normalized.isEmpty) {
      await _prefs.remove(_keyMikanBaseUrl);
    } else {
      await _prefs.setString(_keyMikanBaseUrl, normalized);
    }
  }

  Map<int, MikanSubjectMapping> getMikanSubjectMappings() {
    final raw = getCache(_keyMikanSubjectMappings);
    if (raw is! Map) return const {};
    final result = <int, MikanSubjectMapping>{};
    for (final entry in raw.entries) {
      final subjectId = int.tryParse('${entry.key}');
      final value = entry.value;
      if (subjectId == null || value is! Map) continue;
      try {
        result[subjectId] = MikanSubjectMapping.fromJson(
          value.map((key, value) => MapEntry('$key', value)),
        );
      } catch (_) {
        // 忽略损坏的映射项
      }
    }
    return result;
  }

  MikanSubjectMapping? getMikanSubjectMapping(int subjectId) {
    return getMikanSubjectMappings()[subjectId];
  }

  Future<void> setMikanSubjectMapping(MikanSubjectMapping mapping) async {
    final all = getMikanSubjectMappings();
    final next = <String, dynamic>{
      for (final entry in all.entries) '${entry.key}': entry.value.toJson(),
      '${mapping.subjectId}': mapping.toJson(),
    };
    await setCache(_keyMikanSubjectMappings, next);
  }

  Future<void> removeMikanSubjectMapping(int subjectId) async {
    final all = getMikanSubjectMappings();
    all.remove(subjectId);
    await setCache(_keyMikanSubjectMappings, {
      for (final entry in all.entries) '${entry.key}': entry.value.toJson(),
    });
  }

  Future<void> clearMikanData() async {
    await _prefs.remove(_keyMikanSession);
    await removeCache(_keyMikanSubjectMappings);
  }

  Future<void> _migrateLegacyWebSession() async {
    final hasLegacyCookie = (_prefs.getString(_keyWebCookie) ?? '').isNotEmpty;
    final hasLegacyCookieJar =
        (_prefs.getString(_keyWebCookieJar) ?? '').isNotEmpty;
    final hasStructuredSession =
        (_prefs.getString(_keyWebSession) ?? '').isNotEmpty;

    if (hasLegacyCookie || hasLegacyCookieJar) {
      await _prefs.remove(_keyWebCookie);
      await _prefs.remove(_keyWebCookieJar);
      if (!hasStructuredSession) {
        await _prefs.setBool(_keyLegacyWebSessionInvalidated, true);
      }
    }
  }

  // ==================== 数据缓存 ====================

  /// 写入缓存（自动序列化为 JSON）
  Future<void> setCache(String key, dynamic data) async {
    try {
      final now = DateTime.now();
      final existing = _readCacheEntry(key);
      final createdAt = existing?.createdAt ?? now;
      final accessCount = existing?.accessCount ?? 0;
      final wrapped = CacheEntry(
        data: data,
        createdAt: createdAt,
        updatedAt: now,
        lastAccessedAt: now,
        accessCount: accessCount,
      );
      await _prefs.setString('cache_$key', jsonEncode(wrapped.toJson()));
    } catch (_) {
      // 序列化失败，忽略
    }
  }

  /// 读取缓存（返回反序列化后的 dynamic）
  dynamic getCache(String key, {bool touch = true}) {
    final entry = _readCacheEntry(key);
    if (entry == null) return null;
    if (touch) {
      _touchCacheEntry(key, entry);
    }
    return entry.data;
  }

  CacheEntry? getCacheEntry(String key, {bool touch = true}) {
    final entry = _readCacheEntry(key);
    if (entry == null) return null;
    if (touch) {
      _touchCacheEntry(key, entry);
    }
    return entry;
  }

  Future<void> touchCache(String key) async {
    final entry = _readCacheEntry(key);
    if (entry == null) return;
    await _touchCacheEntry(key, entry);
  }

  CacheEntry? _readCacheEntry(String key) {
    final raw = _prefs.getString('cache_$key');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final map = decoded.map((k, v) => MapEntry('$k', v));
        if (map['__cache_meta'] is Map && map.containsKey('data')) {
          return CacheEntry.fromJson(map);
        }
      }
      final now = DateTime.now();
      return CacheEntry(
        data: decoded,
        createdAt: now,
        updatedAt: now,
        lastAccessedAt: now,
        accessCount: 0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _touchCacheEntry(String key, CacheEntry entry) async {
    try {
      final touched = entry.copyWith(
        lastAccessedAt: DateTime.now(),
        accessCount: entry.accessCount + 1,
      );
      await _prefs.setString('cache_$key', jsonEncode(touched.toJson()));
    } catch (_) {
      // 忽略 touch 失败，不影响缓存读取
    }
  }

  /// 删除指定缓存
  Future<void> removeCache(String key) async {
    await _prefs.remove('cache_$key');
  }

  /// 清除所有缓存
  Future<void> clearAllCache() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith('cache_')).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }

  /// 清除业务数据缓存（保留 app_state 配置）
  Future<void> clearDataCache() async {
    final keys = _prefs
        .getKeys()
        .where(
          (k) =>
              k.startsWith('cache_') &&
              k != 'cache_app_state' &&
              k != 'cache_$_keyMikanSubjectMappings',
        )
        .toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }

  Future<int> pruneStaleDataCache({
    Duration maxAge = const Duration(days: defaultCacheMaxAgeDays),
    int hotAccessThreshold = hotCacheAccessThreshold,
    int keepRecentSubjects = 50,
  }) async {
    final now = DateTime.now();
    final protectedSubjectIds = getRecentSubjectDetails(
      limit: keepRecentSubjects,
    ).map((s) => s.id).toSet();
    var removed = 0;

    final keys = _prefs
        .getKeys()
        .where(
          (k) =>
              k.startsWith('cache_') &&
              k != 'cache_app_state' &&
              k != 'cache_$_keyMikanSubjectMappings',
        )
        .toList();

    for (final prefKey in keys) {
      final cacheKey = prefKey.substring('cache_'.length);
      final entry = _readCacheEntry(cacheKey);
      if (entry == null) {
        await _prefs.remove(prefKey);
        removed++;
        continue;
      }

      final protectedSubject = _protectedSubjectIdForCacheKey(
        cacheKey,
        protectedSubjectIds,
      );
      if (protectedSubject) continue;
      if (entry.accessCount >= hotAccessThreshold) continue;
      if (now.difference(entry.lastAccessedAt) <= maxAge) continue;

      await _prefs.remove(prefKey);
      removed++;
    }

    return removed;
  }

  bool _protectedSubjectIdForCacheKey(String cacheKey, Set<int> subjectIds) {
    if (subjectIds.isEmpty) return false;
    final patterns = [
      RegExp(r'^subject_(\d+)$'),
      RegExp(r'^subject_chars_(\d+)$'),
      RegExp(r'^subject_related_(\d+)$'),
      RegExp(r'^subject_episodes_(\d+)$'),
      RegExp(r'^subject_comments_(\d+)$'),
      RegExp(r'^subject_user_collection_(\d+)$'),
      RegExp(r'^episodes_(\d+)$'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(cacheKey);
      if (match == null) continue;
      final id = int.tryParse(match.group(1) ?? '');
      if (id != null && subjectIds.contains(id)) return true;
    }
    return false;
  }

  /// 保存最近浏览的条目详情（去重并限制数量）
  Future<void> saveRecentSubjectDetail(
    Subject subject, {
    int maxItems = 50,
  }) async {
    if (maxItems <= 0) return;

    final raw = getCache(_keyRecentSubjectDetails);
    final items = <Map<String, dynamic>>[];

    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final map = entry.map((k, v) => MapEntry('$k', v));
        final subjectObj = map['subject'];
        if (subjectObj is! Map) continue;
        final subjectMap = subjectObj.map((k, v) => MapEntry('$k', v));
        if (subjectMap['id'] is int) {
          items.add({
            'subject': subjectMap,
            'updated_at': map['updated_at']?.toString() ?? '',
          });
        }
      }
    }

    items.removeWhere((entry) {
      final subjectObj = entry['subject'];
      if (subjectObj is! Map) return false;
      return subjectObj['id'] == subject.id;
    });

    items.insert(0, {
      'subject': subject.toJson(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    if (items.length > maxItems) {
      items.removeRange(maxItems, items.length);
    }

    await setCache(_keyRecentSubjectDetails, items);
  }

  /// 获取最近浏览的条目详情列表
  List<Subject> getRecentSubjectDetails({int limit = 20}) {
    final raw = getCache(_keyRecentSubjectDetails);
    if (raw is! List || raw.isEmpty || limit <= 0) {
      return const [];
    }

    final result = <Subject>[];
    for (final entry in raw) {
      if (result.length >= limit) break;
      if (entry is! Map) continue;
      final map = entry.map((k, v) => MapEntry('$k', v));
      final subjectObj = map['subject'];
      if (subjectObj is! Map) continue;

      try {
        final subjectMap = subjectObj.map((k, v) => MapEntry('$k', v));
        result.add(Subject.fromJson(subjectMap));
      } catch (_) {
        // 忽略损坏的缓存项
      }
    }

    return result;
  }

  // ==================== 更新管理 ====================

  /// 获取最后检查更新的时间
  DateTime? getLastUpdateCheckTime() {
    final timestamp = _prefs.getInt(_keyLastUpdateCheck);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// 保存最后检查更新的时间
  Future<void> setLastUpdateCheckTime(DateTime time) async {
    await _prefs.setInt(_keyLastUpdateCheck, time.millisecondsSinceEpoch);
  }

  /// 获取忽略的版本号
  String? getIgnoredVersion() {
    return _prefs.getString(_keyIgnoredVersion);
  }

  /// 设置忽略的版本号
  Future<void> setIgnoredVersion(String version) async {
    await _prefs.setString(_keyIgnoredVersion, version);
  }

  /// 清除忽略的版本号
  Future<void> clearIgnoredVersion() async {
    await _prefs.remove(_keyIgnoredVersion);
  }
}

class CacheEntry {
  final dynamic data;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastAccessedAt;
  final int accessCount;

  const CacheEntry({
    required this.data,
    required this.createdAt,
    required this.updatedAt,
    required this.lastAccessedAt,
    required this.accessCount,
  });

  factory CacheEntry.fromJson(Map<String, dynamic> json) {
    final meta = (json['__cache_meta'] as Map).map(
      (key, value) => MapEntry('$key', value),
    );
    return CacheEntry(
      data: json['data'],
      createdAt: _parseDate(meta['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(meta['updatedAt']) ?? DateTime.now(),
      lastAccessedAt: _parseDate(meta['lastAccessedAt']) ?? DateTime.now(),
      accessCount: (meta['accessCount'] as num?)?.toInt() ?? 0,
    );
  }

  CacheEntry copyWith({
    dynamic data,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastAccessedAt,
    int? accessCount,
  }) {
    return CacheEntry(
      data: data ?? this.data,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      accessCount: accessCount ?? this.accessCount,
    );
  }

  Map<String, dynamic> toJson() => {
    '__cache_meta': {
      'version': StorageService._cacheSchemaVersion,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastAccessedAt': lastAccessedAt.toIso8601String(),
      'accessCount': accessCount,
    },
    'data': data,
  };

  static DateTime? _parseDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
