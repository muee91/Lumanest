> **文档权威级别：HISTORICAL / VERSIONED REFERENCE**
> 当前产品范围以 [`docs/core-1.0-scope.md`](docs/core-1.0-scope.md) 为准。本文仅保留历史代码审计证据，不能重新启用 Core 1.0 已冻结或退役的能力。

# 栖光 LumaNest 最终整改报告

**整改依据：** `docs/LUMANEST_FINAL_ENGINEERING_SPEC.md`、`docs/CODEX_EXECUTION_PROMPT.md` 与 Presentation V2 视觉验收意见  
**整改日期：** 2026-07-18  
**本次最终范围：** Android 客户端、全新 Presentation V2、SunsetBot P0 城市预测、自动化验收、真机 APK 与完整工作区源码包

## 最终结论

原有 Presentation 层已废弃，AppShell、五个一级页面和机会详情已使用独立的 `lib/src/presentation_v2/` Widget 树重建。Router 不再导入旧页面，旧页面源码、旧页面测试、15 张自生成 Golden 及其测试均已删除。领域模型、Provider、Drift、服务端接口、地图、安全通道、机会目录和音效能力继续作为数据与能力底座，不再作为旧 UI 兼容层。

最终自动化分析、Flutter 全量测试、Android Debug APK 干净构建和 Mi 10 Pro 覆盖安装均通过。本报告取代此前以旧页面和旧 Golden 为依据的审计结论。

## SunsetBot P0 接入结果

SunsetBot 已作为 Broker 内部 Provider Adapter 接入。Flutter 只消费 `/v1/sky-opportunities` 与 `/v1/sky-opportunities/daily` 的统一模型，不包含 SunsetBot 域名、事件代码、HTML 清洗、双模型聚合、城市别名或熔断逻辑。GFS 与 EC 默认并发；缓存、singleflight、重试、全局/城市并发限制、陈旧回退、熔断、Prometheus 指标和运行时 Feature Flag 均在服务端完成。

线上 release 为 `/vol2/docker/lumanest/releases/sunsetbot-p0-20260718T143306Z/qweather-token-broker`，部署前状态已备份到 `/vol2/docker/lumanest/backups/20260718T143315Z`。六个容器均为 healthy，Context 数据库迁移保持 `0009_feedback_condition_band (head)`，公共 App 端口 `/admin` 返回 404，局域网管理端口返回 200。

真实杭州 daily 首次请求同时获取今日晚霞与明日朝霞的 GFS/EC，四个模型均成功；第二次请求四项全部命中新鲜缓存。杭州今日晚霞聚合分数为 `0.005`，明日朝霞为 `0.0235`，均低于 0.20，因此首页不出现 SunsetBot 对象。Mi 10 Pro 的真实位置请求解析为嘉兴，四个模型也全部成功且均低于阈值；第二次启动不再回源。该结果证明按需展示和无占位规则在真实低分场景下生效。

区域趋势地图仍是规范定义的 P1；本地通知按第一阶段策略保持关闭，未冒充 P0 已上线能力。

## Presentation V2 整改结果

| 验收项 | 最终结果 | 证据 |
|---|---|---|
| 新 AppShell | 通过 | `lib/src/presentation_v2/shell/v2_app_shell.dart` |
| calLog 参考底栏 | 通过 | 四个常用入口共享移动选中对象，灵感为独立圆形主动作 |
| Today 中心对象结构 | 通过 | `lib/src/presentation_v2/today/v2_today_page.dart` |
| Explore 全屏地图与可拖拽结果对象 | 通过 | `lib/src/presentation_v2/explore/v2_explore_page.dart` |
| Route 规划态与行程中陪伴态 | 通过 | `lib/src/presentation_v2/route/v2_route_page.dart` |
| Inspiration 完整舞台、抽取与纸条状态 | 通过 | `lib/src/presentation_v2/inspiration/v2_inspiration_page.dart` |
| Profile 控制中心与三个二级页 | 通过 | `lib/src/presentation_v2/profile/v2_profile_page.dart` |
| Today 到机会详情对象连续性 | 通过 | 生产代码使用同一稳定 ID 的真实 `Hero` |
| V2 标准圆形加载器 | 通过 | `CircularProgressIndicator` 为 0 |
| 旧页面与旧 Router import | 通过 | 旧页面文件已删除，Router 无旧 Presentation import |
| 旧 Golden | 通过 | `test/goldens/` 不存在，Golden 状态为 0 |
| 360 x 800 紧凑布局 | 通过 | 五个一级页面无 RenderFlex overflow |
| 1.5 倍字号 | 通过 | Today 与 Opportunity 无 RenderFlex overflow |

## 保留的领域与工程能力

- 48 项机会 Catalog、16/3/29 目录层级、96 标签和创作提示数据。
- Riverpod 状态、Drift 持久化、环境 Context Snapshot、安全与机会规则。
- Explore 搜索任务、地图和路线基础能力。
- Companion 数据对象、灵感库存、音效资源与反馈服务。
- Data Broker、Context Service、Discovery Service 及其 API 契约。

`legacyOnly` 是工程规格内的目录分层，不能被主动生成，也没有被用于保留旧 UI；客户端旧 Presentation 兼容代码为 0。

## 验证记录

| 验证 | 结果 |
|---|---|
| `flutter analyze` | 通过，无 issue |
| `flutter test` | 482 项全量通过 |
| Broker `npm test` | 196 项全量通过 |
| Broker 全部 `.mjs` `node --check` | 通过 |
| Flutter 第三方协议泄漏扫描 | 通过；无 SunsetBot 域名、参数或事件代码 |
| `flutter test test/acceptance/v2_compact_layout_test.dart --reporter expanded` | 2 项通过 |
| `./tool/flutter_with_environment.sh build apk --debug` | 通过 |
| Mi 10 Pro 覆盖安装 | 通过，包名 `com.muee.lumanest`，位置权限有效 |
| 真机前台与日志检查 | Activity 前台可见，无 Flutter fatal、exception 或 RenderFlex overflow |
| NAS 隔离部署 | 通过；原子 release 指针与完整部署前备份均存在 |
| 真实 Sky daily API | 200；GFS/EC 全成功；二次请求缓存命中 |
| 源码包完整性 | 730 项；压缩数据校验通过；包含根目录 `audio/` 与 SunsetBot P0 验收文档 |
| 源码包排除项 | 无 `.secrets`、Git 元数据、依赖、缓存、任意层级 `build`、APK 或签名材料 |

完整视觉比较、页面状态与真机截图证据见 `design-qa.md`。

## 影响范围

- 删除旧 AppShell、五个旧主页面、旧 ShootingWindow 呈现层及对应旧 UI 测试。
- Router 全量切换至 Presentation V2。
- 新增 V2 Shell、五个主页面、Opportunity、共享舞台/交互/加载/连续对象组件。
- 使用运行中的 calLog 窗口与拆解二进制重建底栏；删除此前未采用的玻璃 Shader 和两套实验导航实现。
- 新增紧凑屏幕与放大字号验收，修复底栏切换动画和机会对象在受限空间中的布局。
- 删除旧 Golden 基准并更新最终验证记录。

## 已知风险

- 本次交付为 Debug APK，不是商店 Release 签名包。
- 按要求未构建或验证 iOS。
- 区域晚霞趋势地图属于 P1，尚未实现；`skyOpportunityMapEnabled` 默认关闭。
- 第一阶段不发送本地通知；`skyOpportunityNotificationEnabled` 默认关闭。
- 真机当前未授予位置权限时会进入产品定义的许可/参考地点降级流程；这不是构建失败。
- Inspiration 的现有瓶子与纸条资产仍偏插画化，可在后续品牌资产阶段替换，不影响 V2 空间结构和状态模型。

## 最终判定

**通过。Presentation V2 已取代旧 UI；SunsetBot P0 城市预测已部署并通过真实双模型、缓存和 Mi 10 Pro 验证；Android APK 可安装运行。**
