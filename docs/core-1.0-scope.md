# 栖光 2.0 产品范围（任务优先重构阶段）

> **状态：CURRENT · PRODUCT SCOPE AUTHORITY · 2026-11-03**
> 本文是当前产品范围的最高仓库级权威。文件名保留 `core-1.0-scope.md` 以避免历史链接失效；本文内容记录 2.0 任务优先重构阶段的真实运行面。历史设计、版本化方案、审计、实现说明与测试契约可以补充实现细节，但不得把尚未交付的能力写成已完成。

## 1. 产品目标

栖光首先解决摄影者在真实行动中的五个问题：

1. **拍不拍？**
2. **什么时候拍？**
3. **哪里拍？**
4. **怎么到？**
5. **到了以后拍什么？**

不能直接帮助以上问题的新能力，默认不进入当前 2.0 运行范围。

## 2. 当前三个一级入口与路线任务场景

### 此刻

**开放的 `TripTask` 优先于普通天气/机会首页**：在有进行中任务时，以任务投影的 `quiet / watching / traveling / onSite` 模式作为当前主舞台；没有任务时，仍只给一个当前最重要的拍摄判断。先结论，再给依据、必要限制和一个下一步动作。

当前任务状态来自本地已持久化的 `TripTask`，而不是新的服务端 Scene API。云端启用、停止及行程状态必须明确区分本地意图与**上次确认的服务端状态**；未确认时不得宣称后台守候已生效，已确认也不得承诺远程通知必达。现场状态是用户手动选择，不代表 GPS 已核验抵达。没有可靠天气、ETA、拍摄窗口时不制造事实。原有环境安全警告在可获得时仍应可查看、可行动。

此任务优先主舞台是 2.0 的首个客户端投影，不意味着云端场景合约、远程推送、实时语音或相机 HUD 已交付。

### 发现

回答“这里是什么、适合拍什么、有什么值得去/看/吃/体验”。地图、区域简报、人文线索和地点是用户对象；Provider、evidence debt、verification state 等内部机制不是用户对象。

### 路线

路线不是底栏一级入口，而是从出行任务或明确地点进入的全屏行动场景。它回答“去那里途中有什么值得提前知道”，保留真实路线、route corridor、scout、天气变化、官方限制、拍摄节点、补给/加油和到达时段；最终导航交给高德等外部地图。

### 我的

只承载必要偏好与少量保存内容。优先保留收藏地点、收藏灵感和最近目的地。

### AI

AI 是全局按需入口，不是常驻一级 Tab。它解释已知事实、回答问题、给创作建议；需要新鲜外部资料时未来统一通过 Research Gateway 调研，不直接把外部渠道变成新的产品模块。

现有客户端 `TripTaskCommandParser` 只是确定性、严格匹配的临时意图入口，**不是服务端 Agent 业务工具**。疑问句与包含命令词的解释不能触发任务变更；建立计划、开始行程、手动到场、完成、取消及开启后台守候必须再次明确确认，同时复核任务状态未被其他动作改变。用户主动输入的精确「停止守候」可直接执行撤销请求。未来切换结构化工具协议时继续沿用这些确认与版本校验约束。

### 出行任务

`TripTask` 是当前 2.0 的统一出行意图对象，状态按 `planning → enRoute → field → completed` 顺序推进，也可以从任一开放状态取消。它保存目的地、交通方式、时间和可选的拍摄会话关联，并投影到路线场景与现有环境上下文。

当前任务保留本地副本；新任务在设备会话可用时会通过 Broker 镜像到服务端 Mission。服务端使用 PostgreSQL `mission` schema、幂等/版本操作和独立 Worker 进行事实检查，但专用 NAS 角色、迁移、Worker profile 与真实重启验收仍需单独完成。远程推送、实时轨迹和跨设备恢复仍未交付。

## 3. 当前保留能力

- 当前天气、云层、风、降水、能见度与光线事实。
- 单一主拍摄机会与可解释的候选窗口。
- SunsetBot 等已存在的摄影专业增强，但失败必须独立降级。
- 高德地图/路线与 OSM 地点线索。
- Region Brief 与实用人文/区域信息。
- Route Corridor / Scout / 官方限制 / 补给与外部导航。
- **Field Mode**：拍摄机会详情页中的前台现场状态。只有用户进入明确的
  `ShootingSession` 与审核 `ShootingTarget`，并取得真实前台设备定位后才生效；
  用于判断接近/到达机位、当前拍摄阶段和下一步动作。不得后台持续定位、记录轨迹、
  形成 Journey，或用手动地点/基础区域确认真实到达。
- **Active Saved Place（旧地方，新机会）**：在当前 fresh `ContextSnapshot` 已有的
  `ShootingSession` 与审核 `ShootingTarget` 中重新匹配收藏地点。它只重新激活本地记忆，
  不创建新机会，不扩大审核 `arrivalRadius`，不使用 `unknown` 坐标，不后台扫描全部收藏点，
  不增加多地点天气请求，也不发送远程推送。
- 单一 AI 入口与确定性安全边界。
- DEM 地平线遮挡、VIIRS 光污染：作为按需摄影增强，不成为常驻页面负担。
- GBIF / iNaturalist：仅作为按需区域生态背景，不生成精确动物导航或概率。
- **本机定时提醒**：仅针对用户显式守候的拍摄窗口，每窗口最多一条系统通知。若用户已经为同一审核机位计算真实路线，则优先使用 `ShootingExecutionResolver` 给出的最晚出发时间；没有可验证路线计划时才退回窗口开始前 15 分钟。已排程的更早出发提醒不得因进程重启、瞬时 Route 状态丢失而被静默降级；stale、机会消失或窗口结束后取消。提醒只陈述窗口/出发时间、成立条件与数据时间，不得出现成功率或概率表述。
- **任务优先路线场景**：路线由明确地点或开放 `TripTask` 驱动；当前任务优先于最近历史路线，任务创建失败或地点结果有歧义时不得自动打开路线页。
- **被动常驻表面（contract-only，未交付）**：`context-v5.policy.json` 已允许 `widget` surface，Context Service 也有过期标记规则，但仓库当前没有任何 Android/iOS 原生 Widget 消费者。在有真实平台实现之前，Widget 不得作为已交付能力对外承诺；服务端不得为没有消费者的 surface 扩散行为。近期无实现计划时将从 Core 移出，只保留本机通知。

## 4. 冻结、退役或移出当前运行主线

以下能力即使代码仍暂时存在，也不能因为历史文档或旧目录而继续扩张：

| 能力 | 2.0 当前状态 | 处理原则 |
| --- | --- | --- |
| Companion 自动 inventory/refresh | **已退役** | Flutter 与服务端 refresh/inventory/feedback 产品链、模型筛选器均已删除；AI/Region Brief 只保留独立的内部 `ContextSnapshotStore` 快照绑定 |
| Route Journey start/end/active/progress | **已删除（2026-09-26）** | Route 回归 scout + corridor + 外部导航；SavedJourney、恢复器与持久化表均已移除 |
| Shooting feedback/calibration | **已删除（2026-09-26）** | 隐私开关、`shareAnonymousPhotographyFeedback` 偏好、Broker `/v1/context/target-session` 与 `/v1/context/shooting-feedback` 路由、Context Service feedback/calibration 端点与数据表均已移除 |
| 未守候窗口的自动提醒 | **分期待放开** | 只有 §「本机定时提醒」验证过兑现率后，才按开口许可契约逐级放开；不得先做抢占再做校准 |
| 远程推送 / 真后台重算 | **冻结** | 前台提前排程本机通知已覆盖绝大部分主动场景；推送需要 APNs 后端、证书与配额，且在数据不准的时间尺度上开口正是同类产品的失败点 |
| 服务端 Mission Engine / 后台主动守候 | **基础实现，未完成验收** | Broker API、`mission` schema、幂等/版本/事件表和独立 Worker 已接线；专用 NAS 角色、真实迁移/重启验证和通知通道仍未完成，不得把它描述成已交付主动副驾 |
| Agent 业务工具调用 | **未交付** | 当前 AI 目的地任务仍由客户端确定性解析和现有地点搜索接线，尚不是服务端行动编排 |
| 实时语音副驾 | **未交付** | 尚无 Realtime 会话和语音驱动任务链路 |
| iOS Live Activity / Dynamic Island | **冻结** | 需要 entitlement 与扩展 target，成本最高收益最低 |
| Offline Photography Pack | **已删除（2026-09-26）** | 生成链与 Library 展示已移除；schema 18 重建时本地残留数据一并清除 |
| GPX 导入/轨迹生命周期 | **已删除（2026-09-26）** | 导入服务、解析器、`ImportedRouteTrack` 与存储表均已移除 |
| 29 个 reserved opportunity | **移出当前产品范围** | 可保留历史规划，不得驱动运行时/UI 扩张 |
| 大规模 Creative Prompt / Tag 目录 | **收缩候选** | 只保留实际能被用户消费的少量集合 |
| 非核心科学 Provider | **默认关闭** | 只有明确用户价值链后再启用 |
| 原生音效系统 | **已删除（2026-09-26）** | `assets/audio`、MethodChannel 音效链与原生 SoundPool/AVAudioPlayer 已移除；交互反馈只保留系统触觉 |
| Ambient 渲染框架继续扩张 | **冻结** | 保留现有品牌氛围，不再平台化 |
| 多模型 fallback/Agent 平台继续扩张 | **冻结** | Core 只要求一个当前模型 + 确定性降级 |

## 5. 运行面清单（2026-11-03 · 2.0 基线）

本节是当前真实运行面的权威清单。本次基线同步记录 Route safety hierarchy、Field Mode
和 Active Saved Place；新增、删除或改名任何条目时必须同步更新本节，并让 CI 路由清单测试阻止冻结路径重新出现。

### 5.1 Broker API

**Core（常驻产品链）**

- `POST /v1/context/snapshot` — 环境快照与 V5 entries
- `POST /v1/context/safety-detail` — 安全事件详情
- `GET /v1/sky-opportunities` — 当前天象机会
- `GET /v1/sky-opportunities/daily` — 首页日级机会批量读取（独立 forecast 语义，与单次查询不是同义重复）
- `POST /v1/explore/discover`、`POST /v1/explore/brief`、`GET /v1/explore/place-media`、`GET /v1/explore/media/:id`
- `POST /v1/route/weather` — 路线走廊天气
- `POST /v1/assistant`、`POST /v1/narrative` — 受约束的模型表达

**地图/路线**

- `POST /v1/amap/nearby`、`/v1/amap/search`、`/v1/amap/driving`、`/v1/amap/walking`、`/v1/amap/scene-evidence`

**按需摄影增强（失败独立降级）**

- `POST /v1/wildlife/nearby`、`/v1/wildlife/layers`
- `POST /v1/elevation`、`/v1/elevation/profile`
- `POST /v1/environment/site-facts`、`/v1/environment/provider-facts`、`/v1/environment/sky-windows`
- `POST /v1/weather/7timer`

**已删除（CI 阻止重新出现）**

- `POST /v1/context/target-session`
- `POST /v1/context/shooting-feedback`

### 5.2 客户端路由

- 常驻：`/today`（此刻）、`/explore`（发现）、`/profile`（我的）
- 任务场景：`/route`（从开放任务或明确地点进入的全屏路线场景）
- 全局按需：`/intelligence`（`/inspiration` 仅作兼容深链映射）
- 二级：`/environment`、`/sky-opportunity/:event/:dayOffset`、`/session/:id`、`/place/:id`、`/profile/style`、`/profile/library`、`/profile/privacy`
- 仅 Debug：`/ambient-debug`、`/environment-lab`

### 5.3 平台消费者

- 本机通知（Android/iOS 系统通知，前台排程）：**已交付**
- 桌面/锁屏 Widget：**contract-only，未交付**（无原生消费者，见 §3）

## 6. Provider 范围

### 核心/默认链

QWeather、高德、OSM、官方限制/公告，以及区域身份需要的 Wikidata/Wikimedia。

### 按需摄影增强

SunsetBot、DEM、VIIRS、GBIF、iNaturalist。缺失时必须隐藏或独立降级。

### 默认关闭/冻结

Sentinel-1、Sentinel-2、CAMS、AERONET、FIRMS、Copernicus Marine、JPL Horizons、NOAA SWPC、eBird。存在适配器不等于当前产品需要启用。

## 7. Research Gateway

Agent Reach 与 Crawl4AI 不作为新的常驻 Provider 集群。Core 收缩完成后，只允许通过统一 `ResearchGateway` 在以下情况触发：

1. 用户明确要求深入了解/联网核验；
2. Region Brief 某个分区缺少新鲜来源（真实证据缺口），包括服务端低频的证据缺口刷新；
3. AI 回答必须依赖新鲜外部资料；
4. 路线走廊的预到达综合：输入已是确定事实的 corridor 数据，产出一条不超过 80 字的预到达简报，每条路线一次并缓存。

Crawl4AI 负责深读允许的网站；Agent Reach 负责按需跨渠道寻找资料。结果必须先经过 Evidence/来源边界，再进入 Region Brief 或 AI。

## 8. 功能准入门槛

新增 Provider、后台 worker、常驻页面、机会 family、路由生命周期、模型 fallback 或持久化类型前，必须回答：

- 它具体改善五个核心问题中的哪一个？
- 现有能力为什么不能完成？
- 用户在哪里看到/使用结果？
- 上游不可用时是否独立降级？
- 是否增加新的常驻 UI、后台轮询或长期维护面？

如果没有明确答案，不进入当前实现。

提醒类能力不新增常驻一级入口，一律通过既有表面或系统通知送达。

### 8.1 开口许可按证据时间尺度分级

主动性的边界由数据本身的可信时间尺度决定，而不是由模型或供应商的能力决定：

| 证据时间尺度 | 允许的表面 | 允许的表述 |
| --- | --- | --- |
| 未来 2 小时内且证据为权威或交叉验证 | 可占据主视觉、可发系统通知、可抢占 | 可陈述即将成立的窗口与成立条件 |
| 日级/多日 | 仅今日与探索的候选窗口 | 只能陈述成立条件、缺失条件与数据时间；**不可预告，不可通知** |
| 单源、候选或互相冲突 | 仅探索页证据列表 | 明确标注未核验 |

这条分级是产品定位而不是合规负担：同类产品中唯一采用主动推送的，因为把多日概率说过头而失去口碑；数据最严谨的则完全不做提醒。栖光的位置是**只在数据真的准的时间尺度上开口**。服务端必须在生成 entry 时按此派生 `allowedSurfaces`，不得由客户端或模型自行判断能否打扰用户。

## 9. “完成”的定义

一个功能只有同时满足以下条件才算完成：

1. **生产入口已接线**：真实 Router/页面/服务路径正在使用它，不是仓库里存在一个实现文件。
2. **用户可见且可行动**：用户能理解结论，并知道下一步。
3. **没有死工作**：没有无消费者的自动刷新、轮询或库存生成。
4. **边界诚实**：缺数据隐藏；候选不包装成概率；安全只用授权链。
5. **回归验证通过**：相关测试和仓库 CI 通过。

“代码已写”“测试已过”“Provider 已接”都不能单独等同于产品完成。
