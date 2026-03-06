import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地存储服务
class StorageService {
  static const String _keyAccessToken = 'access_token';
  static const String _keyUsername = 'username';
  static const String _keyLastUpdateCheck = 'last_update_check';
  static const String _keyIgnoredVersion = 'ignored_version';

  late final SharedPreferences _prefs;

  /// 初始化
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
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

  /// 清除所有登录信息
  Future<void> clearAuth() async {
    await _prefs.remove(_keyAccessToken);
    await _prefs.remove(_keyUsername);
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
