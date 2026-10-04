# ZcBangumi

一个基于 Flutter 开发的 Bangumi 第三方客户端。

在 Bangumi 核心功能的基础上，进一步拓展实用功能、整合相关服务，并优化部分页面与交互体验，提供更完整的一站式 ACG 使用体验。

在线体验：[bgm.greatzaochen.dev](https://bgm.greatzaochen.dev/)  
> Web 版本受浏览器平台限制，目前仅提供部分基础功能。
> Web 诊断日志保存在当前页面内存中，可查看、复制、下载和清空；刷新页面后不保留日志。
> 网页版功能边界与验证说明见 [Web 体验审计](docs/WEB_EXPERIENCE.md)。

## Web 部署与检查

GitHub Pages 工作流会运行客户端测试、Chrome 中的 Web 启动与日志回归测试，再构建并部署 Web 版本。

本地检查：

```sh
flutter test --platform chrome test/web_startup_test.dart test/web_experience_test.dart
flutter build web --release --base-href "/"
```

自定义域名 `bgm.greatzaochen.dev` 的 DNS CNAME 应直接指向 `zao-chen.github.io`。修改后，在仓库 Settings → Pages 中确认 DNS 检查通过、证书签发完成，再开启 Enforce HTTPS。工作流成功不代表域名证书或浏览器运行状态正常。

## 功能特性

- **流畅的客户端体验**：基于 Bangumi API 与 Flutter 构建，提供统一、流畅的跨平台体验。
- **功能完善**：覆盖 Bangumi 的主要功能与接口，提供完整的条目浏览、收藏、进度管理与社区功能。
- **实用站点聚合**：集成萌娘百科、蜜柑计划等相关站点，减少不同网站之间的跳转。
- **功能拓展**：支持镜像站设置、超展开帖子收藏与同步等实用功能。
- **信息展示优化**：重新设计部分页面的信息组织方式，例如以关系图形式展示关联条目，使复杂关系更加直观。
- **多端适配**：适配手机、平板与桌面端，并支持横屏、竖屏等不同使用场景。

## 截图

## 致谢

本项目在开发过程中参考并受益于以下项目：

- [Bangumi](https://bangumi.tv/)：提供数据接口与社区生态。
- [xiaoyvyv/bangumi](https://github.com/xiaoyvyv/bangumi)：优秀的 Bangumi 第三方客户端实现。
- [czy0729/Bangumi](https://github.com/czy0729/Bangumi)：提供了许多值得参考的设计与实现思路。
- [iota9star/mikan_flutter](https://github.com/iota9star/mikan_flutter)：提供了 Mikan 相关功能的实现参考。
- [Flutter](https://flutter.dev/)：本项目使用的跨平台 UI 框架。

## 关于 AI

本项目在开发过程中广泛使用了 AI 辅助，包括代码编写、重构、调试与开发效率优化。
