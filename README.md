# ZcBangumi

> 基于 Flutter 开发的 Bangumi 番组计划第三方客户端

## 📖 项目简介

ZcBangumi 是一个使用 Flutter 开发的跨平台 Bangumi 番组计划第三方客户端，旨在提供流畅、美观的动漫、游戏、书籍等 ACG 内容管理体验。

## ✨ 功能特性

- 📅 **时间线** - 查看用户动态和好友动态
- 📊 **进度管理** - 追踪和管理收藏条目的观看/阅读进度
- 🔍 **搜索** - 快速搜索番剧、动画、游戏等条目
- 📖 **条目详情** - 查看详细的条目信息、评分和评论
- 👤 **角色信息** - 浏览角色详情和声优信息
- 📚 **收藏管理** - 管理你的收藏列表
- 👨‍💼 **个人主页** - 查看和编辑个人信息
- 🎨 **响应式设计** - 适配手机、平板和桌面端

## 🛠 技术栈

- **框架**: Flutter 3.11+
- **状态管理**: Provider
- **网络请求**: Dio
- **本地存储**: SharedPreferences
- **图片缓存**: CachedNetworkImage
- **外部链接**: UrlLauncher

## 📱 支持平台

- ✅ Android
- ✅ iOS
- ✅ Windows
- ✅ macOS
- ✅ Linux
- ✅ Web

## 🚀 快速开始

### 环境要求

- Flutter SDK >= 3.11.0
- Dart SDK >= 3.11.0

### 安装依赖

```bash
flutter pub get
```

### 运行项目

```bash
# 运行在 debug 模式
flutter run

# 指定平台运行
flutter run -d windows
flutter run -d chrome
flutter run -d android
```

### 构建应用

```bash
# Android APK
flutter build apk

# Windows 应用
flutter build windows

# iOS 应用（需要 macOS）
flutter build ios

# Web 应用
flutter build web
```

## 📂 项目结构

```
lib/
├── main.dart              # 应用入口
├── constants.dart         # 常量定义
├── models/                # 数据模型
│   ├── calendar.dart
│   ├── character.dart
│   ├── collection.dart
│   ├── comment.dart
│   ├── episode.dart
│   ├── subject.dart
│   ├── timeline.dart
│   └── user.dart
├── pages/                 # 页面
│   ├── character_page.dart
│   ├── collection_list_page.dart
│   ├── profile_page.dart
│   ├── progress_page.dart
│   ├── search_page.dart
│   ├── subject_page.dart
│   └── timeline_page.dart
├── providers/             # 状态管理
│   ├── auth_provider.dart
│   └── collection_provider.dart
├── services/              # 服务层
│   ├── api_client.dart
│   └── storage_service.dart
└── widgets/               # 自定义组件
    ├── progress_grid.dart
    └── responsive_scaffold.dart
```

## 🔧 开发计划

- [ ] 完善用户认证流程
- [ ] 添加条目评论功能
- [ ] 支持消息通知
- [ ] 完善日历功能
- [ ] 添加主题切换（深色模式）
- [ ] 支持离线缓存
- [ ] 添加国际化支持

## 📄 许可证

本项目采用 MIT 许可证

## 🙏 致谢

- [Bangumi](https://bangumi.tv/) - 提供 API 支持
- [Flutter](https://flutter.dev/) - 优秀的跨平台框架

## 📮 联系方式

如有问题或建议，欢迎提交 Issue 或 Pull Request。

---

⭐ 如果这个项目对你有帮助，欢迎 Star 支持！
