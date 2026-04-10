# ZC Bangumi AI协作文档

本文档用于帮助其他AI在修改代码前快速理解项目结构、关键数据流、常见风险和验证方式。

## 1. 项目定位与技术栈

- 项目类型: Bangumi第三方Flutter客户端
- 目标能力: 条目浏览、收藏管理、时间线、超展开、更新检查
- 关键版本:
  - Flutter SDK: ^3.11.0
- 关键依赖:
  - dio: 网络请求
  - provider: 状态管理
  - shared_preferences: 本地持久化
  - cached_network_image: 图片缓存
  - flutter_inappwebview: 内嵌网页
  - flutter_local_notifications/open_file/permission_handler: 更新下载与安装相关能力

代码依据:

- lib/main.dart
- pubspec.yaml

## 2. 目录分层与职责

- lib/models: 纯数据模型与配置模型
  - 例: subject.dart, collection.dart, timeline.dart
- lib/services: 外部能力封装
  - api_client.dart: 所有接口调用入口
  - storage_service.dart: SharedPreferences缓存和会话存储
  - update_service.dart: GitHub Release更新检查/下载/安装
- lib/providers: 全局状态管理
  - auth_provider.dart: 登录状态与会话恢复
  - collection_provider.dart: 收藏与章节进度缓存
  - app_state_provider.dart: 全局UI配置与导航状态
  - update_provider.dart: 更新状态机
- lib/pages: 页面级业务逻辑
  - timeline/profile/subject等核心页面在此
- lib/widgets: 可复用组件
  - responsive_scaffold.dart, subject_action_buttons.dart等

## 3. 启动流程与初始化顺序

主入口位于 lib/main.dart。

顺序如下:

1. WidgetsFlutterBinding.ensureInitialized
2. StorageService.init
3. ApiClient创建并注入WebSession
4. UpdateService创建
5. runApp -> MultiProvider注入所有服务和Provider

_AppShell初始化后触发后台初始化:

1. preloadCachesIfAvailable
2. AuthProvider.tryRestoreSession
3. 可选启动自动刷新收藏数据
4. UpdateProvider.autoCheckUpdate

关键点:

- 启动流程是“先显示UI，再后台补状态”，避免首屏阻塞。
- Provider依赖链由main.dart中的MultiProvider顺序保证。

## 4. 状态管理与数据流

### 4.1 AuthProvider

- 负责Token登录、恢复会话、退出登录
- 通过ApiClient.setToken控制Authorization头
- tryRestoreSession会调用api.getMe验证Token是否可用

### 4.2 AppStateProvider

- 负责以下可持久化状态:
  - 当前底栏索引
  - 底栏顺序与隐藏项
  - Subject页Tab顺序与隐藏项
  - Timeline/Rakuen默认Tab
  - Profile筛选条件
  - 列表密度、圆角、副信息显示等UI偏好
  - 更新检查频率与稳定版策略
- 每次setter在值变化后会notifyListeners并_saveState

### 4.3 CollectionProvider

- 管理三类收藏缓存(动画/游戏/书籍)
- 支持“先读缓存再请求网络”的无感加载策略
- 章节进度更新采用乐观更新，失败回滚或重拉

### 4.4 UpdateProvider

- 管理更新状态机:
  - idle/checking/available/downloading/downloaded/installing/error
- 自动检查遵循app_state里的updateCheckIntervalHours

## 5. 网络层与缓存层约束

## 5.1 ApiClient三通道

- _dio: https://api.bgm.tv (官方API)
- _webDio: https://bgm.tv (网页请求 + Cookie)
- _nextDio: https://next.bgm.tv (p1 JSON接口)

重要约束:

- 认证Token仅用于官方API通道。
- Web Session依赖BangumiWebSession，Cookie会按请求URI组装。

## 5.2 StorageService

- 认证信息:
  - access_token
  - username
  - web_session
- 缓存统一前缀:
  - cache_<key>
- 特殊保留:
  - cache_app_state (全局设置)
  - last_update_check/ignored_version (更新策略)

重要约束:

- 清除业务缓存应优先使用clearDataCache，避免误删cache_app_state。
- 调整缓存结构时要保持fromJson兼容，避免页面回退到弱展示状态。

## 5.3 官方API文档对照(建议必读)

- 官方文档入口:
  - https://bangumi.github.io/api/

- 建议使用方式:
  1. 先在官方文档确认端点路径、请求参数、字段类型和鉴权要求。
  2. 再对照本项目实现，重点检查 lib/services/api_client.dart 中同名或近似方法。
  3. 如果官方返回结构变化，优先修正 models 的 fromJson/toJson，再回看页面渲染和缓存兼容。

- 本项目常见接口映射(示例):
  - 用户:
    - getMe -> /v0/me
    - getUser -> /v0/users/{username}
  - 条目:
    - getSubject -> /v0/subjects/{id}
    - getSubjectCharacters -> /v0/subjects/{id}/characters
    - getSubjectRelations -> /v0/subjects/{id}/relations
    - getSubjectComments -> /p1/subjects/{id}/comments
  - 收藏:
    - getUserCollections -> /v0/users/{username}/collections
    - patchCollection/putCollection -> /v0/users/-/collections/{subject_id}
    - getUserEpisodeCollections -> /v0/users/-/collections/{subject_id}/episodes
  - 时间线:
    - getTimeline(全站) -> /p1/timeline
    - getUserTimeline(用户) -> /p1/users/{username}/timeline

- 接口改动时的最低动作:
  1. 在提交说明中记录“官方文档依据链接 + 关键字段差异”。
  2. 补至少一个解析层验证(单测或临时断言)覆盖新字段。
  3. 验证旧缓存读取是否仍然安全(字段缺失时不崩溃)。

## 6. 核心页面与职责

- TimelinePage:
  - 三标签: 全站/好友/我的
  - 包含分页游标与去重逻辑
  - 对好友流有回落检测策略
- ProfilePage:
  - 登录态分支、收藏筛选、排序、设置入口
- SubjectPage:
  - 项目最复杂页面，包含多Tab并行数据加载
  - 先读缓存再并发请求，支持关联条目列表/脑图切换
- RakuenPage/RakuenTopicPage:
  - 话题与评论展示、跳转条目详情
- SettingsPage:
  - 登录管理、缓存清理、更新策略和UI偏好设置

## 7. 关键模型速览

- Subject/SlimSubject: 条目主数据
- UserCollection: 用户收藏状态与评分、进度
- UserEpisodeCollection: 单集收藏状态
- TimelineItem: 时间线动态项
- BangumiUser: 用户信息
- Character/Comment/RakuenTopic: 对应页面数据

修改模型时最低要求:

1. fromJson和toJson保持对称
2. 字段容错(空值/类型偏差)不能破坏旧缓存解析
3. 涉及缓存模型时验证历史缓存可回读

## 8. 改动风险清单(高优先级)

1. Provider依赖与初始化顺序

- 若在MultiProvider顺序中破坏依赖，可能出现ProviderNotFound或空状态竞态。

2. 缓存键与缓存结构变更

- 键名变更会导致旧数据失效。
- JSON结构不兼容会造成页面解析失败。

3. 登录态相关改动

- 修改AuthProvider逻辑后要验证: 首启无Token、有效Token恢复、失效Token回收。

4. SubjectPage并行加载逻辑

- 该页面有多段缓存+并发网络请求，改动时最易引入“局部成功/局部失败”显示异常。

5. Timeline分页与去重

- 改动游标或去重算法容易造成重复项或漏项。

6. 更新机制

- UpdateService明确移除了Authorization转发到GitHub，勿误加回。

## 9. AI改代码前检查表

1. 先定位改动属于哪一层(models/services/providers/pages/widgets)。
2. 列出受影响文件与调用链。
3. 若涉及缓存/模型，确认是否兼容历史缓存。
4. 若涉及Provider字段，确认load/save/getter/setter闭环是否完整。
5. 若涉及网络接口，确认走的是api/web/next哪个通道。
6. 若涉及登录与会话，补测Token恢复和失效回收。

## 10. AI改代码后验证表

必须执行:

1. flutter analyze
2. flutter test
3. 关键路径手测

关键路径手测建议:

1. 启动 -> 自动恢复登录 -> 首页可用
2. Timeline三标签切换与下拉刷新
3. Profile筛选/排序/跳转详情
4. Subject页多Tab切换、收藏修改、章节进度变更
5. 设置页修改偏好后重启验证持久化
6. 手动检查更新流程(含忽略版本逻辑)

## 11. 常用命令

- flutter pub get
- flutter analyze
- flutter test
- flutter run
- flutter build apk --release
- flutter build windows --release

## 12. 建议优先阅读文件(按顺序)

1. lib/main.dart
2. lib/constants.dart
3. lib/services/api_client.dart
4. lib/services/storage_service.dart
5. lib/providers/auth_provider.dart
6. lib/providers/app_state_provider.dart
7. lib/providers/collection_provider.dart
8. lib/providers/update_provider.dart
9. lib/pages/subject_page.dart
10. lib/pages/timeline_page.dart
11. lib/pages/profile_page.dart
12. lib/pages/settings_page.dart
13. lib/models/subject.dart
14. lib/models/collection.dart
15. lib/widgets/responsive_scaffold.dart

## 13. 面向AI的修改策略

推荐策略:

1. 小步改动: 单次只动一个核心点，先过analyze和关键手测。
2. 保守兼容: 涉及缓存和模型时优先向后兼容，不轻易破坏旧格式。
3. 先补观察点再改: 对高风险路径先加最小日志/状态标记再修改，便于回归定位。
4. 不跨层重构: 除非明确需求，避免一次改动同时重排services+providers+pages。

红线:

1. 不要在未验证调用链时直接改缓存键名。
2. 不要把UI问题通过绕开Provider状态同步来“临时修好”。
3. 不要把GitHub更新请求复用带业务认证的Dio配置。

---

如果后续新增了模块(例如下载、播放、消息推送)，请同步更新本文件中的目录职责、数据流和验证清单。
