# 应用更新配置（GitHub Release）

## 方案说明

应用现在直接通过 GitHub Release 检查更新，不再依赖自建更新 API。

默认读取接口：

`https://api.github.com/repos/<owner>/<repo>/releases/latest`

## 代码配置位置

在 `lib/services/update_service.dart` 中修改：

```dart
static const String githubOwner = 'your-github-name';
static const String githubRepo = 'ZcBangumi';
static const String apkAssetNameKeyword = 'app-release';
static const String windowsAssetNameKeyword = 'windows';
static const bool allowPrerelease = false;
```

当前仓库示例：`https://github.com/Zao-chen/ZcBangumi`

- `githubOwner`: `Zao-chen`
- `githubRepo`: `ZcBangumi`

参数说明：
- `githubOwner`: GitHub 用户名或组织名
- `githubRepo`: 仓库名
- `apkAssetNameKeyword`: 用于匹配 APK 资源名称关键字
- `windowsAssetNameKeyword`: Windows 安装包名称关键字
- `allowPrerelease`: 是否允许预发布版本

## Release 规范

为了让客户端正确识别，请按下面规则发布：

1. Tag 使用语义化版本
2. 推荐 `v1.2.3`（代码会自动去掉前缀 `v`）
3. 在 Release Assets 中上传 Android 和 Windows 安装包
4. Android APK 文件名包含关键字（默认 `app-release`），例如：
   - `app-release-v0.2.0.apk`
   - `zc_bangumi-app-release.apk`
5. Windows 安装包建议包含关键字（默认 `windows`），支持 `.exe/.msi/.msix`，例如：
   - `zc-bangumi-windows-setup.exe`
   - `zc-bangumi-windows-installer.msi`

## 更新判断逻辑

1. 读取当前应用版本（`pubspec.yaml`）
2. 请求 latest release
3. 比较 `tag_name` 与当前版本
4. 若最新版本更高且未被忽略，查找 APK 资源
5. 找到可下载 APK 后提示更新

## 注意事项

1. Android 支持 APK 直装，Windows 支持 `.exe/.msi/.msix` 安装包拉起
2. 仓库若是 private，需改为带 Token 的 API 请求
3. GitHub API 有速率限制，建议仅在启动和手动时检查
4. 新旧 APK 必须使用同一签名证书

## 发布流程

1. 修改 `pubspec.yaml` 版本号
2. 构建 APK：`flutter build apk --release`
3. 创建 GitHub Tag / Release
4. 上传 APK 到 Release Assets
5. 填写 Release Notes（会展示为更新日志）

## 验证

- 启动应用自动检查（24 小时间隔）
- 设置页手动点击检查更新
- 观察是否弹出更新对话框并可下载安装
