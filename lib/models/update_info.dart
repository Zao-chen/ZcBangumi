/// 更新信息模型
class UpdateInfo {
  final String version;
  final String versionCode;
  final String downloadUrl;
  final String changelog;
  final bool forceUpdate;
  final int fileSize;

  UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.downloadUrl,
    required this.changelog,
    this.forceUpdate = false,
    required this.fileSize,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] ?? '',
      versionCode: json['versionCode'] ?? '',
      downloadUrl: json['downloadUrl'] ?? '',
      changelog: json['changelog'] ?? '',
      forceUpdate: json['forceUpdate'] ?? false,
      fileSize: json['fileSize'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'versionCode': versionCode,
      'downloadUrl': downloadUrl,
      'changelog': changelog,
      'forceUpdate': forceUpdate,
      'fileSize': fileSize,
    };
  }

  /// 格式化文件大小
  String get formattedFileSize {
    if (fileSize < 1024) {
      return '${fileSize}B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(2)}KB';
    } else {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(2)}MB';
    }
  }
}
