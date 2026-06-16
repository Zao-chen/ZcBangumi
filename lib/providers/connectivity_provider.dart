import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ConnectivityProvider extends ChangeNotifier {
  bool _usingCache = false;
  bool _bannerDismissed = false;
  String? _message;
  Object? _lastError;

  bool get usingCache => _usingCache;
  bool get shouldShowBanner =>
      _usingCache && !_bannerDismissed && (_message?.isNotEmpty ?? false);
  String get bannerMessage => _message ?? '网络不可用，正在显示本地缓存';
  Object? get lastError => _lastError;

  void reportNetworkFailure(Object error, {String? message}) {
    _usingCache = true;
    _bannerDismissed = false;
    _lastError = error;
    _message = message ?? _messageForError(error);
    notifyListeners();
  }

  void reportNetworkSuccess() {
    if (!_usingCache && _lastError == null && _message == null) return;
    _usingCache = false;
    _bannerDismissed = false;
    _lastError = null;
    _message = null;
    notifyListeners();
  }

  void dismissBanner() {
    if (_bannerDismissed) return;
    _bannerDismissed = true;
    notifyListeners();
  }

  static bool isNetworkFailure(Object error) {
    if (error is! DioException) return false;
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown;
  }

  static bool isAuthExpired(Object error) {
    if (error is! DioException) return false;
    final statusCode = error.response?.statusCode;
    return statusCode == 401 || statusCode == 403;
  }

  static String _messageForError(Object error) {
    if (isNetworkFailure(error)) {
      return '网络不可用，正在显示本地缓存';
    }
    return '网络请求失败，正在显示本地缓存';
  }
}
