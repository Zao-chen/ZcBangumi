# 萌娘百科接入调研

调研日期：2026-10-08。范围：现有代码检查、少量匿名接口请求、公开网页和浏览器验证。本文是探索结论，尚未实现功能，也没有验证登录后的 API 能力。

## 建议

优先做“原生导航与阅读工具 + 萌百网页正文”的混合接入。第一阶段改善关联、目录、站内跳转和阅读位置；第二阶段单独验证经过正规认证的 API，再决定是否提供原生搜索、摘要和更多结构化内容。

当前证据不足以把萌娘百科当成可匿名调用的开放内容 API。完整正文转为 Flutter 原生组件的收益，也暂时不足以覆盖复杂模板的适配成本。

## 现有实现

入口在 `lib/pages/subject_page.dart` 的 `_buildMoegirlUri`、`_buildMoegirlTab`。当前仅作品详情页实际使用 `EmbeddedWebPageView`；Web 平台提供外部打开按钮。

`lib/pages/web_page_viewer.dart` 中的流程是：

1. 使用 Bangumi 中文名，缺少中文名时使用原名，生成萌百搜索 URL。
2. 用 Dio 获取网页，正则提取搜索结果，弹出 Flutter 选择列表。
3. 按搜索关键词记住选择的 URL。
4. 正则提取正文，包装自定义 CSS，通过 `InAppWebView.loadData` 渲染。
5. 链接交给 `InternalLinkHandler`；非 Bangumi 链接会在系统浏览器打开。

因此现状已经包含正文提取和搜索选词，并非直接显示完整网站的简单 WebView。

值得优先解决的代码问题：

| 位置 | 现象与影响 |
| --- | --- |
| `web_page_viewer.dart:157` | 映射键为 `moegirl_selection_<keyword>`；同名动画、漫画等会共用选择，且缺少重新绑定入口。 |
| `web_page_viewer.dart:315` | `mw-content-text` 兜底正则在第一个 `</div>` 停止，无法正确处理嵌套容器。 |
| `web_page_viewer.dart:389` 附近 | URL 处理依赖字符串替换；未统一处理 `srcset`，且页内锚点也会被补成完整网页地址。 |
| `web_page_viewer.dart:433` 附近 | 自定义文档未保留完整站点样式与脚本环境，复杂模板、折叠和黑幕的行为可能丢失；表格等多处固定 `#222222`，暗色适配不完整。 |
| `web_page_viewer.dart:674` | 萌百站内链接、经转换后的脚注链接被视作外链，无法形成连续阅读。 |
| `web_page_viewer.dart:89` | 无专门的超时、取消和请求代次处理；失败会清空正文，并把当前地址重置为初始搜索地址。 |

这些是代码检查结论；本轮没有在 Flutter 真机上复现全部行为。对本轮收到的截断 HTML 运行同等正文兜底正则，只提取出 934 个字符，说明此兜底路径确实存在截断风险；该样本不是完整网页，不能据此推断所有正常加载都会截断。

## 实测接口与网页

测试接口为 `https://zh.moegirl.org.cn/api.php`，无登录 Cookie、无账号凭据。请求使用 `format=json&formatversion=2`。

| 测试 | 结果 | 能说明什么 |
| --- | --- | --- |
| `action=query&meta=siteinfo&siprop=general\|rightsinfo\|extensions` | HTTP 200，有效 JSON | 站点为 MediaWiki 1.43.3，提供站点信息。 |
| `action=query&list=search&srsearch=葬送的芙莉莲&srnamespace=0&srlimit=5&origin=*` | HTTP 200，JSON 错误 `action-notallowed` | 本次匿名搜索调用被拒绝。 |
| `action=parse&page=葬送的芙莉莲&prop=text\|sections\|displaytitle\|revid\|categories\|links\|images` | HTTP 200，同一 JSON 错误 | 本次匿名正文解析调用被拒绝。 |
| `query` 的重定向、摘要、图片组合请求 | SSL 连接超时 | 此项没有取得能力结论，不能当成权限拒绝或接口不存在。 |
| `/api.php` 帮助页 | HTTP 200，浏览器可读 | 存在 API 文档；文档列出能力不代表匿名请求有权限。 |
| 《葬送的芙莉莲》公开网页 | 浏览器可以正常显示正文、目录和页脚 | 网页阅读路径可行。 |

两项被拒绝的接口均返回：

```json
{
  "error": {
    "code": "action-notallowed",
    "info": "Unauthorized API call"
  }
}
```

搜索响应带 `Access-Control-Allow-Origin: *`，但业务请求仍被拒绝。未来实现必须同时检查 HTTP 状态与 JSON `error`，不能用 HTTP 200 判断请求成功。

站点信息列出了 TextExtracts、PageImages、CirrusSearch、TemplateStyles、Scribunto 等扩展。这只证明站点安装了这些能力，不证明当前客户端可调用。

### 浏览器与网络观察

《葬送的芙莉莲》样本在浏览器中可以读取章节标题及锚点。正文 DOM 有 43 个表格、18 个匹配折叠类的元素、4 个黑幕元素。无需复制整篇内容，就可以从当前阅读页面生成原生目录。

同一页面包含漫画信息和“衍生作品 → 动画版”等章节。Bangumi 的动画条目可能适合绑定到萌百系列页的某个章节，而不是强求两个站点一一对应。

命令行抓取该长页面时，通过现有 `127.0.0.1:7890` 代理和显式直连均收到 HTTP 200，但分别出现部分传输和限时内未完成的问题；浏览器最终正常显示页面。这是本次网络样本，不能推断为所有用户、所有网络的稳定性结论。已停止重复抓取长页面。

公开文章响应带 `X-Frame-Options: DENY`。Flutter Web 不能简单把原站放入 iframe；原生 WebView 顶层导航不属于同一种嵌入方式。Web 平台继续采用外部打开，是当前明确可行的路径。

站内搜索输入 `API` 后可以导航，但命中了重定向 `Api → A_Pi`。这也说明搜索自动跳转、标题大小写和歧义不能等同于可靠的实体匹配；此样本没有找到专门的接口申请说明。

## 认证接入仍有探索价值

公开社区项目 [AnnAngela/moegirlpedia-mediawiki-api](https://github.com/AnnAngela/moegirlpedia-mediawiki-api) 的 README 明确要求萌百账号和 Bot Password，并描述了登录后的搜索、HTML 正文、章节、摘要等操作。

这是一条可供后续验证的技术线索，不是萌百官方对第三方客户端的可用性承诺。本轮只阅读了 README，没有安装或运行该工具，也没有使用账号凭据。

需要进一步确认：

- 普通账号登录是否足以调用目标只读接口，还是需要额外权限或应用授权。
- 普通网页登录会话能否用于目标 API；它与 Bot Password 是否有不同权限及生命周期。
- 第三方客户端的调用频率、缓存、内容展示和分发条件。
- 如果采用用户各自登录，Android、iOS 和桌面端会话隔离与退出行为如何实现。

不要把开发者的 Bot Password 打包进 App，也不能把用户登录与公共服务授权混为一谈。若后续需要共享服务端访问，应先确认站方许可和服务约束。

## 三种方案比较

| 方案 | 用户能得到什么 | 主要成本 / 条件 | 判断 |
| --- | --- | --- | --- |
| 原网页 + 原生阅读工具 | 站内连续阅读、返回、目录、定位、重新关联 | WebView 生命周期和手势适配；目录 DOM 可能随皮肤变化 | 适合作为第一阶段原型。 |
| 授权 API + HTML 阅读器 | 原生搜索、目录、部分摘要，正文仍用网页技术显示 | 先验证认证和使用条件；仍需适配模板样式与交互 | 作为中期方向。 |
| 全文 Flutter 原生化 | 最大程度统一视觉及组件行为 | 复杂表格、模板、脚注、黑幕、媒体持续维护；仍依赖可用数据源 | 暂不建议作为首期目标。 |

直接换成 `flutter_html` 可以覆盖基础 HTML，但不会自动还原 MediaWiki 模板及脚本行为。项目已有 `html` 与 `flutter_html` 依赖；若继续维护当前提取式阅读器，可用 DOM 解析替换正则，但这只是修复解析方式，不能解决接口权限和完整渲染问题。

## 第一阶段可落地范围

建议先完成作品详情页内的闭环，再考虑角色和人物页。

1. **可靠关联**：按 `subject:<Bangumi ID>` 保存萌百 URL、标题和可选章节锚点；提供“重新搜索 / 绑定当前页面 / 解除关联”。旧关键词映射只作为候选迁移，不强行视作已确认关系。
2. **连续阅读**：同页锚点留在当前页；萌百文章链接在阅读器内导航；返回先退网页历史，再退出页面；Bangumi 链接继续进入应用原生详情。
3. **原生目录**：读取当前网页的章节层级和真实锚点，支持底部目录面板。保留重复标题对应的不同 ID，以及 MediaWiki 的旧式编码锚点。
4. **阅读位置**：按具体萌百页面保存章节和滚动位置；记录所属修订信息（页面能够可靠提供时），内容变化后优先恢复章节，避免只靠像素定位。
5. **完整网页加载**：先验证直接由 WebView 加载公开文章的方案，保留站点原有复杂内容和会话环境。原生工具与正文承载分开，未来可替换为经过授权的 HTML 数据源。
6. **失败恢复**：区分无结果、页面不存在、网络错误和访问验证；提供重试与外部打开；仅完整有效内容可作为成功结果。元数据缓存先覆盖关联和阅读位置。

建议拆分为 `MoegirlBinding`、`MoegirlReadingPosition`、独立的萌百阅读器及导航策略，避免继续把站点专属逻辑堆进通用 `WebPageViewer`。

第一阶段原型应验证：同名动画与漫画独立绑定、重新绑定后立即生效、脚注不外跳、作品到角色再返回的位置恢复、长页与横向表格、黑幕和折叠功能、明暗主题、弱网失败、Tab 横滑与网页竖滑、Web 平台外部打开。原生端的 Cookie、代理和图片请求链路需要各平台实际测试；Dio 的代理配置不会自动证明 WebView 使用同一路径。

## 内容使用条件

当前 [著作权信息](https://zh.moegirl.org.cn/萌娘百科:著作权信息)、文章页脚和 `siteinfo.rightsinfo` 指向 **CC BY-NC-SA 4.0**。页面要求注明来自“萌娘百科”并提供原页面完整链接；其他类型作品按各自权利和授权处理。

另有两个需要纳入方案的站方声明：

- [robots.txt](https://zh.moegirl.org.cn/robots.txt) 对通用自动抓取列出了 `/index.php`、特殊页面等限制，不能据公开网页可访问就设计批量爬取。
- [llms.txt](https://zh.moegirl.org.cn/llms.txt) 表达了限制 AI 全文复刻和等同信息框的结构化数据集等要求，且其中写的许可版本仍为 3.0 CN，与当前文章页脚 / 著作权页的 4.0 不一致。

这些文件是站点政策资料。版本不一致需要后续向站方澄清，不能自行合并成统一授权；尤其不宜据此直接规划全文镜像、数据集或批量离线库。首期以用户阅读原站、应用保存关联与阅读状态为边界更清晰。

## 资料与证据边界

- [萌娘百科 API 帮助](https://zh.moegirl.org.cn/api.php)
- [站点信息接口](https://zh.moegirl.org.cn/api.php?action=query&meta=siteinfo&siprop=general%7Crightsinfo&format=json&formatversion=2)
- [实测文章：葬送的芙莉莲](https://zh.moegirl.org.cn/葬送的芙莉莲)
- [社区认证 API 工具说明](https://github.com/AnnAngela/moegirlpedia-mediawiki-api)
- [萌娘百科著作权信息](https://zh.moegirl.org.cn/萌娘百科:著作权信息)
- [robots.txt](https://zh.moegirl.org.cn/robots.txt)、[llms.txt](https://zh.moegirl.org.cn/llms.txt)

结论适用于本次匿名请求和单个长词条样本；没有完成跨平台真机验证、登录后接口验证或站方授权确认。后续产品决策应区分“已实测”“社区描述”和“拟实现”。
