import 'dart:io';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/update_info.dart';
import 'storage_service.dart';

enum UpdateCheckStatus {
  unsupportedPlatform,
  upToDate,
  updateAvailable,
  currentVersionHigher,
  ignoredVersion,
  noReleaseFound,
  noInstallableAsset,
  invalidReleaseData,
  networkError,
}

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final String message;
  final UpdateInfo? updateInfo;
  final String? currentVersion;
  final String? latestVersion;

  const UpdateCheckResult({
    required this.status,
    required this.message,
    this.updateInfo,
    this.currentVersion,
    this.latestVersion,
  });

  bool get hasUpdate => status == UpdateCheckStatus.updateAvailable;

  bool get isFailure =>
      status == UpdateCheckStatus.networkError ||
      status == UpdateCheckStatus.noReleaseFound ||
      status == UpdateCheckStatus.noInstallableAsset ||
      status == UpdateCheckStatus.invalidReleaseData;
}

class UpdateService {
  final Dio _dio;
  final StorageService _storage;
  String? _downloadedPackagePath;

  // GitHub Release 配置
  static const String githubOwner = 'Zao-chen';
  static const String githubRepo = 'ZcBangumi';
  static const String apkAssetNameKeyword = 'app-release';
  static const String windowsAssetNameKeyword = 'windows';
  static const bool allowPrerelease = false;

  UpdateService(this._dio, this._storage);

  /// 获取当前应用版本信息
  Future<PackageInfo> getCurrentVersion() async {
    return PackageInfo.fromPlatform();
  }

  /// 检查是否有新版本
  Future<UpdateInfo?> checkForUpdate() async {
    final result = await checkForUpdateDetailed();
    return result.updateInfo;
  }

  /// 检查更新（返回详细结果）
  Future<UpdateCheckResult> checkForUpdateDetailed() async {
    try {
      if (!Platform.isAndroid && !Platform.isWindows) {
        return const UpdateCheckResult(
          status: UpdateCheckStatus.unsupportedPlatform,
          message: '当前平台暂不支持应用内更新',
        );
      }

      final packageInfo = await getCurrentVersion();
      final currentVersion = packageInfo.version;
      final apiUrl =
          'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

      final response = await _dio.get(
        apiUrl,
        options: Options(
          headers: {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        ),
      );

      if (response.statusCode != 200 || response.data == null) {
        return const UpdateCheckResult(
          status: UpdateCheckStatus.invalidReleaseData,
          message: '获取更新信息失败：服务返回异常',
        );
      }

      final release = response.data as Map<String, dynamic>;
      final isPrerelease = (release['prerelease'] as bool?) ?? false;
      if (!allowPrerelease && isPrerelease) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.upToDate,
          message: '已是最新稳定版本',
          currentVersion: currentVersion,
        );
      }

      final tagName = (release['tag_name'] as String?)?.trim() ?? '';
      final latestVersion = tagName.replaceFirst(RegExp(r'^[vV]'), '');

      if (latestVersion.isEmpty) {
        return const UpdateCheckResult(
          status: UpdateCheckStatus.invalidReleaseData,
          message: '获取更新信息失败：版本号为空',
        );
      }

      final versionCompare = compareVersion(currentVersion, latestVersion);
      if (versionCompare > 0) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.currentVersionHigher,
          message: '当前版本($currentVersion)高于线上最新版($latestVersion)',
          currentVersion: currentVersion,
          latestVersion: latestVersion,
        );
      }

      if (versionCompare == 0) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.upToDate,
          message: '已是最新版本 ($currentVersion)',
          currentVersion: currentVersion,
          latestVersion: latestVersion,
        );
      }

      final ignoredVersion = _storage.getIgnoredVersion();
      if (ignoredVersion != null && ignoredVersion == latestVersion) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.ignoredVersion,
          message: '该版本($latestVersion)已被忽略',
          currentVersion: currentVersion,
          latestVersion: latestVersion,
        );
      }

      final assets = (release['assets'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();

      final packageAsset = _findPlatformAsset(assets);
      if (packageAsset == null) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.noInstallableAsset,
          message: '发现新版本($latestVersion)，但未找到可下载安装包',
          currentVersion: currentVersion,
          latestVersion: latestVersion,
        );
      }

      final downloadUrl =
          (packageAsset['browser_download_url'] as String?)?.trim() ?? '';
      if (downloadUrl.isEmpty) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.noInstallableAsset,
          message: '发现新版本($latestVersion)，但下载地址为空',
          currentVersion: currentVersion,
          latestVersion: latestVersion,
        );
      }

      final updateInfo = UpdateInfo(
        version: latestVersion,
        versionCode: '',
        downloadUrl: downloadUrl,
        changelog: (release['body'] as String?)?.trim() ?? '',
        forceUpdate: false,
        fileSize: (packageAsset['size'] as num?)?.toInt() ?? 0,
      );

      return UpdateCheckResult(
        status: UpdateCheckStatus.updateAvailable,
        message: '发现新版本 $latestVersion',
        updateInfo: updateInfo,
        currentVersion: currentVersion,
        latestVersion: latestVersion,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const UpdateCheckResult(
          status: UpdateCheckStatus.noReleaseFound,
          message: '未找到可用 Release（仅有 Tag 时无法检查更新）',
        );
      }
      return UpdateCheckResult(
        status: UpdateCheckStatus.networkError,
        message: '获取更新失败：${e.message ?? '网络异常'}',
      );
    } catch (e) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.networkError,
        message: '获取更新失败：$e',
      );
    }
  }

  /// 比较版本号
  bool isNewerVersion(String currentVersion, String newVersion) {
    return compareVersion(currentVersion, newVersion) < 0;
  }

  /// 版本比较：current<target 返回 -1，= 返回 0，> 返回 1。
  int compareVersion(String currentVersion, String targetVersion) {
    final current = _parseVersion(currentVersion);
    final target = _parseVersion(targetVersion);

    if (current.isEmpty || target.isEmpty) {
      return 0;
    }

    final maxLength = current.length > target.length
        ? current.length
        : target.length;

    for (int i = 0; i < maxLength; i++) {
      final currentPart = i < current.length ? current[i] : 0;
      final targetPart = i < target.length ? target[i] : 0;

      if (currentPart < targetPart) return -1;
      if (currentPart > targetPart) return 1;
    }

    return 0;
  }

  List<int> _parseVersion(String version) {
    final normalized = version.trim().replaceFirst(RegExp(r'^[vV]'), '');
    if (normalized.isEmpty) return const [];

    final parts = normalized.split('.');
    final result = <int>[];

    for (final part in parts) {
      final match = RegExp(r'\d+').firstMatch(part);
      if (match == null) {
        result.add(0);
        continue;
      }
      result.add(int.tryParse(match.group(0)!) ?? 0);
    }

    return result;
  }

  /// 请求安装权限
  Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      if (await Permission.requestInstallPackages.isGranted) {
        return true;
      }
      final status = await Permission.requestInstallPackages.request();
      return status.isGranted;
    }
    return true;
  }

  Map<String, dynamic>? _findPlatformAsset(List<Map<String, dynamic>> assets) {
    if (Platform.isAndroid) {
      final apks = assets.where((asset) {
        final name = (asset['name'] as String?)?.toLowerCase() ?? '';
        return name.endsWith('.apk');
      }).toList();

      if (apks.isEmpty) return null;

      for (final asset in apks) {
        final name = (asset['name'] as String?)?.toLowerCase() ?? '';
        if (name.contains(apkAssetNameKeyword.toLowerCase())) {
          return asset;
        }
      }

      // 未命中关键词时兜底使用第一个 APK，避免误判无更新。
      return apks.first;
    }

    if (Platform.isWindows) {
      final installers = assets.where((asset) {
        final name = (asset['name'] as String?)?.toLowerCase() ?? '';
        return name.endsWith('.exe') ||
            name.endsWith('.msi') ||
            name.endsWith('.msix');
      }).toList();

      if (installers.isEmpty) return null;

      for (final asset in installers) {
        final name = (asset['name'] as String?)?.toLowerCase() ?? '';
        if (name.contains(windowsAssetNameKeyword.toLowerCase())) {
          return asset;
        }
      }

      for (final asset in installers) {
        final name = (asset['name'] as String?)?.toLowerCase() ?? '';
        if (name.contains('setup') || name.contains('installer')) {
          return asset;
        }
      }

      return installers.first;
    }

    return null;
  }

  String _fileNameFromUrl(String downloadUrl) {
    try {
      final uri = Uri.parse(downloadUrl);
      final fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      if (fileName.isNotEmpty) {
        return fileName;
      }
    } catch (_) {
      // ignore
    }

    if (Platform.isAndroid) return 'zc_bangumi_update.apk';
    if (Platform.isWindows) return 'zc_bangumi_update.exe';
    return 'zc_bangumi_update.pkg';
  }

  /// 下载 APK 文件
  Future<String?> downloadApk(
    String downloadUrl, {
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final hasPermission = await requestStoragePermission();
      if (!hasPermission) {
        throw Exception('需要安装应用权限');
      }

      final directory = Platform.isAndroid
          ? await getExternalStorageDirectory()
          : (await getDownloadsDirectory()) ??
                await getApplicationSupportDirectory();
      if (directory == null) {
        throw Exception('无法获取存储目录');
      }

      final fileName = _fileNameFromUrl(downloadUrl);
      final savePath = '${directory.path}/$fileName';
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }

      await _dio.download(
        downloadUrl,
        savePath,
        onReceiveProgress: onProgress,
        options: Options(
          receiveTimeout: const Duration(minutes: 10),
          headers: {'Accept-Encoding': 'gzip'},
        ),
      );

      _downloadedPackagePath = savePath;
      return savePath;
    } catch (_) {
      return null;
    }
  }

  /// 安装 APK
  Future<bool> installApk([String? apkPath]) async {
    try {
      final path = apkPath ?? _downloadedPackagePath;
      if (path == null) {
        throw Exception('更新包路径为空');
      }

      final file = File(path);
      if (!await file.exists()) {
        throw Exception('更新包不存在');
      }

      final lowerPath = path.toLowerCase();
      final result = lowerPath.endsWith('.apk')
          ? await OpenFile.open(
              path,
              type: 'application/vnd.android.package-archive',
            )
          : await OpenFile.open(path);
      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

  /// 取消下载
  void cancelDownload(CancelToken cancelToken) {
    cancelToken.cancel('用户取消下载');
  }

  /// 清理下载的 APK 文件
  Future<void> cleanupDownloadedApk() async {
    if (_downloadedPackagePath != null) {
      final file = File(_downloadedPackagePath!);
      if (await file.exists()) {
        await file.delete();
      }
      _downloadedPackagePath = null;
    }
  }
}
