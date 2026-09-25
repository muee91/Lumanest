# 栖光 LumaNest 项目功能审计报告

**审计范围**:全部子系统(Flutter 客户端 / Context Service / Data Broker / Discovery Service / 端到端契约)
**审计维度**:功能完整性、代码质量、状态与数据流
**审计日期**:2026-07-21
**审计方式**:静态代码阅读 + 交叉验证,未修改任何代码

---

## 一、总体结论

LumaNest 是一个**架构严谨、契约严格、隐私意识强**的多子系统项目,涵盖 Flutter 客户端、Python 后端服务(Context Service、Discovery Service)、Node.js 数据代理(Data Broker)。整体已具备生产级质量,主要短板集中在**死代码积累**、**可观测性缺失**(后端无日志/无 tracing)、**几处架构断链**(ServerManifest 未接线、catalog 项缺失)。

### 子系统评分总览

| 子系统 | 功能完整性 | 代码质量 | 状态与数据流 | 综合 | 说明 |
|---|---|---|---|---|---|
| **Flutter 客户端** | B+(8.0/10) | B+(8.0/10) | B(7.5/10) | **B+** | 5 个一级页面全部真实实现,但存在 10+ 死代码文件、ServerManifest 断链、AI 长度上限过严、两套色板并存 |
| **Context Service**(Python) | B+(8.5/10) | B(7.5/10) | A-(9.0/10) | **B+** | 9 个端点全部真实实现,迁移链连贯;但 10 处静默异常吞 DB 错、0 日志、catalog 项缺失 |
| **Data Broker**(Node.js) | A-(8.5/10) | B+(8.0/10) | A-(8.5/10) | **B+** | SunsetBot P0 双模型聚合真实落地,熔断/缓存/限流完整;但 `/metrics` 无认证、`clearCache` 空实现、AuditLog 无持久化 |
| **Discovery Service** | A(9.5/10) | A(9.0/10) | A(9.0/10) | **A** | 完整生产级实现,职责清晰分层,SSRF 防护到位 |
| **端到端 API 契约** | A(9.5/10) | A(9.0/10) | A(9.0/10) | **A** | 18 个客户端调用端点 100% 匹配服务端实现,无遗漏 |

**项目综合评分:B+(8.3/10)— 可生产部署,有可改进点**

---

## 二、跨子系统核心发现

### 2.1 高风险问题(跨子系统)

#### H1. `ServerManifest` 端到端断链 [Flutter 客户端 + Context Service]

**现象**:Context Service 的 V5 响应未包含 `manifest` 字段,Flutter 客户端 `_parseV5` 也未解析该字段,导致整套服务端 manifest 域逻辑失效。

**证据链**:
- Context Service `services/lumanest-context-service/app/v5.py` 的 `project_snapshot_v5` 输出中无 `manifest` 键
- Flutter 客户端 `lib/src/infrastructure/context/data_broker_context_repository.dart:406-477` 的 `_v5ResponseKeys` 不含 `manifest`,构造 `ContextSnapshot` 时 `serverManifest` 默认 null
- Flutter 端 `lib/src/core/context/server_manifest.dart`、`lib/src/core/manifest/manifest_policy.dart:38-115` 的 `_buildFromServer` 路径、`lib/src/core/context/persistent_context_cache.dart:773-809` 的编解码全部成为事实死代码

**影响**:服务端无法通过 manifest 表达 `quiet/opportunity/safety` 布局意图,客户端始终走本地兜底的 `_buildLocal` 路径。这是**最严重的架构级断链**。

**建议**:与产品确认 manifest 字段是否为预留能力。若是,在域代码中标注 `reserved for server-side manifest`;若应启用,需在 Context Service v5 输出与客户端解析两端同步接入。

#### H2. AI 问答长度上限过严导致 `/v1/assistant` 形同未接入 [Flutter 客户端 + Data Broker]

**现象**:Flutter 客户端 `lib/src/core/assistant/assistant_model.dart:152-156` 对模型回答长度限制为 `answer.runes.length > 80`,80 个 rune 在中文场景下约 40-80 个汉字,远低于合理上限。

**影响**:任何超过此长度的有效模型回答都会被误判为 `invalidResponse` 并降级到本地模板。用户实际几乎永远看到模板文本,Data Broker 的 `/v1/assistant` 端点(`services/lumanest-data-broker/src/server.mjs:1605`)形同未接入。降级是静默的,QA 难以发现。

**建议**:放宽到 500-2000 rune,或按 `NarrativeTone` 区分(concise 上限 300,balanced 上限 1200)。若为成本控制,应改为后端策略而非客户端硬卡。

#### H3. Context Service 静默异常 + 0 日志导致生产不可观测 [Context Service]

**现象**:`services/lumanest-context-service/app/store.py` 中 10 处 `except Exception: return ...` 静默吞掉 DB 错误,且整个 `app/` 目录 0 条 `import logging`、0 条 `logger.` 调用。

**关键位置**:
- `store.py:76-77` `spatial_evidence` 失败返回空证据
- `store.py:542-543` `active_astronomy_events` 失败返回 `[]`
- `store.py:285-286` `shooting_targets` 失败返回 `[]`

**影响**:生产环境 DB 故障时服务静默降级为"无空间证据 + 无天文事件 + 无拍摄目标"的空快照,客户端无法区分"正常无数据"与"DB 故障"。`/readyz` 仍返回 200,Kubernetes 不会重启 Pod。

**建议**:
1. 在 10 处 `except Exception` 加入 `logger.warning("store_fallback", extra={...})`
2. `/readyz` 在 DB 不可用时返回 503 而非 200

#### H4. `generalMorning`/`generalEvening` catalog 项缺失 [Context Service]

**现象**:`services/lumanest-context-service/app/shooting_sessions.py:409-410` 生成 `kind="generalMorning"`/`"generalEvening"`,`app/v5.py:179-180` 映射为 `session.general.morning`/`session.general.evening`,但 `app/generated/opportunity_catalog.py` 中**没有这两个 ID**(catalog 仅 48 项,`available` 仅 6 项,严格计数)。

**影响**:V5 entry 的 `definitionId` 指向不存在的 catalog 项,客户端可能无法正确解析 opportunity 的 tier/capability 元信息。

**建议**:与产品确认 `generalMorning`/`generalEvening` 是否应有对应 catalog 项。若应补,在 `opportunity_catalog.py` 添加;若不应有,修改 `_session_definition` 映射。

### 2.2 中风险问题(跨子系统)

#### M1. Flutter 客户端死代码积累(~10 个文件,0 生产引用)

**关键死代码清单**:

| 文件 | 性质 | 建议 |
|---|---|---|
| `lib/src/core/state/` 整个目录(5 文件) | 完整的"状态切片+部分刷新+TTL 策略"框架,仅测试引用 | 删除或接入 `LiveEnvironmentController` |
| `lib/src/features/notifications/application/route_reminder_service.dart` | 完整实现 `flutter_local_notifications`,但 0 调用 | 与 P-03 一起决策 |
| `lib/src/shared/widgets/luma_nest_page_header.dart` 等 5 个 shared widget | V1 时代遗留 | 直接删除 |
| `lib/src/features/profile/presentation/local_photography_export.dart`、`lib/src/features/route/application/gpx_track_import_service.dart` | 完整实现但未接入 UI | 标注 `reserved for P1` 或移至 drafts/ |
| `lib/src/shared/actions/manifest_action_handler.dart` + `lib/src/shared/widgets/manifest_event_metadata.dart` | V1 manifest action 路径,V2 已用 `EntryActionDispatcher` 替代 | 删除 |

**影响**:增加维护成本与认知负担,新成员可能误以为这些组件在使用。

#### M2. Flutter `Resilient*Repository` 名不副实 [Flutter 客户端]

**位置**:4 个 Resilient 仓库(`nearby_place`、`wildlife_map_layer`、`driving_route`、`location_search`)。

**现象**:类名叫 `Resilient`,但实际只实现"主失败→读缓存"两步,**无重试、无指数退避、无熔断**。与服务端 `circuit_breaker/` 形成对比。

**影响**:网络抖动一次即降级到缓存,用户看到陈旧数据,无法自动恢复。

**建议**:引入 `RetryPolicy`(最多 1 次重试,200ms 退避),或重命名为 `CachedFallbackRepository`。

#### M3. Data Broker `/metrics` 端点无认证 [Data Broker]

**位置**:`services/lumanest-data-broker/src/server.mjs:1253-1256`。

**影响**:暴露 SunsetBot/7Timer 计数器、p95 延迟、模型分歧度,可被公网探测。

**建议**:为 `/metrics` 添加 Bearer 认证或限制为 LAN-only。

#### M4. Data Broker `clearCache` 空实现 + AuditLog 无持久化 [Data Broker]

- `services/lumanest-data-broker/src/admin/admin-server.mjs:140, 505-509` `clearCache` 回调默认空,`createBrokerServices` 未注入实际实现 → admin 后台"清空缓存"按钮无效
- `services/lumanest-data-broker/src/admin/audit-log.mjs:6` 仅内存 200 条,容器重启丢失,不符合审计日志合规预期

**建议**:`clearCache` 注入实际实现;AuditLog 改为写入文件或 Redis,保留至少 90 天。

#### M5. Flutter 两套色板并存,高对比度主题不生效到 V2 文字色 [Flutter 客户端]

**现象**:
- `lib/src/design/luma_nest_colors.dart` 定义 `LumaNestColors`(primaryLight=#00A5E9、accentLight=#91A86B 等)
- `lib/src/presentation_v2/shared/v2_palette.dart` 定义完全不同的 `V2Palette`(canvas=#F5F5F1、ink=#171A18、moss=#819D4B 等)
- V2 页面大量使用 `Colors.white`/`Colors.black`/`Color(0xFF...)` 硬编码(~83 行)
- `V2Palette` 为静态常量,`preferences.highContrast=true` 时 `V2Palette.ink` 不变

**影响**:无障碍合规风险。WCAG 对比度测试 `test/design/luma_nest_theme_test.dart:140-162` 只覆盖 `LumaNestTheme`,未覆盖 V2 页面实际渲染色。

**建议**:保留 `V2Palette` 作为事实标准,扩展为支持 `Brightness` 与 `highContrast` 的 resolver(`V2Palette.of(context).ink`)。

#### M6. Flutter `shootingSessionNotificationsEnabledProvider` UI 开关缺失 [Flutter 客户端]

**位置**:`lib/src/features/notifications/application/photography_watch_notification_service.dart:380-417`。

**证据**:`grep -rn "shootingSessionNotificationsEnabledProvider" lib/src/presentation_v2/` 返回 0 匹配。

**影响**:服务、ledger、reconciler 完整实现,但用户永远无法启用,整个调用链实际从不调度任何通知。与 README 声明"第一阶段不发送本地通知"一致,但代码层已完整实现,形成"功能完整但被 UI 阻断"的状态。

**建议**:若第一阶段确实不做,删除 `route_reminder_service.dart` 整个文件并在 `photography_watch_notification_service.dart` 标注 reserved;若要做,补齐 UI 开关。

### 2.3 低风险问题(汇总)

| 子系统 | 问题 | 位置 |
|---|---|---|
| Flutter | Hero tag 在 `sessionId==null` 时不匹配 | `lib/src/presentation_v2/shared/v2_opportunity_object.dart:36-54` |
| Flutter | `v2_explore_page.dart` 2180 行单文件,18 个状态字段 | `lib/src/presentation_v2/explore/v2_explore_page.dart` |
| Flutter | `disponse` 拼写(需确认 AMap SDK) | `lib/src/presentation_v2/explore/v2_explore_page.dart:165`、`lib/src/presentation_v2/route/v2_route_page.dart:176` |
| Flutter | `AppDatabase.onUpgrade` 直接 `DROP+createAll`,schemaVersion=16 仍开发期行为 | `lib/src/core/persistence/app_database.dart:388-399` |
| Flutter | 后台刷新失败静默吞错(`configMissing` 场景用户无提示) | `lib/src/core/context/environment_providers.dart:238-250` |
| Context Service | `route_corridor.py` + `PhotographyTarget` 模型死代码 | `services/lumanest-context-service/app/route_corridor.py`、`app/store.py:152-212` |
| Context Service | `rule_versions` 表无代码引用 | `services/lumanest-context-service/alembic/versions/0001_context_foundation.py:48-55` |
| Context Service | Dockerfile 未使用 `uv.lock` | `services/lumanest-context-service/Dockerfile:8` |
| Data Broker | AMap/GBIF/Elevation 缓存使用进程内 Map,多容器不共享 | `services/lumanest-data-broker/src/server.mjs:1065-1068` |
| Data Broker | SunsetBot 负缓存使用 `freshTtl`(90 分钟)过长 | `services/lumanest-data-broker/src/domain/sky_opportunity/sky_opportunity_service.mjs:334-339` |
| Data Broker | `SevenTimerCircuitBreaker` 无滑动窗口 | `services/lumanest-data-broker/src/infrastructure/circuit_breaker/seven_timer_circuit_breaker.mjs` |

---

## 三、端到端契约一致性(优秀)

### 3.1 API 端点契约

**18 个客户端调用端点 100% 匹配服务端实现**,无遗漏、无多余。详见审计子报告对照表(此处仅列代表):

| 客户端调用 | 服务端实现 | 契约状态 |
|---|---|---|
| `/v1/context/snapshot` (POST) | `services/lumanest-data-broker/src/server.mjs:1654` | 匹配 |
| `/v1/sky-opportunities/daily` (GET) | `services/lumanest-data-broker/src/server.mjs:1226` | 匹配 |
| `/v1/companion/refresh` (POST) | `services/lumanest-data-broker/src/server.mjs:1189` | 匹配 |
| `/v1/explore/discover` (POST) | `services/lumanest-data-broker/src/server.mjs:1860` | 匹配 |
| `/v1/assistant` (POST) | `services/lumanest-data-broker/src/server.mjs:1605` | 匹配(但受 H2 限制实际未生效) |

### 3.2 鉴权一致性

三层鉴权在两端完全对齐:
- **App ↔ Data Broker**:共享密钥 Bearer Token,`timingSafeEqual` 防时序攻击
- **Data Broker ↔ Context/Discovery Service**:`X-Internal-Service-Token` Header
- **Discovery Worker ↔ Data Broker**:`X-Discovery-Worker-Token` Header

**说明**:项目不使用 JWT 进行 App 鉴权。JWT 仅用于 Data Broker → QWeather 的 EdDSA 签名,这是合理设计。

### 3.3 数据格式一致性

- 服务端全部使用 camelCase 序列化(Pydantic `Field(alias=...)` + `response_model_by_alias=True`)
- 客户端直接消费 camelCase,无 snake_case 转换层
- 客户端做了严格**键集校验**(如 `_hasExactKeys` 校验 V5 响应必须正好 10 个键),服务端 Pydantic 全部 `extra="forbid"`,两端对等严格

---

## 四、测试覆盖度评估

| 子系统 | 测试数量 | 评估 |
|---|---|---|
| Flutter 客户端 | 117 个测试文件,~540 个 `test()`/`testWidgets()` 调用 | 数量属实(声称 482 项),但 V2 页面单元测试缺失、无覆盖率工具 |
| Context Service | 7 个测试文件,~61 个测试 | 契约/隐私/降级路径覆盖好,但 store 事务/并发测试缺失、迁移仅测 0004 |
| Data Broker | 37 个测试文件,255 个 `test()` 调用 | 数量级与声称 196 项一致,覆盖关键路径,但缺 `/metrics` 未认证、`clearCache` 空实现等边缘场景 |
| Discovery Service | 5 个测试文件,29 个测试 | 覆盖鉴权、契约、缓存、队列、准入、爬虫,质量高 |

**Flutter 测试质量亮点**:
- `test/flutter_test_config.dart` 全局替换 SharedPreferences 与 Drift factory,测试隔离规范
- `test/core/persistence/app_database_test.dart:111` 手工构造旧 SQLite 文件验证迁移,扎实
- `test/design/luma_nest_theme_test.dart` WCAG 对比度断言(≥ 4.5:1 与 ≥ 7:1)
- 隐私测试严格(断言"概率不外露"、HTTPS-only authority URI)

---

## 五、改进建议(按优先级)

### P0(立即处理,影响功能正确性或生产可运维性)

1. **修复 AI 回答长度上限**(H2):放宽 `lib/src/core/assistant/assistant_model.dart:152-156` 的 80 rune 限制
2. **决策 `ServerManifest` 断链**(H1):与服务端确认 v5 响应是否应包含 `manifest` 字段,同步接入或标注 reserved
3. **Context Service 引入结构化日志**(H3):在 10 处 `except Exception` 加入 `logger.warning`,`/readyz` 在 DB 不可用时返回 503
4. **修复 `generalMorning`/`generalEvening` catalog 缺失**(H4):与产品确认设计意图
5. **Data Broker `/metrics` 添加认证**(M3)
6. **Data Broker 实现 `clearCache` 回调**(M4)

### P1(近期处理,影响可维护性或无障碍)

7. **Flutter 清理死代码**(M1):删除 `core/state/` 目录或接入主流程;删除 V1 遗留 widget;标注 reserved 服务
8. **Flutter 统一色板**(M5):`V2Palette` 扩展为支持 highContrast 的 resolver
9. **Flutter 补齐 V2 页面 widget 测试**:每个一级页面至少 5 个用例,覆盖空/loading/error/data + 关键交互
10. **Flutter 接入 `flutter test --coverage`**:CI 设定最低行覆盖率阈值(初始 60%)
11. **Flutter 决策通知 UI 开关**(M6):补齐开关或删除 `route_reminder_service.dart`
12. **Data Broker AuditLog 持久化**(M4)
13. **Flutter `Resilient*Repository` 引入重试策略**(M2)

### P2(中期优化)

14. Flutter:`AppDatabase.onUpgrade` 为 RC 编写数据保留迁移
15. Flutter:抽取 TextStyle/Spacing token,统一 design token 体系
16. Flutter:拆分 `v2_explore_page.dart`(2180 行)
17. Context Service:Dockerfile 改用 `uv pip sync uv.lock`
18. Context Service:`invalidate_snapshot_cache` 改用版本号 key 避免 SCAN
19. Data Broker:AMap/GBIF 缓存迁移到 Redis
20. Data Broker:`SevenTimerCircuitBreaker` 增加滑动窗口

---

## 六、影响范围与验证方法

### 影响范围

本审计为**只读研究性审计**,未修改任何代码。所有发现均基于静态代码阅读 + 交叉验证。审计覆盖:
- Flutter 客户端 `lib/` 全目录(约 42 个关键文件)
- Context Service `app/` + `alembic/versions/` + `tests/` 全部
- Data Broker `src/` 全目录(37 个测试文件)
- Discovery Service 全部源码 + 迁移 + 测试
- 端到端 18 个 API 端点逐项核对

### 验证方法

读者可用以下命令复现关键发现:

```bash
# H1: ServerManifest 未被解析(应返回 0 匹配)
grep -n "serverManifest" lib/src/infrastructure/context/data_broker_context_repository.dart

# H2: AI 长度上限(应返回 80)
grep -n "runes.length > 80" lib/src/core/assistant/assistant_model.dart

# H3: Context Service 0 日志(应返回 0)
grep -rn "import logging\|logger\.\|getLogger" services/lumanest-context-service/app/

# M1: Flutter core/state/ 死代码(应返回 0 个非自身引用)
grep -rln "PartialRefreshController\|EnvironmentState\|ContextDelta" lib/src/ | grep -v "core/state/"

# M6: 通知 UI 开关缺失(应返回 0 匹配)
grep -rn "shootingSessionNotificationsEnabledProvider" lib/src/presentation_v2/

# 端到端契约:18 个端点逐项核对(见子报告)
```

### 风险说明

- 本审计基于静态阅读,**未运行时验证**。`ServerManifest` 是否真的从未被服务端返回、`disponse` 是否为 AMap SDK 自定义方法、`generalMorning`/`generalEvening` 是否为有意缺失,需结合运行时行为或团队确认
- 死代码判定基于当前代码库快照,若后续接入路径已规划但未实现,应保留代码并标注 `reserved`
- Context Service 的 `on Object {}` 静默吞错策略大部分有注释说明降级理由,是有意为之,但建议补齐日志以利于线上诊断
- 测试数量声称(482/196)经核实基本属实,但无覆盖率工具,无法判断分支覆盖度

---

## 七、最终判定

**通过(有条件)**。LumaNest 项目整体架构严谨、契约严格、隐私意识强,已具备生产部署能力。主要风险集中在:

1. **H2(AI 长度上限)** 是最影响用户体验的问题,建议立即修复
2. **H1(ServerManifest 断链)** 与 **H4(catalog 缺失)** 需与产品确认设计意图后决策
3. **H3(Context Service 可观测性)** 是生产可运维性短板,建议在上线前补齐日志
4. **M1(Flutter 死代码)** 与 **M5(色板不统一)** 不影响功能但增加维护成本,建议近期清理

完成 P0 六项后,项目的功能正确性与生产可运维性将显著提升。P1/P2 项可在后续迭代中逐步处理,不阻塞当前部署。

**审计完成。本报告未修改任何代码,所有结论基于对源码、迁移、测试、配置的静态阅读与交叉验证。**

---

## 附录:各子系统详细审计子报告索引

本次审计由 6 个并行子代理完成,详细子报告内容如下(如需查阅完整子报告,可重新运行审计或联系审计人):

1. **Flutter Presentation V2 层审计** — 5 个一级页面 + Shell + Router + AI 问答页逐项核查
2. **Flutter 核心能力与领域层审计** — core/ 与 features/ 的 Provider/Repository/Service 状态流分析
3. **Flutter 测试覆盖与代码质量扫描** — 117 个测试文件评估 + 死代码扫描 + 设计一致性核查
4. **Context Service(Python)审计** — 9 个端点 + 迁移链 + 规则引擎 + shooting_sessions 一致性
5. **Data Broker(Node.js)审计** — 31 个端点 + Provider/LLM/缓存/熔断/限流评估
6. **Discovery Service + 端到端契约审计** — Discovery 实现度 + 18 个 API 端点契约对照
