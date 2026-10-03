# ZcBangumi

基于 **Flutter** 开发的  **Bangumi 第三方客户端** ，专注于 ACG 条目浏览、收藏进度管理以及跨设备一致的使用体验。

在线体验：[bgm.greatzaochen.dev](https://bgm.greatzaochen.dev/)（受限于网页，仅有部分基础功能）

## 项目简介

ZcBangumi 致力于在保持 Bangumi 核心功能的基础上，提供更加**简洁、易用、流畅、清晰、现代化**的用户体验，并对部分页面展示方式进行了优化与改进。

## 功能特性

- **现代化页面设计**：界面风格简洁清晰，提升整体视觉体验。
- **流畅的使用体验**：内置缓存机制，部分内容支持离线加载。
- **Bangumi 镜像站**：在设置中选择官方站、`bangumi.vip` 或自定义镜像，统一切换网页、API 和图片线路，并支持手动验证。
- **多端与屏幕适配**：支持手机、平板与桌面端，并兼容横屏与竖屏使用场景。
- **页面体验优化**：对页面展示方式进行优化，如将关联条目以脑图形式展示，提升信息结构的可读性。
- **功能拓展**：利用班固米特性拓展更多功能，如超展开帖子收藏和收藏同步。补全使用体验。
- **多来源整合**：萌娘百科、蜜柑计划集成到应用中，可以快速查看百科和种子资源。

## 截图展示

![截图 1](img/1.png)
![截图 2](img/2.png)
![截图 3](img/3.png)
![截图 4](img/4.png)
![截图 5](img/5.png)
![截图 6](img/6.png)
![截图 7](img/7.png)
![截图 7](img/8.png)
![截图 7](img/9.png)
![截图 7](img/10.png)
![截图 7](img/11.png)
![截图 7](img/12.png)

## 镜像站使用

在「设置 → 网络 → Bangumi 镜像站」选择线路并保存。自定义镜像填写 HTTPS 网页主域名，默认生成 `api`、`next`、`lain`、`fast` 子域名；高级选项可以分别覆盖服务根地址和端口，不支持路径式反代。

第三方镜像能够接触经由它发送的 Token、Cookie 及镜像页面内的登录信息。首次启用或修改服务地址必须确认风险，取消不会更换当前线路。网页版仍受浏览器跨域限制，切换镜像不等于解除这些限制。

「检查连接」只请求公开内容，不携带登录凭据，且会分别检查各服务的返回格式。展开「连接详情」查看各服务结果及验证入口；使用说明和验证会话清理位于卡片右上角的更多菜单。遇到人机验证时，在受支持的原生平台点击「验证」，自行完成页面操作后点击「验证完成，复测连接」。客户端复测通过才保存会话；代理出口或 User-Agent 不兼容时会提示失败。验证不会自动重放收藏、进度或发帖等写请求。

可使用 `flutter run -d macos -t tools/mirror_smoke.dart --no-pub` 进行隔离运行验收。此入口将设置保存在独立的 `mirror_smoke.` 偏好命名空间，不读取正式应用的 Token、Cookie 或设置，也不清理正式数据；隔离设置可以跨重启恢复。WebView 和公开图片仍使用应用现有的原生存储。

## macOS 开发要求

macOS 最低运行版本为 12.0。Runner 和 CocoaPods 的最低部署版本统一为 12.0；重新执行 `pod install` 时也会修正插件及隐私资源包中过旧的部署版本，不会降低依赖自身要求的更高版本。

使用 `flutter run -d macos` 启动调试，无须额外传入 `MACOSX_DEPLOYMENT_TARGET`。

## 致谢

本项目在开发过程中参考并受益于以下优秀项目：

* [Bangumi](https://bangumi.tv/)：提供数据接口与社区生态。
* [xiaoyvyv/bangumi](https://github.com/xiaoyvyv/bangumi)：优秀的 Bangumi 第三方客户端实现。
* [czy0729/Bangumi](https://github.com/czy0729/Bangumi)：提供了许多值得学习的实现思路。
* [iota9star/mikan_flutter](https://github.com/iota9star/mikan_flutter)：Mikan实现思路借鉴。
* [Flutter](https://flutter.dev/)：跨平台 UI 框架。

注：本项目在开发过程中广泛使用了 AI 辅助。
