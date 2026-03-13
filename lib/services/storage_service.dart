import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bangumi_web_session.dart';

/// 本地存储服务
class StorageService {
  static const String _keyAccessToken = 'access_token';
  static const String _keyUsername = 'username';
  static const String _keyWebCookie = 'web_cookie';
  static const String _keyWebCookieJar = 'web_cookie_jar';
  static const String _keyWebSession = 'web_session';
  static const String _keyLegacyWebSessionInvalidated =
      'legacy_web_session_invalidated';
  static const String _keyLastUpdateCheck = 'last_update_check';
  static const String _keyIgnoredVersion = 'ignored_version';

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

  Future<void> _migrateLegacyWebSession() async {
    final hasLegacyCookie = (_prefs.getString(_keyWebCookie) ?? '').isNotEmpty;
    final hasLegacyCookieJar =
        (_prefs.getString(_keyWebCookieJar) ?? '').isNotEmpty;
    final hasStructuredSession = (_prefs.getString(_keyWebSession) ?? '')
        .isNotEmpty;

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
      await _prefs.setString('cache_$key', jsonEncode(data));
    } catch (_) {
      // 序列化失败，忽略
    }
  }

  /// 读取缓存（返回反序列化后的 dynamic）
  dynamic getCache(String key) {
    final raw = _prefs.getString('cache_$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
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
