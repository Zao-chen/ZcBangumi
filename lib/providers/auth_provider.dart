import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

/// 认证状态管理
class AuthProvider extends ChangeNotifier {
  final ApiClient api;
  final StorageService storage;

  BangumiUser? _user;
  bool _loading = false;
  String? _error;

  AuthProvider({required this.api, required this.storage});

  BangumiUser? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get loading => _loading;
  String? get error => _error;
  String? get username => _user?.username ?? storage.username;

  /// 尝试用已保存的 Token 恢复登录
  Future<void> tryRestoreSession() async {
    final token = storage.accessToken;
    if (token == null || token.isEmpty) return;

    api.setToken(token);
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await api.getMe();
      await storage.setUsername(_user!.username);
      _error = null;
    } catch (e) {
      // Token 可能已过期
      _user = null;
      api.setToken(null);
      _error = '登录已过期，请重新登录';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 使用 Access Token 登录
  Future<bool> loginWithToken(String token) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      api.setToken(token);
      _user = await api.getMe();
      await storage.setAccessToken(token);
      await storage.setUsername(_user!.username);
      _error = null;
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      api.setToken(null);
      _user = null;
      _error = '登录失败，请检查 Token 是否正确';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// 退出登录
  Future<void> logout() async {
    _user = null;
    api.setToken(null);
    await storage.clearAuth();
    _error = null;
    notifyListeners();
  }
}
