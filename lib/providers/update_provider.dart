import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../models/update_info.dart';
import '../services/update_service.dart';
import '../services/storage_service.dart';

enum UpdateState {
  idle, // 空闲
  checking, // 检查中
  available, // 有更新可用
  downloading, // 下载中
  downloaded, // 下载完成
  installing, // 安装中
  error, // 错误
}

class UpdateProvider extends ChangeNotifier {
  final UpdateService _updateService;
  final StorageService _storage;

  UpdateState _state = UpdateState.idle;
  UpdateInfo? _updateInfo;
  String? _errorMessage;
  String? _lastCheckMessage;
  bool _lastCheckIsError = false;
  double _downloadProgress = 0.0;
  CancelToken? _cancelToken;

  UpdateProvider({
    required UpdateService updateService,
    required StorageService storage,
  }) : _updateService = updateService,
       _storage = storage;

  UpdateState get state => _state;
  UpdateInfo? get updateInfo => _updateInfo;
  String? get errorMessage => _errorMessage;
  String? get lastCheckMessage => _lastCheckMessage;
  bool get lastCheckIsError => _lastCheckIsError;
  double get downloadProgress => _downloadProgress;
  bool get isDownloading => _state == UpdateState.downloading;

  /// 检查更新
  Future<void> checkForUpdate({bool silent = false}) async {
    if (_state == UpdateState.checking) return;

    _state = UpdateState.checking;
    _updateInfo = null;
    _errorMessage = null;
    _lastCheckMessage = null;
    _lastCheckIsError = false;
    if (!silent) notifyListeners();

    try {
      final appStateData =
          _storage.getCache('app_state') as Map<String, dynamic>?;
      final updateStableOnly =
          appStateData?['updateStableOnly'] as bool? ?? true;
      final result = await _updateService.checkForUpdateDetailed(
        allowPrerelease: !updateStableOnly,
      );

      if (result.hasUpdate && result.updateInfo != null) {
        _updateInfo = result.updateInfo;
        _state = UpdateState.available;
        _lastCheckMessage = result.message;
        _lastCheckIsError = false;

        // 保存最后检查时间
        await _storage.setLastUpdateCheckTime(DateTime.now());
      } else {
        _state = UpdateState.idle;

        // 静默检查只在有更新时处理 UI 信息，避免启动时显示错误提示。
        if (!silent) {
          _lastCheckMessage = result.message;
          _lastCheckIsError = result.isFailure;
          if (result.isFailure) {
            _errorMessage = result.message;
          }
        }
      }
    } catch (e) {
      _state = UpdateState.error;
      _errorMessage = '检查更新失败: $e';
      _lastCheckMessage = _errorMessage;
      _lastCheckIsError = true;
    }

    notifyListeners();
  }

  /// 下载更新
  Future<void> downloadUpdate() async {
    if (_updateInfo == null || _state == UpdateState.downloading) return;

    _state = UpdateState.downloading;
    _downloadProgress = 0.0;
    _errorMessage = null;
    _lastCheckMessage = null;
    _lastCheckIsError = false;
    _cancelToken = CancelToken();
    notifyListeners();

    try {
      final apkPath = await _updateService.downloadApk(
        _updateInfo!.downloadUrl,
        onProgress: (received, total) {
          if (total > 0) {
            _downloadProgress = received / total;
            notifyListeners();
          }
        },
      );

      if (apkPath != null) {
        _state = UpdateState.downloaded;
        notifyListeners();

        // 自动安装
        await installUpdate(apkPath);
      } else {
        throw Exception('下载失败');
      }
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        _state = UpdateState.available;
        _errorMessage = '下载已取消';
      } else {
        _state = UpdateState.error;
        _errorMessage = '下载失败: $e';
      }
      notifyListeners();
    }
  }

  /// 安装更新
  Future<void> installUpdate([String? apkPath]) async {
    _state = UpdateState.installing;
    _errorMessage = null;
    notifyListeners();

    try {
      final success = await _updateService.installApk(apkPath);

      if (!success) {
        throw Exception('安装失败');
      }

      // 注意：安装成功后应用会被关闭，所以这里的状态更新可能不会被看到
    } catch (e) {
      _state = UpdateState.error;
      _errorMessage = '安装失败: $e';
      notifyListeners();
    }
  }

  /// 取消下载
  void cancelDownload() {
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      _updateService.cancelDownload(_cancelToken!);
      _state = UpdateState.available;
      _errorMessage = '下载已取消';
      notifyListeners();
    }
  }

  /// 忽略本次更新
  Future<void> ignoreThisUpdate() async {
    if (_updateInfo != null) {
      await _storage.setIgnoredVersion(_updateInfo!.version);
      _state = UpdateState.idle;
      _updateInfo = null;
      notifyListeners();
    }
  }

  /// 检查是否应该自动检查更新
  Future<bool> shouldAutoCheck() async {
    final appStateData =
        _storage.getCache('app_state') as Map<String, dynamic>?;
    final configuredHours =
        appStateData?['updateCheckIntervalHours'] as int? ?? 24;
    if (configuredHours <= 0) {
      return false;
    }

    final lastCheck = _storage.getLastUpdateCheckTime();
    if (lastCheck == null) return true;

    // 根据用户设置的频率检查
    final now = DateTime.now();
    final difference = now.difference(lastCheck);
    return difference.inHours >= configuredHours;
  }

  /// 自动检查更新（静默）
  Future<void> autoCheckUpdate() async {
    if (await shouldAutoCheck()) {
      await checkForUpdate(silent: true);
    }
  }

  /// 重置状态
  void reset() {
    _state = UpdateState.idle;
    _updateInfo = null;
    _errorMessage = null;
    _lastCheckMessage = null;
    _lastCheckIsError = false;
    _downloadProgress = 0.0;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }
}
