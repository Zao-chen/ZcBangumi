import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/app_log_service.dart';
import '../services/network_proxy_config.dart';

class ConnectivityProvider extends ChangeNotifier {
  ConnectivityProvider({
    this.failureBannerDelay = const Duration(milliseconds: 800),
    AppLogService? logService,
    FutureOr<bool> Function()? canReachBangumi,
  }) : _logService = logService,
       _canReachBangumi = canReachBangumi ?? _defaultCanReachBangumi;

  final Duration failureBannerDelay;
  final AppLogService? _logService;
  final FutureOr<bool> Function() _canReachBangumi;

  bool _usingCache = false;
  bool _bannerDismissed = false;
  String? _message;
  Object? _lastError;
  Timer? _failureTimer;
  int _probeGeneration = 0;
  bool _rechecking = false;

  bool get usingCache => _usingCache;
  bool get shouldShowBanner =>
      _usingCache && !_bannerDismissed && (_message?.isNotEmpty ?? false);
  String get bannerMessage => _message ?? '网络不可用，正在显示本地缓存';
  Object? get lastError => _lastError;
  bool get rechecking => _rechecking;

  void reportNetworkFailure(Object error, {String? message}) {
    _failureTimer?.cancel();
    final generation = ++_probeGeneration;
    if (failureBannerDelay == Duration.zero) {
      unawaited(
        _confirmNetworkFailure(error, message: message, generation: generation),
      );
      return;
    }
    _failureTimer = Timer(failureBannerDelay, () {
      unawaited(
        _confirmNetworkFailure(error, message: message, generation: generation),
      );
    });
  }

  Future<void> _confirmNetworkFailure(
    Object error, {
    String? message,
    required int generation,
  }) async {
    final reachable = await _checkBangumiReachable();
    if (generation != _probeGeneration || reachable) {
      if (reachable) {
        unawaited(_logService?.info('network', 'bgm.tv 连通，忽略单次请求失败'));
        if (_usingCache) {
          reportNetworkSuccess();
        }
      }
      return;
    }
    _showNetworkFailure(error, message: message);
  }

  Future<bool> _checkBangumiReachable() async {
    try {
      return await _canReachBangumi();
    } catch (_) {
      return false;
    }
  }

  void _showNetworkFailure(Object error, {String? message}) {
    _usingCache = true;
    _bannerDismissed = false;
    _lastError = error;
    _message = message ?? _messageForError(error);
    unawaited(_logService?.warning('cache', _message!));
    notifyListeners();
  }

  void reportNetworkSuccess() {
    _failureTimer?.cancel();
    _failureTimer = null;
    _probeGeneration++;
    if (!_usingCache && _lastError == null && _message == null) return;
    _usingCache = false;
    _bannerDismissed = false;
    _lastError = null;
    _message = null;
    unawaited(_logService?.info('cache', '网络请求恢复，停止显示本地缓存提示'));
    notifyListeners();
  }

  void dismissBanner() {
    if (_bannerDismissed) return;
    _bannerDismissed = true;
    notifyListeners();
  }

  Future<bool> retryConnection() async {
    if (_rechecking) return false;
    _failureTimer?.cancel();
    _failureTimer = null;
    _rechecking = true;
    notifyListeners();

    final reachable = await _checkBangumiReachable();
    if (reachable) {
      reportNetworkSuccess();
    } else {
      _message = '网络仍不可用，正在显示本地缓存';
      unawaited(_logService?.warning('cache', _message!));
    }

    _rechecking = false;
    notifyListeners();
    return reachable;
  }

  @override
  void dispose() {
    _failureTimer?.cancel();
    super.dispose();
  }

  static Future<bool> _defaultCanReachBangumi() async {
    if (kIsWeb) return true;
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      NetworkProxyConfig.installDio(dio);
      await dio.get<String>(
        'https://bgm.tv',
        options: Options(responseType: ResponseType.plain),
      );
      return true;
    } catch (_) {
      return false;
    }
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
