#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise SystemExit(f"{path}: expected one anchor, found {text.count(old)}")
    path.write_text(text.replace(old, new), encoding="utf-8")


# 1) Production /environment must use the actionable workbench, not the retired timeline.
router = ROOT / "lib/src/app/router.dart"
replace_once(
    router,
    "import 'package:luma_nest/src/presentation_v2/environment/v2_environment_timeline_page.dart';\n",
    "",
)
replace_once(
    router,
    """      GoRoute(\n        parentNavigatorKey: rootNavigatorKey,\n        path: '/environment',\n        pageBuilder: (context, state) => _v2DetailPage(\n          state,\n          child: V2EnvironmentTimelinePage(\n            initialSnapshot: initialContext,\n            initialFocus: EnvironmentTimelineFocus.fromQuery(\n              state.uri.queryParameters['focus'],\n            ),\n          ),\n        ),\n      ),\n""",
    """      GoRoute(\n        parentNavigatorKey: rootNavigatorKey,\n        path: '/environment',\n        pageBuilder: (context, state) => _v2DetailPage(\n          state,\n          child: V2EnvironmentWorkbenchPage(initialSnapshot: initialContext),\n        ),\n      ),\n""",
)

# 2) Stop dead Companion network work at the root. Keep the client implementation for a
# later dependency-removal pass, but it must no longer run automatically without a consumer.
app = ROOT / "lib/src/app/luma_nest_app.dart"
replace_once(
    app,
    "import 'package:luma_nest/src/core/companion/companion_client.dart';\n",
    "",
)
replace_once(app, "  String? _lastCompanionRefresh;\n", "")
replace_once(
    app,
    """    if (reconciliationSnapshot != null &&\n        _lastCompanionRefresh != reconciliationSnapshot.id) {\n      _lastCompanionRefresh = reconciliationSnapshot.id;\n      WidgetsBinding.instance.addPostFrameCallback((_) {\n        if (!mounted) return;\n        unawaited(\n          ref\n              .read(companionInventoryProvider.notifier)\n              .refresh(\n                snapshotId: reconciliationSnapshot.id,\n                reason: 'manual_refresh',\n                visiblePage: _visiblePage,\n              ),\n        );\n      });\n    }\n""",
    "",
)
replace_once(
    app,
    """  String get _visiblePage {\n    if (_routeLocation.startsWith('/explore')) return 'explore';\n    if (_routeLocation.startsWith('/route')) return 'route';\n    if (_routeLocation.startsWith('/inspiration')) return 'inspiration';\n    if (_routeLocation.startsWith('/profile')) return 'profile';\n    if (_routeLocation.startsWith('/session')) return 'shootingWindow';\n    return 'today';\n  }\n\n""",
    "",
)

# 3) Make repository entry points describe the product that actually ships.
readme = ROOT / "README.md"
readme.write_text(
    """# LumaNest · 栖光\n\n栖光——循光而行，择光而栖。\n\n一个以**拍摄决策为第一优先级**的环境感知摄影与探索助手。当前开发范围以\n[`docs/core-1.0-scope.md`](docs/core-1.0-scope.md) 为唯一产品范围权威。\n\n## Core 1.0\n\n当前应用只有四个常驻一级入口：\n\n- **今日**：现在/今天最值得关注的一个拍摄机会。\n- **探索**：到达一个区域后，理解这里值得拍、值得看、值得体验什么。\n- **路线**：去一个目的地途中需要提前知道的摄影、天气、限制与补给信息；导航交给外部地图。\n- **我的**：少量真正需要保存的偏好与内容。\n\n**栖光 AI** 是全局按需入口，不是第五个常驻 Tab。旧 `/inspiration` 仅保留深链兼容并进入同一 AI 页面。\n\n当前产品不以 Provider 数量、机会目录数量、模型数量或后台能力数量作为完成度。功能只有在生产入口可达、用户能看懂并能据此行动时才算完成。\n\n## 文档\n\n先读 [`docs/README.md`](docs/README.md)。版本化设计、审计和历史 Markdown 都是支持材料；与 Core 1.0 冲突时不能恢复已冻结能力。\n\n## 验证\n\n```bash\nflutter analyze\nflutter test\n./tool/flutter_with_environment.sh test\n```\n\n真实 Broker 集成测试使用：\n\n```bash\n./tool/flutter_with_environment.sh test-configured <测试路径>\n```\n\n真机运行使用：\n\n```bash\n./tool/flutter_with_environment.sh run\n```\n\nDebug APK 仍可在本地按需构建，但当前 GitHub CI 的职责是 Flutter analyze/test 与服务测试，不把远端 APK artifact 当作发布闭环。\n""",
    encoding="utf-8",
)

core_scope = ROOT / "docs/core-1.0-scope.md"
core_scope.write_text(
    """# 栖光 Core 1.0 产品范围\n\n> **状态：CURRENT · PRODUCT SCOPE AUTHORITY**  \n> 本文是当前产品范围的最高仓库级权威。历史设计、版本化方案、审计、实现说明与测试契约可以补充实现细节，但不得扩大本文定义的产品范围。\n\n## 1. 产品目标\n\n栖光首先解决摄影者在真实行动中的五个问题：\n\n1. **拍不拍？**\n2. **什么时候拍？**\n3. **哪里拍？**\n4. **怎么到？**\n5. **到了以后拍什么？**\n\n不能直接帮助以上问题的新能力，默认不进入 Core 1.0。\n\n## 2. 当前四个一级入口\n\n### 今日\n\n只给一个当前最重要的拍摄判断。先结论，再给 2–3 个依据、必要限制和一个下一步动作。没有可靠主机会时不制造机会。\n\n### 探索\n\n回答“这里是什么、适合拍什么、有什么值得去/看/吃/体验”。地图、区域简报、人文线索和地点是用户对象；Provider、evidence debt、verification state 等内部机制不是用户对象。\n\n### 路线\n\n回答“去那里途中有什么值得提前知道”。保留真实路线、route corridor、scout、天气变化、官方限制、拍摄节点、补给/加油和到达时段；最终导航交给高德等外部地图。Core 1.0 不建设行程追踪器。\n\n### 我的\n\n只承载必要偏好与少量保存内容。优先保留收藏地点、收藏灵感和最近目的地。\n\n### AI\n\nAI 是全局按需入口，不是常驻一级 Tab。它解释已知事实、回答问题、给创作建议；需要新鲜外部资料时未来统一通过 Research Gateway 调研，不直接把外部渠道变成新的产品模块。\n\n## 3. Core 1.0 保留能力\n\n- 当前天气、云层、风、降水、能见度与光线事实。\n- 单一主拍摄机会与可解释的候选窗口。\n- SunsetBot 等已存在的摄影专业增强，但失败必须独立降级。\n- 高德地图/路线与 OSM 地点线索。\n- Region Brief 与实用人文/区域信息。\n- Route Corridor / Scout / 官方限制 / 补给与外部导航。\n- 单一 AI 入口与确定性安全边界。\n- DEM 地平线遮挡、VIIRS 光污染：作为按需摄影增强，不成为常驻页面负担。\n- GBIF / iNaturalist：仅作为按需区域生态背景，不生成精确动物导航或概率。\n\n## 4. 冻结、退役或移出当前运行主线\n\n以下能力即使代码仍暂时存在，也不能因为历史文档或旧目录而继续扩张：\n\n| 能力 | Core 1.0 状态 | 处理原则 |\n| --- | --- | --- |\n| Companion 自动 inventory/refresh | **退役** | 不允许无用户可见消费者的自动网络工作；后续删除残余实现 |\n| Route Journey start/end/active/progress | **冻结并准备删除** | Route 回归 scout + corridor + 外部导航 |\n| 拍摄窗口 Watch/通知 | **P2 冻结** | Core 判断稳定后再评估 |\n| Offline Photography Pack | **P2 冻结** | 不继续扩展 |\n| GPX 导入/轨迹生命周期 | **P2 冻结** | 不继续扩展 |\n| Shooting feedback/calibration | **冻结** | 不作为落地前阻塞项 |\n| 29 个 reserved opportunity | **移出当前产品范围** | 可保留历史规划，不得驱动运行时/UI 扩张 |\n| 大规模 Creative Prompt / Tag 目录 | **收缩候选** | 只保留实际能被用户消费的少量集合 |\n| 非核心科学 Provider | **默认关闭** | 只有明确用户价值链后再启用 |\n| 原生音效系统 | **准备删除** | 最多保留轻量系统触觉 |\n| Ambient 渲染框架继续扩张 | **冻结** | 保留现有品牌氛围，不再平台化 |\n| 多模型 fallback/Agent 平台继续扩张 | **冻结** | Core 只要求一个当前模型 + 确定性降级 |\n\n## 5. Provider 范围\n\n### 核心/默认链\n\nQWeather、高德、OSM、官方限制/公告，以及区域身份需要的 Wikidata/Wikimedia。\n\n### 按需摄影增强\n\nSunsetBot、DEM、VIIRS、GBIF、iNaturalist。缺失时必须隐藏或独立降级。\n\n### 默认关闭/冻结\n\nSentinel-1、Sentinel-2、CAMS、AERONET、FIRMS、Copernicus Marine、JPL Horizons、NOAA SWPC、eBird。存在适配器不等于当前产品需要启用。\n\n## 6. Research Gateway\n\nAgent Reach 与 Crawl4AI 不作为新的常驻 Provider 集群。Core 收缩完成后，只允许通过统一 `ResearchGateway` 在以下情况触发：\n\n1. 用户明确要求深入了解/联网核验；\n2. Region Brief 有真实证据缺口；\n3. AI 回答必须依赖新鲜外部资料。\n\nCrawl4AI 负责深读允许的网站；Agent Reach 负责按需跨渠道寻找资料。结果必须先经过 Evidence/来源边界，再进入 Region Brief 或 AI。\n\n## 7. 功能准入门槛\n\n新增 Provider、后台 worker、常驻页面、机会 family、路由生命周期、模型 fallback 或持久化类型前，必须回答：\n\n- 它具体改善五个核心问题中的哪一个？\n- 现有能力为什么不能完成？\n- 用户在哪里看到/使用结果？\n- 上游不可用时是否独立降级？\n- 是否增加新的常驻 UI、后台轮询或长期维护面？\n\n如果没有明确答案，不进入当前实现。\n\n## 8. “完成”的定义\n\n一个功能只有同时满足以下条件才算完成：\n\n1. **生产入口已接线**：真实 Router/页面/服务路径正在使用它，不是仓库里存在一个实现文件。\n2. **用户可见且可行动**：用户能理解结论，并知道下一步。\n3. **没有死工作**：没有无消费者的自动刷新、轮询或库存生成。\n4. **边界诚实**：缺数据隐藏；候选不包装成概率；安全只用授权链。\n5. **回归验证通过**：相关测试和仓库 CI 通过。\n\n“代码已写”“测试已过”“Provider 已接”都不能单独等同于产品完成。\n""",
    encoding="utf-8",
)

docs_index = ROOT / "docs/README.md"
docs_index.write_text(
    """# 栖光文档索引与权威规则\n\n> **先读：[`core-1.0-scope.md`](core-1.0-scope.md)**\n\n仓库过去累积了大量阶段性方案。为避免旧 Markdown 重新驱动已经冻结的功能，文档按以下权威级别解释。\n\n## 权威顺序\n\n1. **产品范围权威**：`core-1.0-scope.md`。\n2. **强制契约**：当前公开接口契约、隐私/安全边界、当前自动化测试。它们约束“怎么安全实现”，但不能自行扩大产品范围。\n3. **当前支持文档**：运维 runbook、数据源说明、当前 UI 清晰度规范、路线 scout 说明。\n4. **历史/版本化/审计文档**：`*-v1.md`、`*-v2.md`、`audits/` 以及已经被后续实现替代的设计说明。只用于追溯决策。\n\n发生冲突时，高一级文档优先。历史文档不能恢复 Core 1.0 已冻结或退役的功能。\n\n## 当前阅读路径\n\n- 产品范围：`core-1.0-scope.md`\n- AI 回答可读性：`assistant-answer-clarity.md`\n- AI 上下文边界：`assistant-context-envelope.md`\n- 环境页可读性：`environment-workbench-clarity.md`\n- 路线探路：`route-scout-mode.md`\n- 生态来源：`ecology-data-sources.md`\n- Provider 运维：`provider-operations-runbook.md`\n- 可观测性：`operational-observability.md`\n\n## 历史材料处理规则\n\n历史文件默认保留，不批量删除，因为它们仍有架构决策和验收背景价值。但：\n\n- 不把历史数量目标（例如 48 个机会、96 个标签）当作当前交付目标；\n- 不因为旧文档出现一个页面/Provider/后台任务就重新实现；\n- 任何从历史文档恢复能力的改动，必须先修改 `core-1.0-scope.md`；\n- 后续整理时优先合并重复文档，而不是继续新增同主题版本。\n\n仓库中除本文件和 `core-1.0-scope.md` 外的 Markdown，会被标记为“支持性”或“历史/版本化参考”，明确其产品范围权威低于 Core 1.0。\n""",
    encoding="utf-8",
)

# 4) Make AGENTS reflect current IA and document authority. Do not rewrite the
# engineering safeguards; only correct the stale product scope and add a hard scope gate.
agents = ROOT / "AGENTS.md"
text = agents.read_text(encoding="utf-8")
authority = """## 0. 当前产品范围权威（必须先读）\n\n任何涉及产品行为、页面、Provider、后台任务、机会模型或 AI 能力的修改，开始前必须先读：\n\n1. `docs/core-1.0-scope.md`\n2. `docs/README.md`\n\n历史/版本化/审计 Markdown 只能提供实现背景，**不能重新启用 Core 1.0 已冻结或退役的功能**。\n\n“完成”必须同时包含生产入口接线和用户可见结果；仅存在实现文件、测试通过、Provider 已接入都不算产品完成。未经明确范围变更，不新增常驻一级入口、Provider、opportunity family、后台 worker、Journey 生命周期或模型 fallback 层。\n\n---\n\n"""
anchor = "---\n\n## 1. 指令优先级与事实来源\n"
if authority not in text:
    if text.count(anchor) != 1:
        raise SystemExit("AGENTS authority anchor mismatch")
    text = text.replace(anchor, "---\n\n" + authority + "## 1. 指令优先级与事实来源\n")
old_nav = """### 2.2 五个一级目的地\n\n一级导航保持：\n\n- 今日\n- 探索\n- 路线\n- 灵感\n- 我的\n\n不得随意增加新的常驻一级入口。新增能力应优先落入现有信息架构，或根据环境按需出现。\n"""
new_nav = """### 2.2 四个常驻一级目的地 + 一个按需 AI 入口\n\n一级导航保持：\n\n- 今日\n- 探索\n- 路线\n- 我的\n\nAI / 灵感已经合并为同一个全局按需入口，不再占一个常驻 Tab。旧 `/inspiration` 只是兼容深链。不得随意增加新的常驻一级入口。新增能力应优先落入现有信息架构，或根据环境按需出现。\n"""
if text.count(old_nav) != 1:
    raise SystemExit("AGENTS nav anchor mismatch")
text = text.replace(old_nav, new_nav)
agents.write_text(text, encoding="utf-8")

# 5) Mark historical/supporting Markdown so old plans cannot silently become scope.
for path in sorted((ROOT / "docs").rglob("*.md")):
    if path in {core_scope, docs_index}:
        continue
    raw = path.read_text(encoding="utf-8")
    if "PRODUCT SCOPE AUTHORITY" in raw or "文档权威级别：" in raw:
        continue
    rel = path.relative_to(ROOT).as_posix()
    historical = "/audits/" in f"/{rel}" or "-v1.md" in rel or "-v2.md" in rel
    level = "HISTORICAL / VERSIONED REFERENCE" if historical else "SUPPORTING DOCUMENT"
    banner = (
        f"> **文档权威级别：{level}**  \n"
        "> 当前产品范围以 [`core-1.0-scope.md`](core-1.0-scope.md) 为准。"
        "若本文与 Core 1.0 冲突，本文只能作为历史/实现参考，不能重新启用已冻结能力。\n\n"
    )
    path.write_text(banner + raw, encoding="utf-8")

print("Core 1.0 cleanup patch applied")
