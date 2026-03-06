import 'dart:io';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/update_info.dart';
import 'storage_service.dart';

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
    try {
      if (!Platform.isAndroid && !Platform.isWindows) {
        return null;
      }

      final packageInfo = await getCurrentVersion();
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
        return null;
      }

      final release = response.data as Map<String, dynamic>;
      final isPrerelease = (release['prerelease'] as bool?) ?? false;
      if (!allowPrerelease && isPrerelease) {
        return null;
      }

      final tagName = (release['tag_name'] as String?)?.trim() ?? '';
      final latestVersion = tagName.startsWith('v')
          ? tagName.substring(1)
          : tagName;

      if (latestVersion.isEmpty ||
          !isNewerVersion(packageInfo.version, latestVersion)) {
        return null;
      }

      final ignoredVersion = _storage.getIgnoredVersion();
      if (ignoredVersion != null && ignoredVersion == latestVersion) {
        return null;
      }

      final assets = (release['assets'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();

      final packageAsset = _findPlatformAsset(assets);
      if (packageAsset == null) {
        return null;
      }

      final downloadUrl =
          (packageAsset['browser_download_url'] as String?)?.trim() ?? '';
      if (downloadUrl.isEmpty) {
        return null;
      }

      return UpdateInfo(
        version: latestVersion,
        versionCode: '',
        downloadUrl: downloadUrl,
        changelog: (release['body'] as String?)?.trim() ?? '',
        forceUpdate: false,
        fileSize: (packageAsset['size'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// 比较版本号
  bool isNewerVersion(String currentVersion, String newVersion) {
    final current = currentVersion.split('.').map(int.parse).toList();
    final newer = newVersion.split('.').map(int.parse).toList();

    for (int i = 0; i < current.length && i < newer.length; i++) {
      if (newer[i] > current[i]) return true;
      if (newer[i] < current[i]) return false;
    }

    return newer.length > current.length;
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
      for (final asset in assets) {
        final name = (asset['name'] as String?)?.toLowerCase() ?? '';
        if (name.endsWith('.apk') &&
            name.contains(apkAssetNameKeyword.toLowerCase())) {
          return asset;
        }
      }
      return null;
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
