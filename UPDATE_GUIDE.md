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
2. 确保 Android 发布签名固定不变：

```bash
copy android\\key.properties.example android\\key.properties
```

填写 `android/key.properties`（`storeFile/storePassword/keyAlias/keyPassword`）后再构建。

3. 打包 APK：

```bash
flutter build apk --release
```

4. 到 GitHub 创建新 Release，Tag 如 `v0.2.0`
5. 上传生成的 APK 和 Windows 安装包（`.exe/.msi/.msix`）到 Assets
6. 写好 Release Notes（客户端会显示为更新内容）

### 如果你使用 GitHub Actions 自动发布

请在仓库 `Settings -> Secrets and variables -> Actions` 配置：

- `ANDROID_KEYSTORE_BASE64`：发布 keystore 的 base64 内容
- `ANDROID_STORE_PASSWORD`：keystore 密码
- `ANDROID_KEY_ALIAS`：key alias
- `ANDROID_KEY_PASSWORD`：key 密码
- `ANDROID_CERT_SHA256`（可选但强烈建议）：证书 SHA256 指纹，用于 CI 防止签名漂移

PowerShell 生成 base64 示例：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\\path\\to\\upload-keystore.jks"))
```

也可以直接运行脚本一次性生成 5 个 Secrets 值：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/generate_github_android_secrets.ps1 \
	-KeystorePath "C:\path\to\upload-keystore.jks" \
	-Alias "upload" \
	-StorePassword "<store-password>" \
	-KeyPassword "<key-password>"
```

获取证书 SHA256（Windows）：

```powershell
keytool -list -v -keystore C:\path\to\upload-keystore.jks -alias upload | Select-String "SHA256"
```

将输出中的指纹（去掉空格）填入 `ANDROID_CERT_SHA256`。

本地发布前可执行签名校验：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify_android_signing.ps1 \
	-KeystorePath "android/keystore/upload-keystore.jks" \
	-Alias "upload" \
	-StorePassword "<store-password>" \
	-KeyPassword "<key-password>" \
	-ApkPath "build/app/outputs/flutter-apk/app-release.apk" \
	-ExpectedSha256 "<sha256-with-or-without-colons>"
```

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

#### 如何确认签名一致

- 历史版本和新版本必须使用同一个 keystore（同一份 `.jks/.keystore`）
- 不能一版用 debug 签名、一版用 release 签名
- 不能更换 `keyAlias` 到另一个证书

## 备注

- iOS 不支持 APK 方式更新（应走 App Store）
- 若仓库为 private，需要额外实现带 Token 的 GitHub API 请求
