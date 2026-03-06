# 应用更新功能使用说明（GitHub Release）

## 你现在需要做的仅有两步

1. 在 `lib/services/update_service.dart` 填写你的仓库信息
2. 发布 Release 时上传 APK 资源

## 第一步：配置仓库

编辑 `lib/services/update_service.dart`：

```dart
static const String githubOwner = 'Zao-chen';
static const String githubRepo = 'ZcBangumi';
static const String apkAssetNameKeyword = 'app-release';
static const String windowsAssetNameKeyword = 'windows';
static const bool allowPrerelease = false;
```

## 第二步：发布 Release

1. 更新项目版本（`pubspec.yaml`）
2. 打包 APK：

```bash
flutter build apk --release
```

3. 到 GitHub 创建新 Release，Tag 如 `v0.2.0`
4. 上传生成的 APK 和 Windows 安装包（`.exe/.msi/.msix`）到 Assets
5. 写好 Release Notes（客户端会显示为更新内容）

## 应用内体验

- 自动检查：应用启动后按 24 小时频率检查
- 手动检查：设置页点击检查更新
- 有新版本：弹出更新框，支持下载进度与安装
- 忽略版本：可忽略某个版本，后续不再提示该版本
- Windows 识别：优先匹配文件名包含 `windows` 的安装包

## 常见问题

### 检查不到更新

- 确认 `githubOwner/githubRepo` 是否正确
- 确认 Release 是最新发布（latest）
- 确认 Tag 版本号高于当前版本
- 确认 Android 有 `.apk`（包含 `app-release`），Windows 有 `.exe/.msi/.msix`（建议包含 `windows`）

### 找到版本但无法下载

- 检查 Release 资源是否上传成功
- 检查网络是否可访问 GitHub
- 检查 APK 资源链接是否可直接访问

### 下载后不能安装

- 检查 APK 是否与已安装版本同签名
- 检查系统安装未知来源权限

## 备注

- iOS 不支持 APK 方式更新（应走 App Store）
- 若仓库为 private，需要额外实现带 Token 的 GitHub API 请求
