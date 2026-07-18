# 栖光 LumaNest 最终整改报告

**整改依据：** `docs/LUMANEST_FINAL_ENGINEERING_SPEC.md`、`docs/CODEX_EXECUTION_PROMPT.md` 与 Presentation V2 视觉验收意见  
**整改日期：** 2026-07-18  
**本次最终范围：** Android 客户端、全新 Presentation V2、自动化验收、真机 APK 与完整工作区源码包

## 最终结论

原有 Presentation 层已废弃，AppShell、五个一级页面和机会详情已使用独立的 `lib/src/presentation_v2/` Widget 树重建。Router 不再导入旧页面，旧页面源码、旧页面测试、15 张自生成 Golden 及其测试均已删除。领域模型、Provider、Drift、服务端接口、地图、安全通道、机会目录和音效能力继续作为数据与能力底座，不再作为旧 UI 兼容层。

最终自动化分析、Flutter 全量测试、Android Debug APK 干净构建和 Mi 10 Pro 覆盖安装均通过。本报告取代此前以旧页面和旧 Golden 为依据的审计结论。

## Presentation V2 整改结果

| 验收项 | 最终结果 | 证据 |
|---|---|---|
| 新 AppShell | 通过 | `lib/src/presentation_v2/shell/v2_app_shell.dart` |
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
| `flutter test` | 全量通过 |
| `flutter test test/acceptance/v2_compact_layout_test.dart --reporter expanded` | 2 项通过 |
| `./tool/flutter_with_environment.sh build apk --debug` | 通过 |
| Mi 10 Pro 覆盖安装 | 通过，包名 `com.muee.lumanest` |
| 真机前台与日志检查 | Activity 前台可见，无 Flutter fatal、exception 或 RenderFlex overflow |
| 源码包完整性 | 708 项；压缩数据校验通过；包含根目录 `audio/` |
| 源码包排除项 | 无 `.secrets`、Git 元数据、依赖、缓存、任意层级 `build`、APK 或签名材料 |

完整视觉比较、页面状态与真机截图证据见 `design-qa.md`。

## 影响范围

- 删除旧 AppShell、五个旧主页面、旧 ShootingWindow 呈现层及对应旧 UI 测试。
- Router 全量切换至 Presentation V2。
- 新增 V2 Shell、五个主页面、Opportunity、共享舞台/交互/加载/连续对象组件。
- 新增紧凑屏幕与放大字号验收，修复底栏切换动画和机会对象在受限空间中的布局。
- 删除旧 Golden 基准并更新最终验证记录。

## 已知风险

- 本次交付为 Debug APK，不是商店 Release 签名包。
- 按要求未构建或验证 iOS。
- 真机当前未授予位置权限时会进入产品定义的许可/参考地点降级流程；这不是构建失败。
- Inspiration 的现有瓶子与纸条资产仍偏插画化，可在后续品牌资产阶段替换，不影响 V2 空间结构和状态模型。

## 最终判定

**通过。Presentation V2 已取代旧 UI，Android APK 可安装运行，源码包已按最终工作区重新生成。**
