# 栖光 LumaNest 最终工程规格书

**文档版本：** 1.1
**基准源码：** `LumaNest-source-20260718-043432(1).zip`，仓库根目录为 `on-the-way/`  
**参考审计：** `calLog_analysis.zip` 中 `技术栈分析报告.md`、二进制符号与资源清单  
**目标平台：** Flutter iOS + Android  
**唯一产品人格：** 栖光

---

## 0. 规格书地位与一致性数字

本文件是产品行为、UI/UX、数据契约和工程实现的事实源。代码中的同类常量不得在页面、Dart、Python、Node 三处分别维护。

一致性数字：

- 摄影机会目录：**48 项**
- `core`：**16 项**，其中 `available=6`、`degraded=7`、`unavailable=3`
- `legacyOnly`：**3 项**
- `reserved`：**29 项**
- 时间策略：**16 套**
- 标准标签：**96 个**
- 内置创作提示：**48 条**
- 主场景：**10 个**
- 场景特征：**24 个**
- 活动状态：**4 个**
- 后台职能智能体：**8 个**
- Insight 通道：**9 个**
- 灵感瓶候选池上限：**120 条**
- 当前库存：**20–60 条，目标 36 条**
- 同时参与物理模拟：**18 张纸条**
- UI Golden 基准状态：**15 个**

### 0.1 开发阶段发布与兼容性规则

当前产品处于**仅开发者本人使用的内部开发阶段**，不是公测或正式发布。
在产品负责人明确说出“**开始公测**”之前，以下规则为强制约束：

- App、Broker、Context 与 Discovery 只维护**一个当前契约**；接口、DTO、缓存或运行设置发生破坏性调整时，直接删除被替代字段、默认值和降级分支，不保留旧客户端/API 兼容层。
- 禁止为“可能存在的旧版本”添加双读双写、旧字段透传、旧参数默认值、协议探测回退、影子端点或静默容错。收到旧契约时必须明确拒绝，或将该可选创作能力诚实隐藏，不能伪造可用结果。
- NAS 发布必须把相互依赖的服务与当前 App 构建视为同一 release 验收对象；先切换 Broker/服务端，再用真实 API 校验当前契约，最后交付当前 App 构建。不得声明或维持新旧混用状态。
- 未实现、未审核或不具备真实数据支撑的功能必须保持关闭/隐藏；Feature Flag 不能被用于暴露旧实现或占位能力。
- 只有产品负责人明确宣布“开始公测”后，才可为已安装测试版本设计兼容窗口；届时必须另行记录受影响版本、兼容期限、迁移/回滚方案和删除日期。没有这四项记录即不得实现兼容代码。

本规格书中的 `legacyOnly` 仅是历史目录数据的受控迁移分类，不构成对旧 App、旧 API 或旧展示层的兼容授权。

---

# 第一部分：产品与体验事实

## 1. 产品定义

栖光是环境感知型旅行摄影智能体。它持续处理位置、天气、光线、天象、地理场景、活动状态、路线、附近公开网络信息和用户偏好，并将结果组织为可行动的摄影机会、地点发现、人文线索、路线陪伴和创作灵感。

前台只呈现一个人格“栖光”。后台智能体不得成为独立聊天入口或独立 Tab。

### 1.1 五个一级页面

| 页面 | 唯一职责 | 首屏上限 |
|---|---|---|
| 今日 | 现在最值得做什么 | 1 个主行动、2 个次级机会、1 条搭子跟进 |
| 探索 | 附近和目的地还有什么值得去 | 地图、1 个搜索意图、紧凑结果面板 |
| 路线 | 怎么去、能否赶上、沿途注意什么 | 地图、核心指标、下一件事、1 个主行动 |
| 灵感 | 持续发现地点、人文、创作、生活和记忆线索 | 玻璃瓶与当前抽出的 1 张纸条 |
| 我的 | 栖光怎样理解用户以及留下了什么 | 5 个控制中心入口 |

### 1.2 跨页面稳定标识

所有页面传递同一组稳定 ID：

```text
insightId
opportunityInstanceId
sessionId
targetId
routeId
searchMissionId
```

禁止页面间通过地点名称、标题或临时序号重新匹配对象。

### 1.3 标准行动闭环

```text
今日发现机会/线索
→ 容器展开查看依据
→ 探索定位目标
→ 路线计算是否赶得上
→ 进入守候或行动会话
→ 提交拍摄结果
→ 写入记忆和收藏
```

---

## 2. UI/UX 北极星

参考项目的迁移对象是交互编舞，不是饮食业务、品牌资产、字体或视频背景。

优先级从高到低：

1. 容器连续形变高于页面跳转。
2. 直接操控高于设置菜单。
3. 单一视觉焦点高于模块堆叠。
4. 自然语言结论高于数据仪表。
5. 低幅度、高密度反馈高于大型装饰动画。
6. 当前内容立即可用，AI 与联网结果渐进增强。
7. 动态天气背景只提供氛围，不成为视觉主角。
8. 所有声音、触觉和动画必须表达状态语义。

明确不采用：

- `01.mp4`–`13.mp4`、`gem.mp4`、`waterWave.mp4`、`window.mp4` 作为背景；
- 参考 App 的字体文件、品牌图标或页面资产；
- 大量默认 Material 卡片、InkSparkle 和整页圆形 Loading；
- 每页独立重算同一机会；
- 页面切换时重启动态背景或丢失地图视角。

---

# 第二部分：现有工程锚点

## 3. 保留技术栈

当前 `pubspec.yaml` 已确认：Dart `^3.12.1`、Riverpod `3.3.2`、GoRouter `17.3.0`、Drift `2.34.1`、Dio `5.10.0`、高德地图、Geolocator、Sentry、Fragment Shader 等。继续使用，不替换核心框架。

服务端继续使用：

- `services/lumanest-context-service`：环境事实、摄影机会、拍摄会话、安全和反馈校准；
- `services/lumanest-data-broker`：客户端网关、JWT、限流、天气/地图代理、Tavily、LLM 路由；
- `services/lumanest-discovery-service`：联网证据落库、候选地点和活动归一化；
- `services/qweather-token-broker`：现有天气令牌能力。

### 3.1 现有公开端点兼容表

| 现有端点 | 处理方式 |
|---|---|
| `POST /v1/context/snapshot` | 保留；升级返回 `sceneContext`、机会目录版本和 Core 机会实例 |
| `POST /v1/context/target-session` | 保留；支持 8 种 Shooting Session |
| `POST /v1/context/shooting-feedback` | 保留；扩展结果类型与标签学习 |
| `POST /v1/context/safety-detail` | 保留；安全事实不经 LLM 改写 |
| `POST /v1/route/weather` | 保留；Route Agent 使用 |
| `POST /v1/explore/discover` | 保留并扩展 `missionType`；不再新增重复的 Search Mission 执行端点 |
| `POST /v1/narrative` | 保留；只负责已选事实的自然语言表达 |
| `GET /v1/amap/nearby` | 保留；POI 与生活补给 |
| `GET /v1/amap/search` | 保留；结构化地点搜索 |
| `GET /v1/amap/scene-evidence` | 保留；场景分类证据 |
| `GET /v1/amap/driving`、`/walking` | 保留；路线计算 |
| `GET /v1/elevation/profile` | 保留；高程显示，不等同 DEM 坡向/通视 |
| `GET /v1/wildlife/nearby`、`/layers` | 保留；区域生态机会与安全分流 |

新增端点只允许三个：

| 新端点 | 用途 |
|---|---|
| `POST /v1/companion/refresh` | 总控刷新；聚合当前快照、搜索任务和可见 Insight |
| `GET /v1/inspiration/inventory` | 返回 20–60 条持久化灵感库存 |
| `POST /v1/insights/:id/feedback` | 记录查看、收藏、路线、完成、不感兴趣等行为 |

---

## 4. 当前代码必须修复的锚点

- `lib/src/app/router.dart`：5 个分支当前使用 `NoTransitionPage`。
- `lib/src/app/app_shell.dart`：当前为 `StatelessWidget`，底部导航使用 `InkWell`，Blur Sigma 为 18。
- `lib/src/features/today/presentation/today_page.dart`：接收 `narrativeAsync` 但未用于主体；存在湖岸硬编码、`IntrinsicHeight` 和整页 `CircularProgressIndicator`。
- `lib/src/core/context/context_snapshot.dart`：`SceneType` 把 `driving`、`hiking` 当场景。
- `lib/src/core/context/context_rule_engine.dart`：统一 `Duration(minutes: 15)`；旧事件 ID 分散。
- `lib/src/core/photography/photography_opportunity.dart`：7 个混合维度枚举只保留为兼容解码。
- `lib/src/core/photography/shooting_session.dart`：仅有 2 种水域会话。
- `ambient_shader_surface.dart`、`ambient_canvas.dart`：Shader 创建、降水重绘、重复暖光/云层和状态插值问题。
- Explore、Route、Profile、Today、Shooting Window 大文件拆分为 Page + Section + 通用组件。

---

# 第三部分：视觉、动效、声音与导航

## 5. 设计令牌

### 5.1 颜色

浅色基准：

```text
页面背景 #F6F6F5
主文字 #25292D
次文字 #626B73
三级文字 #8B949C
主操作蓝 #00A5E9
成功绿 #91A86B
暖光橙 #FF8754
警示红 #ED6C72
```

深色基准：

```text
页面背景 #12161A
主文字 #F5F7F8
次文字 #B6C0C7
三级文字 #86919A
主操作蓝 #37B5EA
成功绿 #A6BB7D
暖光橙 #FF956A
警示红 #FF858A
```

动态环境颜色只能影响氛围层；文字和按钮颜色必须由可读性主题决定。

### 5.2 间距、圆角和字号

```text
间距：4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 48
页面左右边距：<390dp 使用20；≥390dp 使用24
圆角：标签12、图标14、输入16、按钮18、普通卡22、主容器28、Sheet顶部30、导航24
字号：主判断30、主机会23、分区18、次标题16、正文15、辅助13、标签12
```

主容器阴影：Y=10、Blur=30、Opacity=0.08。普通容器：Y=6、Blur=18、Opacity=0.06。

ZcoolXiaoWei 只用于品牌标题、纸条和少量旅行记忆标题，不用于正文、路线、安全和数据。

### 5.3 BackdropFilter 统一规则

- 长期存在的大面积模糊最多 **1 层**：底部导航，Sigma=12。
- 临时 Sheet 展开时允许第 **2 层**。
- 普通列表卡片不使用真实 BackdropFilter，只使用半透明实色。

---

## 6. Motion 与直接操控

固定时长：

```text
pressIn 80ms
pressOut 190ms
iconFeedback 160ms
tabTransition 200ms
contentExit 160ms
contentEnter 280ms
bottomSheet 360ms
containerTransform 420ms
environmentChange 1600ms
```

固定曲线：

```dart
standard = Curves.easeOutCubic
exit = Curves.easeInCubic
emphasized = Cubic(0.20, 0.80, 0.20, 1.00)
```

主卡按下：`1.000 → 0.975`，阴影透明度减少 30%，Y 减少 40%。释放：`0.975 → 1.015 → 0.998 → 1.000`。

内容进入：Opacity `0→1`、Y `8→0`、280ms；Stagger 40ms。数字更新采用旧数字上移 4px、新数字从下方 4px 进入，220ms。

### 6.1 稳定 Morph ID

```text
opportunity:{opportunityInstanceId}
insight:{insightId}
place:{targetId}
session:{sessionId}
route:{routeId}
```

### 6.2 Navigator 结构

在 `router.dart` 增加：

```dart
final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();
```

详情路由挂到 Root Navigator：

```text
/opportunity/:id
/insight/:id
/place/:id
/session/:id
/route-detail/:id
```

同分支使用 Hero；跨 Tab 先在 Root Overlay 完成 Morph，再切换 `navigationShell.goBranch()`。不得依赖跨 Navigator 自动 Hero。

---

## 7. 音频与触觉契约

来源目录：

```text
calLog_analysis/extracted_resources/audio/
```

| 文件 | 原格式 | 时长 | SHA-256 | 用途 |
|---|---|---|---|---|
| click.wav | PCM s16le / 44.1kHz / Stereo | 31.814ms | 2c8efd09836415bc6646ab8c8a39b8251746b51e249ca5cebb8fc92b7f5a9d38 | 普通点击与主行动点击共用样本；靠触觉强度区分 |
| liveButton.wav | 与 click.wav 字节完全相同 | 31.814ms | 2c8efd09836415bc6646ab8c8a39b8251746b51e249ca5cebb8fc92b7f5a9d38 | 不重复打包；作为来源校验项 |
| changeCard.wav | PCM s24le / 44.1kHz / Stereo | 38.889ms | 731df109354fc739fdc9d19a24fcaf4bb857c56ae69ab448666a4244e6b568b3 | 切换卡片/Tab；运行副本转换为16-bit |
| ding.wav | PCM s16le / 44.1kHz / Stereo | 211.406ms | a2214091f16dd20c8a207ffc9b859779f6cc26290660662f0abc49739d6251dd | 确认成功 |
| paper.wav | PCM s16le / 44.1kHz / Stereo | 893.651ms | 4a552c097bf1b680b024505510d2ecadd8a641ecb600107524cb99292980ef40 | 抽取与展开纸条 |
| sec.mp3 | MP3 / 44.1kHz / Stereo | 1.044875s | c8f662d5c97e3e85559b47819b9a26dc7c84c0b80694a3b1aea9f92c1fdb21d4 | 拍摄会话完成仪式 |

`click.wav` 与 `liveButton.wav` 字节相同，因此运行时只打包一个 `click.wav`。主行动与普通点击通过音量和触觉区分，不把同一样本声称为两种听觉语义。

`changeCard.wav` 在导入时转换为 16-bit 运行副本：

```bash
ffmpeg -y -i changeCard.wav -ar 44100 -ac 2 -c:a pcm_s16le change_card.wav
```

资源布局：

```text
assets/audio/source/   # 保留用户提供的原始文件与SHA校验
assets/audio/runtime/  # click.wav、change_card.wav、ding.wav、paper.wav、sec.mp3
```

正式发行前由项目方确认素材授权；代码与资源位不因此改变。

### 7.1 事件映射

| 事件 | 音频 | 音量 | 触觉 |
|---|---|---:|---|
| 普通图标、筛选、证据展开 | `click.wav` | 0.22 | selection |
| 主行动、开始守候、创建路线、抽瓶按钮 | `click.wav` | 0.30 | lightImpact |
| Tab、候选、驾车/徒步切换 | `change_card.wav` | 0.20 | selection |
| 纸条离开瓶口前80ms | `paper.wav` | 0.26 | lightImpact |
| 收藏/路线/反馈成功 | `ding.wav` | 0.30 | success |
| 会话完成、保存光迹 | `sec.mp3` | 0.34 | medium@0ms、light@420ms、success@end |
| 安全警告 | 不使用上述奖励音 | — | warning/error |

### 7.2 原生通道

MethodChannel：`com.lumanest/feedback`

方法：

```text
preload {sounds:[...]}
play {sound, volume}
stop {sound}
setEnabled {soundEnabled, hapticEnabled, completionEnabled}
dispose
```

iOS Audio Session：`ambient`、尊重静音开关、`mixWithOthers=true`。Android AudioAttributes：`USAGE_ASSISTANCE_SONIFICATION`、`CONTENT_TYPE_SONIFICATION`。Android 使用 SoundPool；iOS 使用预加载 AVAudioPlayer/系统触觉。

---

## 8. 动态环境背景

不使用任何预录视频。继续四级降级：Shader、CustomPainter、Animated Gradient、静态渐变。

必须修复：

- FragmentShader 在 Program 加载后创建一次并缓存；
- 降水 Painter 使用 `repaint: animation`；
- Shader 模式不再重复叠加云层与暖光 Overlay；
- `AmbientVisualStateTween` 插值颜色、云量、暖光、降水、饱和度、亮度、运动强度；
- 风向使用最短角路径；
- 普通变化 1600ms、降水进入 800ms、退出 1200ms；
- 后台和减少动态时进入 Level 0。

---

# 第四部分：页面状态机与15个视觉基准

## 9. 页面状态机

### 9.1 Today

```dart
enum TodayViewState {
  initialLoading,
  readyEmpty,
  readyOpportunity,
  readySession,
  scouting,
  stale,
  offline,
  safetyOverride,
  error,
}
```

优先级：`safetyOverride > offline/stale > readySession > readyOpportunity > scouting > readyEmpty`。

### 9.2 Explore

```dart
enum ExploreViewState {
  mapIdle,
  searching,
  showingResults,
  placeSelected,
  sheetExpanded,
  error,
}
```

### 9.3 Route

```dart
enum RouteViewState {
  empty,
  calculating,
  ready,
  recalculating,
  active,
  paused,
  completed,
  error,
}
```

### 9.4 Inspiration

```dart
enum InspirationBottleState {
  loading,
  idle,
  pressing,
  gathering,
  lifting,
  opening,
  opened,
  returning,
  refilling,
  error,
}
```

禁止使用多个互相矛盾的布尔状态替代上述状态机。


### 9.5 Profile

```dart
enum ProfileViewState {
  ready,
  learningDetails,
  preferences,
  displayFeedback,
  privacyData,
  collections,
  error,
}
```

### 9.6 Shooting Window

```dart
enum ShootingWindowViewState {
  loading,
  observeOnly,
  preparing,
  departNow,
  enRoute,
  waitAtTarget,
  shootNow,
  ended,
  safetyOverride,
  error,
}
```

安全状态具有最高优先级，并立即覆盖非安全主行动。


---

## 10. 15个 Golden 视觉状态

基准画布：iOS `390×844`；Android `360×800`。内容按安全区自适应，不按整屏比例缩放。Golden 名称固定：

- `Today/empty`
- `Today/opportunity`
- `Today/session`
- `Today/scouting`
- `Today/safety`
- `Explore/default`
- `Explore/place-selected`
- `Explore/sheet-expanded`
- `Route/summary`
- `Route/mid-sheet`
- `Route/full-sheet`
- `Inspiration/bottle-idle`
- `Inspiration/slip-lifting`
- `Inspiration/slip-detail`
- `Profile/control-center`

### 10.1 Today 五态

- **empty**：顶部地点行 44px；主判断位于 y≈92；不显示大空卡，只显示 1 条搭子句和 1 个探索按钮。
- **opportunity**：主判断 y≈88；主机会卡 y≈160、高 250–280；证据摘要 3 条以内；2 个次级入口使用 92px 小卡。
- **session**：主卡高 300–330，含 4–5 阶段横向时间轴；当前阶段高亮，未来阶段降透明度。
- **scouting**：保留现有内容，仅在主判断下加入 36px 侦察状态条；不得遮罩全屏。
- **safety**：背景饱和度降低；顶部红色安全容器；主行动只允许查看安全详情或结束会话。

### 10.2 Explore 三态

- **default**：52px 搜索栏；地图充满内容区；底部 Sheet 22%；同时最多 1 个 Banner。
- **place-selected**：Marker 放大 1.14；地点详情从 Marker 方向 Morph；地图仍占至少 55% 高度。
- **sheet-expanded**：Sheet 88%；搜索栏收缩为 44px；结果卡显示来源和更新时间。

### 10.3 Route 三态

- **summary**：地图占内容区约 62%；Sheet 26%；仅显示距离、ETA、窗口剩余、下一件事。
- **mid-sheet**：Sheet 55%；显示摄影时间轴、天气、补给和返程风险。
- **full-sheet**：Sheet 90%；显示道路步骤、高程和证据；地图保留顶部窄条，不完全消失。

### 10.4 Inspiration 三态

- **bottle-idle**：瓶宽 72%、高 280px；真实物理纸条 18 张；当前库存数字不直接展示。
- **slip-lifting**：瓶体缩至 0.97；纸条向瓶口聚拢；目标纸条从原位置抬升；`paper.wav` 在离口前80ms开始。
- **slip-detail**：纸条 Morph 成 22px 圆角详情；显示短词、一句解释、来源/动作；背景瓶子保留低透明轮廓。

### 10.5 Profile

- **control-center**：首屏只有“栖光如何理解我、摄影偏好、显示声音动态、隐私本机数据、我的收藏”5 个入口；不展开收藏内容。

---

# 第五部分：场景、证据与摄影机会


## 10.6 领域枚举与稳定 ID

以下枚举为完整集合，页面和服务端不得自行新增自由字符串。

```dart
enum OpportunityModelType { shootingSession, factualEvent }
enum OpportunityFamily { water, mountain, city, landform, atmosphere, astronomy, ecology, humanityRoute }

enum ContextAction {
  openShootingWindow,
  openExplore,
  openRoute,
  openPlaceDetail,
  openAstronomyDetail,
  openWildlifeDetail,
  openSafetyDetail,
  openCreativeDetail,
  dismiss,
}

enum PhotographyPreferenceId {
  mountainLandform,
  waterCoast,
  cityArchitecture,
  humanityStreet,
  astroCelestial,
  wildlifeEcology,
  forestDetail,
  aerialSpatial,
}
```

标准安全冲突 ID 共 12 个：

```text
thunderstorm
strong-wind
heavy-rain
low-visibility
road-stop-unsafe
trail-return-risk
official-closure
wildlife-safety
dust-hazard
flash-flood
unsafe-solar-viewing
no-fly-zone
```

`Safety Guardian` 可以产生其他结构化安全事件，但只有上述 ID 可被 Opportunity Catalog 的 `safetyConflicts` 引用。

拍摄会话固定 8 种：

```dart
enum ShootingSessionKind {
  waterMorning,
  waterEvening,
  mountainMorning,
  mountainEvening,
  cityBlueHour,
  cityAfterRain,
  desertSideLight,
  routeLightWindow,
}
```

会话阶段固定 18 种：

```dart
enum ShootingPhaseKind {
  morningBlueHour,
  sunrise,
  morningMist,
  reflection,
  warmLight,
  sunset,
  blueHour,
  artificialLights,
  rainEnding,
  wetReflection,
  desertSideLight,
  texture,
  approach,
  safeStop,
  shoot,
  rejoinRoute,
  returnWindow,
  sessionEnd,
}
```

`GeoScope` 是机会实例字段，不是目录常量，按以下顺序计算：

1. `session.route.light_window` 固定为 `route`；
2. 有审核坐标或目标坐标时为 `point`；
3. 野生动物、气象大范围和无精确坐标的联网线索为 `region`；
4. 不允许根据标题或 LLM 文本猜测坐标。


## 11. 复合场景模型

主场景 10 个：

```text
unknown, urban, village, mountain, plateau, desert, forest, inlandWater, coast, wetland
```

场景特征 24 个：

```text
lake, river, reservoir, wetland, coast, tidalFlat, waterfall,
snowCover, glacier, canyon, dune, grassland, forest, bambooForest,
skyline, architecture, oldTown, villageStreet, openRoad, openHorizon,
darkSky, reviewedPeak, reviewedViewpoint, reflectiveSurface
```

活动状态 4 个：`stationary, walking, hiking, driving`。路线状态继续使用 `none, planned, active, paused`。活动状态不得覆盖主场景。

### 11.1 主场景评分

```text
人工审核覆盖 100
mountain 60
coast 60
wetland 60
desert 60
plateau 55
forest 55
lake/reservoir 55
village 50
urban 45
river 35
```

同分优先：`mountain > coast > wetland > inlandWater > plateau > desert > forest > village > urban > unknown`。所有命中的 SceneFacet 保留。

---

## 12. 证据能力矩阵

| Evidence | 当前责任方 | 当前状态 | 缺失行为 |
|---|---|---|---|
| light | Context solar | available | 不生成光线会话 |
| weather | QWeather/Broker | available | 不生成天气相关机会 |
| precipitation | QWeather/Broker | available | 雨后模型不能判断 |
| wind | QWeather/Broker | available | 倒影/荒漠模型不生成 |
| visibility | QWeather/Broker | available | 降级或淘汰 |
| astronomy | Context 天文计算/目录 | available | 天文机会不生成 |
| authority | Context 审核目录 | available | 权威事件不生成 |
| place | AMap + 审核目标 | available | 不生成地点承诺 |
| route | AMap route | available | 路线机会不生成 |
| equipment | 用户本地配置 | available | 调整动作，不创造事实 |
| cloudLayers | 未连接高中低云 | unavailable | 晚霞仅 degraded |
| directionalRain | 未连接方向性降水 | unavailable | 彩虹 unavailable |
| humidityDewPoint | 未连接完整湿度/露点 | unavailable | 晨雾 degraded |
| moonTrajectory | 当前仅部分月相 | degraded | 月窗口 degraded |
| terrain | 现有 elevation 非 DEM 坡向 | unavailable | 禁止“日照金山”承诺 |
| lineOfSight | 无通视计算 | unavailable | 禁止精确山体对位 |
| legalStop | 无完整合法停靠库 | unavailable | 沿途光窗 degraded |
| tide | 无潮汐源 | unavailable | 海岸潮汐 reserved |
| lightPollution | 无光污染源 | unavailable | 银河 unavailable |
| snowCover | 无降雪历史/地表积雪 | unavailable | 雪后 unavailable |
| ecology | GBIF历史信号/审核源 | degraded | 只给区域级信号 |

联网文章和 LLM 不得补齐天气、安全、地形、通视、合法停车或光污染事实。

---

## 13. 目录生命周期与能力状态

```dart
enum CatalogTier { core, legacyOnly, reserved }
enum CoreCapabilityState { available, degraded, unavailable }
```

`CoreCapabilityState` 只适用于 `core`。`legacyOnly` 仅解码旧数据，不允许本地主动生成。`reserved` 只登记完整字段，不进入排序、Today 或灵感瓶。

### 13.1 单一事实源

使用标准库可解析的 JSON，不新增 YAML 解析依赖：

```text
catalog/opportunities.v1.json
catalog/timing-policies.v1.json
catalog/tags.v1.json
catalog/creative-prompts.v1.json
catalog/schema/*.schema.json
```

生成器：

```text
tool/generate_catalog.py
```

命令：

```bash
python3 tool/generate_catalog.py
python3 tool/generate_catalog.py --check
```

输出：

```text
lib/src/generated/opportunity_catalog.g.dart
services/lumanest-context-service/app/generated/opportunity_catalog.py
services/lumanest-data-broker/src/generated/opportunity-catalog.mjs
```

CI 必须执行 `--check`。

### 13.2 Opportunity JSON Schema 核心字段

```json
{
  "id": "session.water.evening",
  "catalogTier": "core",
  "coreCapability": "available",
  "modelType": "shootingSession",
  "family": "water",
  "presentation": {
    "zhCN": {
      "name": "湖岸晚间会话",
      "shortLabel": "湖岸晚光",
      "fallbackSummary": "风和光线正在形成湖岸晚间拍摄窗口",
      "emoji": "🌇"
    }
  },
  "primaryScenes": ["inlandWater", "wetland", "coast"],
  "sceneFacets": ["lake", "reservoir", "reflectiveSurface"],
  "requiredEvidence": ["place", "light", "weather", "wind"],
  "optionalEvidence": ["cloudLayers", "visibility"],
  "timingPolicy": "timing.waterEvening",
  "primaryAction": "openShootingWindow",
  "fallbackAction": "openExplore",
  "minimumConfidence": 0.65,
  "dedupeGroup": "water-evening",
  "suppresses": ["event.water.reflection"],
  "safetyConflicts": ["thunderstorm", "strong-wind", "heavy-rain"],
  "preferenceAffinities": ["waterCoast"]
}
```

---

## 14. 48项摄影机会完整目录

字段分隔符 `|` 表示数组。`—` 表示该 Tier 不激活，不是待 Codex 决策。

| ID | 名称 | 短词 | Emoji | Tier | Core能力 | 类型 | 家族 | 主场景 | Facets | 必需证据 | 可选证据 | 时间策略 | 主动作 | 回退 | 最低可信 | 去重组 | 安全冲突 | 偏好 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| session.water.morning | 湖岸晨光会话 | 晨光临水 | 🌅 | core | available | shootingSession | water | inlandWater|wetland|coast | lake|river|reservoir|wetland|coast|reflectiveSurface|reviewedViewpoint | place|light|weather|wind | cloudLayers|visibility|terrain|lineOfSight | timing.waterMorning | openShootingWindow | openExplore | 0.65 | water-morning | thunderstorm|strong-wind|heavy-rain|official-closure | waterCoast |
| session.water.evening | 湖岸晚间会话 | 湖岸晚光 | 🌇 | core | available | shootingSession | water | inlandWater|wetland|coast | lake|river|reservoir|wetland|coast|reflectiveSurface|reviewedViewpoint | place|light|weather|wind | cloudLayers|visibility|terrain|lineOfSight | timing.waterEvening | openShootingWindow | openExplore | 0.65 | water-evening | thunderstorm|strong-wind|heavy-rain|official-closure | waterCoast |
| event.water.reflection | 独立倒影窗口 | 去看倒影 | 🪞 | legacyOnly | 不激活 | factualEvent | water | inlandWater|wetland|coast | lake|river|reservoir|wetland|coast|reflectiveSurface | place|weather|wind | light|visibility | — | openShootingWindow | openExplore | — | water-reflection | strong-wind|heavy-rain|thunderstorm | waterCoast |
| event.water.long_exposure | 水域长曝光窗口 | 让水变慢 | 〰️ | reserved | 不激活 | factualEvent | water | inlandWater|coast|wetland | river|waterfall|coast|reflectiveSurface | place|weather|wind|legalStop | light|tide | — | openShootingWindow | openExplore | — | water-long-exposure | strong-wind|heavy-rain|official-closure | waterCoast |
| session.coast.golden_hour | 海岸黄金时段会话 | 海岸金光 | 🌊 | reserved | 不激活 | shootingSession | water | coast | coast|tidalFlat|openHorizon|reviewedViewpoint | place|light|weather|tide | wind|cloudLayers|legalStop | — | openShootingWindow | openExplore | — | coast-golden | thunderstorm|strong-wind|heavy-rain|official-closure | waterCoast |
| event.coast.tide | 海岸潮汐窗口 | 潮水正好 | 🌊 | reserved | 不激活 | factualEvent | water | coast|wetland | coast|tidalFlat | place|tide|weather | wind|light|legalStop | — | openShootingWindow | openExplore | — | coast-tide | thunderstorm|strong-wind|official-closure | waterCoast |
| session.mountain.morning | 山地晨光会话 | 山要亮了 | ⛰️ | core | degraded | shootingSession | mountain | mountain|plateau | snowCover|glacier|canyon|reviewedPeak|reviewedViewpoint|openHorizon | place|light|weather|visibility | terrain|lineOfSight|cloudLayers | timing.mountainMorning | openShootingWindow | openExplore | 0.65 | mountain-morning | thunderstorm|strong-wind|heavy-rain|low-visibility|trail-return-risk|official-closure | mountainLandform |
| session.mountain.evening | 山地晚光会话 | 晚光上山 | 🏔️ | core | degraded | shootingSession | mountain | mountain|plateau | snowCover|glacier|canyon|reviewedPeak|reviewedViewpoint|openHorizon | place|light|weather|visibility | terrain|lineOfSight|cloudLayers|route | timing.mountainEvening | openShootingWindow | openExplore | 0.65 | mountain-evening | thunderstorm|strong-wind|heavy-rain|low-visibility|trail-return-risk|official-closure | mountainLandform |
| event.mountain.alpenglow_verified | 已验证山体金山 | 山峰要亮 | 🏔️ | reserved | 不激活 | factualEvent | mountain | mountain|plateau | reviewedPeak|reviewedViewpoint|snowCover|openHorizon | place|light|weather|terrain|lineOfSight | cloudLayers|visibility | — | openShootingWindow | openExplore | — | mountain-alpenglow | thunderstorm|strong-wind|low-visibility|official-closure | mountainLandform |
| event.mountain.cloud_sea | 山地云海 | 云海候选 | ☁️ | reserved | 不激活 | factualEvent | mountain | mountain|plateau | canyon|reviewedViewpoint|openHorizon | place|weather|cloudLayers|humidityDewPoint|terrain | visibility|wind | — | openShootingWindow | openExplore | — | mountain-cloud-sea | thunderstorm|strong-wind|low-visibility|trail-return-risk | mountainLandform |
| event.mountain.post_snow_light | 雪后光影 | 雪后见光 | ❄️ | core | unavailable | factualEvent | mountain | mountain|plateau|forest | snowCover|reviewedPeak|reviewedViewpoint | place|weather|precipitation|light|snowCover | cloudLayers|visibility | timing.postSnow | openShootingWindow | openExplore | 0.72 | mountain-post-snow | strong-wind|heavy-rain|low-visibility|official-closure | mountainLandform |
| event.mountain.moon_alignment | 山峰月出对位 | 月上山峰 | 🌕 | reserved | 不激活 | factualEvent | mountain | mountain|plateau | reviewedPeak|reviewedViewpoint|openHorizon | place|moonTrajectory|terrain|lineOfSight|weather | light|route | — | openShootingWindow | openExplore | — | mountain-moon-alignment | low-visibility|official-closure|trail-return-risk | mountainLandform|astroCelestial |
| session.city.blue_hour | 城市蓝调会话 | 蓝调将至 | 🌆 | core | available | shootingSession | city | urban | skyline|architecture|oldTown|river|reflectiveSurface|reviewedViewpoint | place|light|weather|visibility | cloudLayers|route | timing.cityBlue | openShootingWindow | openExplore | 0.68 | city-blue | heavy-rain|official-closure | cityArchitecture |
| session.city.after_rain | 雨后城市会话 | 雨后有光 | 🌧️ | core | degraded | shootingSession | city | urban | skyline|architecture|oldTown|river|reflectiveSurface | place|weather|precipitation|light | cloudLayers|visibility|route | timing.cityAfterRain | openShootingWindow | openExplore | 0.70 | city-after-rain | thunderstorm|heavy-rain|official-closure | cityArchitecture|humanityStreet |
| event.city.sunrise_geometry | 城市日出几何 | 日光穿城 | 🌇 | reserved | 不激活 | factualEvent | city | urban | skyline|architecture|oldTown|reviewedViewpoint | place|light|terrain|lineOfSight|weather | cloudLayers|route | — | openShootingWindow | openExplore | — | city-sunrise | heavy-rain|official-closure | cityArchitecture |
| event.city.sunset_skyline | 天际线日落 | 天际线晚霞 | 🌇 | reserved | 不激活 | factualEvent | city | urban | skyline|architecture|reviewedViewpoint|openHorizon | place|light|weather|cloudLayers | visibility|route | — | openShootingWindow | openExplore | — | city-sunset | heavy-rain|official-closure | cityArchitecture |
| event.city.light_trails | 城市车流光轨 | 车流亮了 | 🚗 | reserved | 不激活 | factualEvent | city | urban | architecture|skyline|openRoad|reviewedViewpoint | place|light|weather|legalStop | route|visibility | — | openShootingWindow | openExplore | — | city-light-trails | heavy-rain|road-stop-unsafe|official-closure | cityArchitecture |
| event.city.fog_layers | 城市雾层 | 城里起雾 | 🌫️ | reserved | 不激活 | factualEvent | city | urban | skyline|architecture|river | place|weather|humidityDewPoint|visibility | cloudLayers|wind | — | openShootingWindow | openExplore | — | city-fog | low-visibility|road-stop-unsafe | cityArchitecture |
| session.desert.side_light | 荒漠侧光会话 | 侧光扫沙 | 🏜️ | core | available | shootingSession | landform | desert|plateau | dune|canyon|openHorizon | place|light|weather|wind|visibility | route|legalStop | timing.desertSide | openShootingWindow | openExplore | 0.68 | desert-side-light | strong-wind|dust-hazard|low-visibility|official-closure | mountainLandform |
| event.desert.dust_light | 风沙低角度光 | 风沙有光 | 🌬️ | legacyOnly | 不激活 | factualEvent | landform | desert|plateau | dune|openHorizon | place|weather|wind|visibility|light | route | — | openShootingWindow | openExplore | — | desert-dust-light | strong-wind|dust-hazard|low-visibility | mountainLandform |
| event.desert.dune_shadow | 沙丘明暗纹理 | 沙丘有线 | 🏜️ | reserved | 不激活 | factualEvent | landform | desert | dune|openHorizon | place|light|weather|visibility | wind|terrain | — | openShootingWindow | openExplore | — | desert-dune-shadow | strong-wind|dust-hazard|official-closure | mountainLandform |
| event.landform.texture | 地貌纹理窗口 | 纹理出来了 | 🪨 | reserved | 不激活 | factualEvent | landform | desert|plateau|mountain | canyon|dune|grassland|openHorizon | place|light|weather|visibility | terrain|wind | — | openShootingWindow | openExplore | — | landform-texture | strong-wind|low-visibility|official-closure | mountainLandform |
| event.canyon.light_beam | 峡谷光束 | 峡谷进光 | ✨ | reserved | 不激活 | factualEvent | landform | mountain|desert|plateau | canyon|reviewedViewpoint | place|light|terrain|lineOfSight|weather | cloudLayers | — | openShootingWindow | openExplore | — | canyon-light-beam | flash-flood|official-closure | mountainLandform |
| event.plateau.storm_clearance | 高原风暴后光线 | 风暴后见光 | ⛈️ | reserved | 不激活 | factualEvent | landform | plateau|mountain | openHorizon|grassland | place|weather|precipitation|light|visibility | cloudLayers|wind | — | openShootingWindow | openExplore | — | plateau-storm-clearance | thunderstorm|strong-wind|heavy-rain|official-closure | mountainLandform |
| event.sky.sunset_glow | 晚霞候选 | 晚霞候选 | 🌅 | core | degraded | factualEvent | atmosphere | urban|village|mountain|plateau|desert|forest|inlandWater|coast|wetland | openHorizon|skyline|reviewedViewpoint | light|weather|cloudLayers | visibility|precipitation | timing.sunsetGlow | openShootingWindow | openExplore | 0.68 | sunset-glow | thunderstorm|heavy-rain|official-closure | mountainLandform|waterCoast|cityArchitecture |
| event.weather.rainbow | 彩虹候选 | 彩虹候选 | 🌈 | core | unavailable | factualEvent | atmosphere | urban|village|mountain|plateau|desert|forest|inlandWater|coast|wetland | openHorizon | precipitation|directionalRain|light|weather | visibility | timing.rainbow | openShootingWindow | openExplore | 0.75 | rainbow | thunderstorm|heavy-rain|road-stop-unsafe | mountainLandform|waterCoast|cityArchitecture |
| event.atmosphere.morning_mist | 晨雾与低雾 | 雾要起来 | 🌫️ | core | degraded | factualEvent | atmosphere | village|mountain|plateau|forest|inlandWater|wetland | lake|river|wetland|canyon|forest|villageStreet | weather|wind|visibility|humidityDewPoint | terrain|place | timing.morningMist | openShootingWindow | openExplore | 0.70 | morning-mist | low-visibility|road-stop-unsafe|trail-return-risk | mountainLandform|waterCoast|forestDetail |
| event.atmosphere.tyndall_rays | 丁达尔光候选 | 光束出来了 | ✨ | reserved | 不激活 | factualEvent | atmosphere | forest|mountain|village|urban | forest|bambooForest|canyon|architecture | light|cloudLayers|humidityDewPoint|place | weather|terrain | — | openShootingWindow | openExplore | — | tyndall-rays | thunderstorm|heavy-rain | forestDetail|cityArchitecture |
| event.weather.post_rain_light | 雨后云隙光 | 云缝开了 | 🌤️ | reserved | 不激活 | factualEvent | atmosphere | urban|village|mountain|plateau|desert|forest|inlandWater|coast|wetland | openHorizon | weather|precipitation|cloudLayers|light | visibility | — | openShootingWindow | openExplore | — | post-rain-light | thunderstorm|heavy-rain | mountainLandform|waterCoast|cityArchitecture |
| event.weather.snowfall_layers | 降雪层次 | 雪里有层次 | 🌨️ | reserved | 不激活 | factualEvent | atmosphere | mountain|plateau|forest|urban|village | snowCover|forest|architecture | weather|precipitation|visibility|place | wind|light | — | openShootingWindow | openExplore | — | snowfall-layers | strong-wind|low-visibility|road-stop-unsafe | mountainLandform|forestDetail|cityArchitecture |
| event.astro.milky_way | 银河窗口 | 银河窗口 | 🌌 | core | unavailable | factualEvent | astronomy | mountain|plateau|desert|forest|inlandWater|coast|wetland | darkSky|openHorizon|reviewedViewpoint | astronomy|moonTrajectory|weather|cloudLayers|lightPollution|place | route|legalStop | timing.astroMilkyWay | openAstronomyDetail | openExplore | 0.75 | milky-way | official-closure|trail-return-risk | astroCelestial |
| event.astro.moon_window | 月出与月落窗口 | 月升东南 | 🌙 | core | degraded | factualEvent | astronomy | urban|village|mountain|plateau|desert|forest|inlandWater|coast|wetland | openHorizon|skyline|reviewedPeak|reviewedViewpoint | astronomy|moonTrajectory|weather|place | terrain|lineOfSight|route | timing.astroMoon | openAstronomyDetail | openExplore | 0.72 | moon-window | low-visibility|official-closure|trail-return-risk | astroCelestial |
| event.astro.meteor_shower | 流星雨窗口 | 流星雨 | ☄️ | core | available | factualEvent | astronomy | mountain|plateau|desert|forest|inlandWater|coast|wetland | darkSky|openHorizon|reviewedViewpoint | authority|astronomy|moonTrajectory|weather|cloudLayers | lightPollution|route | timing.astroMeteor | openAstronomyDetail | openExplore | 0.80 | meteor-shower | official-closure|trail-return-risk | astroCelestial |
| event.astro.special_authority | 权威特殊天象 | 特殊天象 | 🔭 | core | available | factualEvent | astronomy | urban|village|mountain|plateau|desert|forest|inlandWater|coast|wetland | openHorizon|reviewedViewpoint | authority|astronomy|weather | moonTrajectory|equipment|route | timing.astroAuthority | openAstronomyDetail | openExplore | 0.85 | special-astronomy | official-closure|unsafe-solar-viewing|trail-return-risk | astroCelestial |
| event.astro.star_trails | 星轨窗口 | 星轨窗口 | 🌠 | reserved | 不激活 | factualEvent | astronomy | mountain|plateau|desert|forest|inlandWater|coast|wetland | darkSky|openHorizon|reviewedViewpoint | astronomy|weather|cloudLayers|lightPollution|place | moonTrajectory|legalStop | — | openAstronomyDetail | openExplore | — | star-trails | official-closure|trail-return-risk | astroCelestial |
| event.astro.planetary_alignment | 行星与月亮对位 | 行星同框 | 🪐 | reserved | 不激活 | factualEvent | astronomy | urban|village|mountain|plateau|desert|forest|inlandWater|coast|wetland | openHorizon|reviewedViewpoint | authority|astronomy|moonTrajectory|weather | terrain|lineOfSight | — | openAstronomyDetail | openExplore | — | planetary-alignment | low-visibility|official-closure | astroCelestial |
| session.wetland.dawn | 湿地晨间会话 | 湿地醒了 | 🦆 | reserved | 不激活 | shootingSession | ecology | wetland|inlandWater | wetland|lake|river|reflectiveSurface|reviewedViewpoint | place|weather|light|ecology | wind|visibility | — | openShootingWindow | openExplore | — | wetland-dawn | wildlife-safety|official-closure|heavy-rain | wildlifeEcology|waterCoast |
| event.forest.light_beam | 森林光束 | 林间进光 | 🌲 | reserved | 不激活 | factualEvent | ecology | forest|mountain | forest|bambooForest|canyon | place|light|cloudLayers|humidityDewPoint | weather|terrain | — | openShootingWindow | openExplore | — | forest-light-beam | heavy-rain|official-closure|wildlife-safety | forestDetail |
| event.forest.mist | 森林雾气 | 林子起雾 | 🌫️ | reserved | 不激活 | factualEvent | ecology | forest|mountain | forest|bambooForest | place|weather|humidityDewPoint|visibility | wind|terrain | — | openShootingWindow | openExplore | — | forest-mist | low-visibility|trail-return-risk|wildlife-safety | forestDetail |
| event.flora.bloom | 花期窗口 | 花开正好 | 🌸 | reserved | 不激活 | factualEvent | ecology | forest|village|plateau|wetland|urban | grassland|forest|wetland|villageStreet | ecology|place|authority | weather|route | — | openPlaceDetail | openExplore | — | flora-bloom | official-closure | forestDetail |
| event.wildlife.bird_migration | 候鸟迁徙窗口 | 候鸟来了 | 🦅 | reserved | 不激活 | factualEvent | ecology | wetland|inlandWater|coast|plateau | wetland|lake|river|coast | ecology|authority|place | weather|route | — | openWildlifeDetail | openExplore | — | bird-migration | wildlife-safety|official-closure | wildlifeEcology |
| event.wildlife.mammal_activity | 野生动物活动窗口 | 附近有踪迹 | 🐾 | reserved | 不激活 | factualEvent | ecology | forest|mountain|plateau|desert|wetland | forest|grassland|canyon | ecology|authority|place | weather|route | — | openWildlifeDetail | openExplore | — | mammal-activity | wildlife-safety|official-closure | wildlifeEcology |
| session.route.light_window | 沿途光窗会话 | 沿途光窗 | 🚗 | core | degraded | shootingSession | humanityRoute | urban|village|mountain|plateau|desert|forest|inlandWater|coast|wetland | openRoad|reviewedViewpoint|openHorizon | route|weather|light|legalStop | place|visibility | timing.routeWindow | openRoute | openExplore | 0.72 | route-light-window | road-stop-unsafe|thunderstorm|heavy-rain|low-visibility|official-closure | mountainLandform|waterCoast|cityArchitecture |
| event.humanity.village_edge_light | 村落晨昏光线 | 村口有光 | 🏘️ | legacyOnly | 不激活 | factualEvent | humanityRoute | village | villageStreet|oldTown|architecture | place|light|weather | route | — | openPlaceDetail | openExplore | — | village-edge-light | official-closure | humanityStreet |
| event.humanity.market_morning | 清晨市集 | 去看早市 | 🧺 | reserved | 不激活 | factualEvent | humanityRoute | urban|village | oldTown|villageStreet | authority|place | route|weather | — | openPlaceDetail | openExplore | — | market-morning | official-closure | humanityStreet |
| event.humanity.festival | 节庆民俗 | 今晚有节 | 🏮 | reserved | 不激活 | factualEvent | humanityRoute | urban|village|plateau | oldTown|villageStreet|architecture | authority|place | route|weather | — | openPlaceDetail | openExplore | — | humanity-festival | official-closure | humanityStreet |
| event.humanity.pastoral_migration | 牧群转场 | 牧群回来了 | 🐑 | reserved | 不激活 | factualEvent | humanityRoute | plateau|desert|village | grassland|openRoad|openHorizon | authority|place|ecology | route|weather | — | openPlaceDetail | openExplore | — | pastoral-migration | wildlife-safety|official-closure | humanityStreet|wildlifeEcology |
| event.aerial.spatial_light | 航拍空间光影 | 从高处看看 | 🚁 | reserved | 不激活 | factualEvent | humanityRoute | urban|mountain|plateau|desert|forest|inlandWater|coast|wetland | openHorizon|skyline|dune|river|coast | place|weather|wind|authority|equipment | light|route | — | openPlaceDetail | openExplore | — | aerial-spatial-light | strong-wind|official-closure|no-fly-zone | aerialSpatial |

Core 数量：16；LegacyOnly：3；Reserved：29。


### 14.1 Core 模型的固定展示文案

| ID | 正常名称 | 降级名称 | 本地回退摘要 |
|---|---|---|---|
| `session.water.morning` | 湖岸晨光会话 | 湖岸晨光观察 | 晨间水面条件正在形成，先看风和光线的变化。 |
| `session.water.evening` | 湖岸晚间会话 | 湖岸晚光观察 | 日落、倒影和蓝调正在形成一个连续窗口。 |
| `session.mountain.morning` | 山地晨光会话 | 山地晨光候选 | 山体附近存在晨间暖光条件，当前不能承诺具体山峰受光。 |
| `session.mountain.evening` | 山地晚光会话 | 山地晚光候选 | 山地晚间光线正在变化，当前不能承诺日照金山。 |
| `session.city.blue_hour` | 城市蓝调会话 | 城市蓝调观察 | 蓝调时间正在靠近，建筑灯光与天空亮度将逐渐平衡。 |
| `session.city.after_rain` | 雨后城市会话 | 雨后城市候选 | 降水正在减弱，湿地面和灯光可能形成反光。 |
| `session.desert.side_light` | 荒漠侧光会话 | 荒漠侧光观察 | 低角度光正在增强地表纹理，先确认风和能见度。 |
| `session.route.light_window` | 沿途光窗会话 | 沿途光线观察 | 路线附近出现短时光线变化，但尚未确认合法停靠点。 |
| `event.sky.sunset_glow` | 晚霞候选 | 晚霞观察 | 当前云层信息只支持继续观察，不构成强晚霞承诺。 |
| `event.weather.rainbow` | 彩虹候选 | 不显示 | 缺少方向性降水时不生成事实机会。 |
| `event.atmosphere.morning_mist` | 晨雾与低雾 | 低雾观察候选 | 能见度和风支持观察低雾，但缺少完整露点证据。 |
| `event.mountain.post_snow_light` | 雪后光影 | 不显示 | 缺少降雪历史或积雪证据时不生成。 |
| `event.astro.milky_way` | 银河窗口 | 不显示 | 缺少银河轨迹或光污染证据时不生成。 |
| `event.astro.moon_window` | 月出与月落窗口 | 月亮时间窗口 | 当前只确认月亮时间范围，方位与地景对位仍需核实。 |
| `event.astro.meteor_shower` | 流星雨窗口 | 流星雨天气观察 | 权威事件存在；本地天气只决定是否值得守候。 |
| `event.astro.special_authority` | 权威特殊天象 | 特殊天象天气观察 | 事件时间来自权威目录，本地只补充天气与安全要求。 |

`unavailable` 行不进入 Today、灵感瓶和通知，不显示降级卡片。

### 14.2 机会硬过滤、排序与压制

硬过滤条件：

```text
CatalogTier != core
CoreCapabilityState == unavailable
命中 safetyConflicts
缺少 requiredEvidence
confidence < minimumConfidence
expiresAt <= now
目标无法在窗口结束前到达且动作要求到达
```

分数：

```text
confidence × 50
峰值≤30分钟 +20
峰值≤90分钟 +15
峰值≤3小时 +10
峰值≤12小时 +5
主场景完全匹配 +10
用户偏好匹配 +8
与当前路线相关 +7
存在审核目标 +5
所有证据新鲜 +5
任何必需证据过期 -40
无法按时到达 -25
24小时内已展示同一实例 -8
```

排序：总分降序 → `peaksAt` 升序 → `definitionId` 字典序 → `instanceId` 字典序。

固定压制：

```text
session.water.morning 压制 event.water.reflection
session.water.evening 压制 event.water.reflection
session.water.evening 压制时间重叠且方位差≤20°的 event.sky.sunset_glow
session.mountain.evening 压制时间重叠且方位差≤20°的 event.sky.sunset_glow
session.city.blue_hour 压制同地点同窗口的 event.sky.sunset_glow
session.city.after_rain 不压制 event.weather.rainbow
event.astro.special_authority(subtype=lunarEclipse) 压制重叠的 event.astro.moon_window
```

窗口重叠定义：交集时长 ≥ 较短窗口时长的 50%。


---

## 15. 16套时间策略

| ID | 目录跨度 | 可行动跨度 | 提前提醒 | 远期刷新 | 近期刷新 | 守候刷新 | 证据TTL | 窗口计算 |
|---|---|---|---|---|---|---|---|---|
| timing.waterMorning | 18h | 6h | 180m | 30m | 10m | 5m | 20m | 天文晨光前30分钟至日出后75分钟 |
| timing.waterEvening | 18h | 6h | 180m | 30m | 10m | 5m | 20m | 日落前90分钟至蓝调结束后30分钟；无蓝调数据时至日落后90分钟 |
| timing.mountainMorning | 24h | 8h | 240m | 30m | 10m | 5m | 20m | 民用晨光前45分钟至日出后90分钟 |
| timing.mountainEvening | 24h | 8h | 240m | 30m | 10m | 5m | 20m | 日落前120分钟至民用暮光结束后45分钟 |
| timing.cityBlue | 24h | 6h | 120m | 60m | 20m | 10m | 30m | 日落前30分钟至航海暮光结束后30分钟 |
| timing.cityAfterRain | 6h | 3h | 60m | 10m | 5m | 5m | 15m | 预计降水结束前10分钟至降水结束后120分钟 |
| timing.desertSide | 12h | 6h | 120m | 20m | 10m | 5m | 15m | 太阳高度2°–15°，单次窗口最长90分钟 |
| timing.routeWindow | min(路线预计时长+3h,12h) | 90m | 30m | 10m | 5m | 5m | 15m | 单个合法停靠窗口10–30分钟 |
| timing.sunsetGlow | 6h | 3h | 120m | 30m | 10m | 10m | 30m | 日落前90分钟至日落后45分钟 |
| timing.rainbow | 90m | 45m | 15m | 5m | 2m | 2m | 10m | 太阳高度0°–42°；最后有效证据消失后最多保留15分钟 |
| timing.morningMist | 12h | 6h | 180m | 30m | 10m | 10m | 20m | 天文晨光前60分钟至日出后120分钟 |
| timing.postSnow | 24h | 12h | 360m | 30m | 10m | 10m | 30m | 降雪结束至结束后12小时 |
| timing.astroMilkyWay | 365d | 72h | 12h | 60m | 30m | 15m | 60m | 天文黑夜且目标银河高度≥10° |
| timing.astroMoon | 365d | 72h | 6h | 60m | 30m | 15m | 60m | 月出或月落前45分钟至后45分钟 |
| timing.astroMeteor | 365d | 14d | 24h | 1440m(>72h) | 60m(≤72h) | 15m | 60m | 权威峰值前3小时至后3小时；权威目录窗口优先 |
| timing.astroAuthority | 730d | 30d | 72h | 1440m(>72h) | 60m(≤72h) | 15m | 60m | 完全采用权威目录的开始、峰值和结束时间 |

每个机会实例必须包含 `startsAt`、可选 `peaksAt`、`expiresAt`、`evidenceExpiresAt`。不得继续使用统一 15 分钟 TTL。

---

## 16. 旧数据迁移

| 旧值/事件 | 固定迁移 |
|---|---|
| `sunset` | 只作为会话 `sunset` 阶段；有 cloudLayers 才可转晚霞候选 |
| `blueHour` / `blue-hour` | urban 场景转 `session.city.blue_hour`；其他场景只作时间阶段 |
| `reflection` | 合并入水域晨/晚会话；无法合并的旧数据转 `event.water.reflection` |
| `alpenglow` | 合并入山地晨/晚会话的 warmLight 阶段；无 terrain/lineOfSight 时只写“山地暖光候选” |
| `morningMist` / `mist` | `event.atmosphere.morning_mist` |
| `sunsetGlow` | `event.sky.sunset_glow` |
| `dust-light` | `event.desert.dust_light` |
| `humanity-light` | `event.humanity.village_edge_light` |
| `route-light-window` | `session.route.light_window` |
| `astronomy` + meteorShower subtype | `event.astro.meteor_shower` |
| `astronomy` + solarEclipse/lunarEclipse/comet | `event.astro.special_authority` |
| 无 subtype 的 `astronomy` | 不显示；记录 `legacy_ambiguous_astronomy` |

缓存 schema 升级为：`context_snapshot_schema_version=5`、`opportunity_catalog_version=1`。迁移成功后回写 v5；收藏 ID 通过 alias 表保持稳定。

---

## 17. 96个标准标签

### 主体（12）

- `mountain_peak`
- `mountain_range`
- `lake`
- `river`
- `wetland`
- `coast`
- `city_skyline`
- `architecture`
- `street_people`
- `wildlife`
- `forest`
- `flowers`
### 场景（12）

- `alpine`
- `plateau`
- `desert`
- `canyon`
- `dune`
- `grassland`
- `village`
- `old_town`
- `waterfront`
- `shoreline`
- `woodland`
- `open_road`
### 现象（16）

- `reflection`
- `morning_mist`
- `low_fog`
- `cloud_sea`
- `rainbow`
- `sunset_glow`
- `alpenglow`
- `tyndall_rays`
- `after_rain`
- `post_snow`
- `dust_haze`
- `starry_sky`
- `milky_way`
- `moonrise`
- `meteor_shower`
- `eclipse_comet`
### 光线（12）

- `sunrise`
- `sunset`
- `blue_hour`
- `golden_hour`
- `side_light`
- `backlight`
- `side_backlight`
- `soft_light`
- `hard_light`
- `window_light`
- `artificial_light`
- `silhouette`
### 时间（8）

- `dawn`
- `morning`
- `noon`
- `afternoon`
- `dusk`
- `night`
- `seasonal`
- `fixed_date`
### 拍摄方法（15）

- `wide_angle`
- `telephoto`
- `panorama`
- `long_exposure`
- `slow_shutter`
- `focus_stack`
- `exposure_bracket`
- `star_tracking`
- `light_trail`
- `reflection_composition`
- `foreground_leading`
- `minimalism`
- `aerial`
- `time_lapse`
- `handheld`
### 活动（8）

- `stationary`
- `scouting`
- `waiting`
- `walking`
- `hiking`
- `driving`
- `route_stop`
- `return_journey`
### 装备（13）

- `tripod`
- `wide_angle_lens`
- `standard_zoom`
- `telephoto_lens`
- `macro_lens`
- `nd_filter`
- `gnd_filter`
- `polarizer`
- `star_tracker`
- `solar_filter`
- `rain_cover`
- `drone`
- `headlamp`

总数严格为 96。UI 不显示完整标签菜单；机会、创作提示、搜索候选和行为学习只能引用目录 ID，禁止自由字符串。

---

# 第六部分：灵感、智能体与联网搜索

## 18. 灵感瓶库存

候选池最大 120；当前库存最少 20、目标 36、最多 60；真实物理模拟 18 张。

目标构成：摄影事实8、地点发现8、人文6、创作8、路线2、生活2、记忆1、野生动物1。没有可靠内容时不强行补齐。

补货触发：库存<20、过期>40%、跨行政区、中心移动>20km、创建/开始路线、时间阶段变化、手动刷新、同点停留30分钟。

抽取采用加权无放回；Seed=`snapshotId + localDate + userPreferenceHash`。位置>5km、行政区、时间阶段、路线状态或环境机会实质变化时重建顺序。

### 18.1 Insight 通道

```dart
enum InsightChannel {
  photographyOpportunity,
  localDiscovery,
  humanityClue,
  creativePrompt,
  routeCompanion,
  lifeCompanion,
  memoryFollowUp,
  wildlifeOpportunity,
  safety,
}
```

`safety` 永不进入瓶子。Wildlife opportunity 最多占事实候选 1 条，不暴露敏感精确坐标。

### 18.2 Inspiration 状态与交互

瓶宽屏幕72%、高280px；纸条旋转限制±14°。抽取顺序：pressing→gathering→lifting→opening→opened。关闭：returning→idle。补货：refilling，不重建整页。

---

## 19. 48条创作提示完整数据

| ID | 短词 | 一句说明 | 场景亲和 | 技术标签 | 装备 | 冷却 |
|---|---|---|---|---|---|---|
| creative.composition.foreground | 靠近前景 | 向前移动，寻找一个能把视线带向主体的明确前景。 | mountain|inlandWater|coast|desert|forest | wide_angle|foreground_leading | wide_angle_lens | 24h |
| creative.composition.negative_space | 留点空白 | 减少无关元素，让主体与环境之间保留呼吸。 | urban|mountain|plateau|desert|coast | minimalism |  | 24h |
| creative.composition.repetition | 找重复线 | 寻找道路、窗格、树木或地形中重复出现的节奏。 | urban|village|forest|desert | architecture|minimalism |  | 24h |
| creative.composition.frame | 框住主体 | 利用门窗、树枝或岩石边缘形成天然画框。 | urban|village|forest|mountain | foreground_leading |  | 24h |
| creative.composition.compress | 压缩远景 | 后退并使用长焦，把远处的形状叠进同一画面。 | mountain|urban|village|plateau | telephoto|minimalism | telephoto_lens | 24h |
| creative.composition.layers | 拉开层次 | 移动位置，让前景、中景和远景彼此分离。 | mountain|forest|urban|inlandWater | foreground_leading|wide_angle | wide_angle_lens | 24h |
| creative.composition.single | 只留一个 | 从画面中删除元素，直到只剩一个明确视觉中心。 | urban|desert|coast|forest | minimalism |  | 24h |
| creative.composition.symmetry | 对称一下 | 寻找水面、建筑或道路形成的对称关系。 | urban|inlandWater|wetland|village | reflection_composition|architecture | tripod | 24h |
| creative.light.backlight | 看向背光 | 寻找轮廓、透光材质或被光勾出的边缘。 | forest|village|urban|plateau | backlight|silhouette |  | 24h |
| creative.light.beam | 等一束光 | 先固定构图，等待局部光线落到主体上。 | forest|mountain|urban|village | window_light|waiting | tripod | 24h |
| creative.light.side | 追着侧光 | 绕到光线侧面，让纹理和起伏变得更清楚。 | mountain|desert|urban|village | side_light |  | 24h |
| creative.light.shadow | 拍下阴影 | 把阴影当作主体，观察它与真实物体的关系。 | urban|desert|village|forest | hard_light|minimalism |  | 24h |
| creative.light.reflection | 借点反光 | 利用水面、玻璃或湿地面把光带进画面。 | urban|inlandWater|coast|wetland | reflection|reflection_composition | polarizer | 24h |
| creative.light.highlights | 收住高光 | 降低曝光，保留最亮区域的颜色和边缘。 | coast|mountain|urban|inlandWater | exposure_bracket | tripod | 24h |
| creative.light.lamps | 等灯亮起 | 在自然光尚未完全消失时等待人工灯光进入画面。 | urban|village | artificial_light|blue_hour | tripod | 24h |
| creative.light.fog | 让雾吃光 | 让光线在雾里扩散，不必追求清晰边缘。 | forest|mountain|wetland|urban | soft_light|morning_mist | telephoto_lens | 24h |
| creative.angle.low | 试试低机位 | 降低视点，让近处纹理与远景建立关系。 | mountain|inlandWater|desert|urban | wide_angle|foreground_leading | wide_angle_lens | 24h |
| creative.angle.height | 换个高度 | 向上或向下移动视点，检查重叠元素能否重新分离。 | urban|mountain|village|forest | scouting |  | 24h |
| creative.angle.look_back | 回头看一眼 | 离开前回看原来的方向，检查被忽略的光线和层次。 | all | scouting|return_journey |  | 24h |
| creative.angle.farther | 再远一点 | 后退几步，让主体和环境之间出现更多关系。 | urban|village|mountain|forest | scouting|minimalism |  | 24h |
| creative.angle.closer | 靠近一点 | 靠近主体，只保留最有质感或动作的一部分。 | urban|village|forest|wetland | handheld|minimalism | standard_zoom | 24h |
| creative.angle.crouch | 蹲下来 | 把视线降低到人物、动物或地面细节附近。 | village|wetland|forest|urban | handheld |  | 24h |
| creative.angle.backside | 绕到背面 | 绕到主体背后，观察逆光、轮廓和环境关系。 | urban|village|mountain|forest | backlight|scouting |  | 24h |
| creative.angle.ten_steps | 横走十步 | 横向移动十步，重新检查前后景重叠。 | all | scouting |  | 24h |
| creative.motion.wait_person | 等人入画 | 固定构图，等待一个人物进入合适的位置。 | urban|village | street_people|waiting |  | 24h |
| creative.motion.wind | 留住风感 | 选择较慢快门，表现草木、云层或衣物的运动。 | plateau|coast|forest|village | slow_shutter | nd_filter|tripod | 24h |
| creative.motion.water | 让水变慢 | 使用稳定支撑和慢快门，让流水或波纹变成连续形态。 | inlandWater|coast|mountain|forest | long_exposure|slow_shutter | tripod|nd_filter | 24h |
| creative.motion.freeze | 冻住瞬间 | 提高快门速度，抓住飞溅、跳跃或快速动作。 | wetland|forest|coast|urban | handheld | telephoto_lens | 24h |
| creative.motion.car | 等车经过 | 先确定背景和线条，再等待车辆进入关键位置。 | urban|village|plateau|desert | light_trail|waiting | tripod | 24h |
| creative.motion.cloud | 等云让开 | 保持机位不动，等待云层短暂露出主体或光线。 | mountain|plateau|inlandWater|coast | waiting | tripod | 24h |
| creative.motion.five_minutes | 多等五分 | 不立刻离开，给环境五分钟发生一次小变化。 | all | waiting |  | 24h |
| creative.motion.timelapse | 拍一段延时 | 固定构图，记录云、光线或人流的连续变化。 | urban|mountain|coast|desert | time_lapse | tripod | 48h |
| creative.story.hands | 拍手的动作 | 把注意力放在手与工具、食物或环境的关系上。 | village|urban | street_people|handheld | standard_zoom | 24h |
| creative.story.leaving | 拍离开的背影 | 观察人物离开时与空间之间形成的方向感。 | urban|village|plateau|desert | street_people|foreground_leading |  | 24h |
| creative.story.trace | 找一处痕迹 | 寻找磨损、脚印、旧招牌或被使用过的物件。 | urban|village|forest|desert | minimalism|handheld |  | 24h |
| creative.story.closing | 记录收摊前 | 观察人们整理、告别和收尾的动作。 | urban|village | street_people|waiting | standard_zoom | 48h |
| creative.story.sound | 跟着声音走 | 把声音当作线索，寻找正在发生的真实活动。 | urban|village|forest|coast | scouting|handheld |  | 24h |
| creative.story.person_environment | 拍人与环境 | 让人物保持较小比例，交代他与地点的关系。 | urban|village|mountain|plateau | wide_angle|street_people | wide_angle_lens | 24h |
| creative.story.passing | 只拍路过 | 不追逐完整事件，只记录一次短暂经过。 | urban|village|plateau|desert | handheld|street_people |  | 24h |
| creative.story.waiting | 拍下等待 | 寻找停留、排队、守候或休息中的人物状态。 | urban|village|plateau | street_people|waiting | telephoto_lens | 24h |
| creative.color.single | 只拍一种色 | 选择一种主色，主动排除与它无关的元素。 | all | minimalism |  | 24h |
| creative.color.contrast | 找冷暖对比 | 寻找冷色环境中的暖色主体，或相反关系。 | urban|village|coast|inlandWater | blue_hour|golden_hour |  | 24h |
| creative.color.bw | 试试黑白 | 忽略颜色，只判断光线、形状和明暗关系。 | urban|village|forest|desert | hard_light|minimalism |  | 48h |
| creative.experiment.blur | 故意留糊 | 用运动模糊表达速度或情绪，而不是追求全部清晰。 | urban|village|forest|coast | slow_shutter|handheld |  | 48h |
| creative.experiment.glass | 借玻璃一层 | 透过玻璃、水汽或反射拍摄，让画面多一层空间。 | urban|village | reflection|handheld |  | 48h |
| creative.experiment.tilt | 让画面倾斜 | 有意识地改变水平线，制造方向和不稳定感。 | urban|village|plateau|desert | handheld |  | 48h |
| creative.experiment.triptych | 连续拍三张 | 围绕同一主题拍远景、中景和细节三张照片。 | all | handheld|wide_angle|telephoto | standard_zoom | 48h |
| creative.experiment.repeat | 同一处再拍 | 回到之前的位置，用不同时间、焦段或方向再拍一次。 | all | scouting|return_journey |  | 72h |

连续忽略 3 次后，单条冷却从表中值提升为 7 天。


### 19.1 创作提示 Schema 约束

`sceneAffinity` 只允许本规格书的 10 个 `PrimaryScene` ID 或通配值 `all`；`techniqueTags` 和 `equipmentRequirement` 只能引用 96 标签目录。生成器必须拒绝未知值。

```json
{
  "id": "creative.composition.foreground",
  "shortLabel": "靠近前景",
  "guide": "向前移动，寻找一个能把视线带向主体的明确前景。",
  "sceneAffinity": ["mountain", "inlandWater", "coast", "desert", "forest"],
  "techniqueTags": ["wide_angle", "foreground_leading"],
  "equipmentRequirement": ["wide_angle_lens"],
  "cooldownHours": 24
}
```


---

## 20. 八个后台职能智能体运行契约

| Agent | 实现类型 | 联网 | LLM | 最大输出/调用 |
|---|---|---:|---:|---|
| Environment Sentinel | 规则与结构化计算 | 否 | 仅最终解释可选 | 10个候选机会 |
| Local Scout | AMap + Tavily + 抽取 | 是 | 1次抽取 | 6个地点候选 |
| Humanity Scout | Tavily + 来源抽取 | 是 | 1次抽取 | 6个人文候选 |
| Route & Logistics | AMap route/POI/weather | 受限 | 仅总结可选 | 8个节点 |
| Creative Director | 固定48库优先 | 否 | 最多1次个性化改写 | 8条候选 |
| Memory Agent | 本地/服务端权重 | 否 | 可选1次摘要 | 20个标签权重 |
| Safety Guardian | 确定性规则/权威源 | 权威源 | 否 | 所有有效安全事件 |
| Companion Orchestrator | 确定性排序与节流 | 否 | 最多1次最终表达 | Today 1+2；Inventory 36 |

一次 `companion/refresh` 的硬预算：

```text
最多3个搜索任务
每个任务最多3条查询
Tavily每条最多8结果
总搜索证据最多24条
最多2次LLM调用
单搜索超时8秒
总请求软超时12秒、硬超时15秒
最终新增Insight最多20条
```

Agent 不允许自主循环或自行创建新任务类型。

---

## 21. 搜索职责与确定流程

### 21.1 数据分工

- AMap：POI、坐标、行政区、距离、营业字段、餐饮/加油/休息、驾车/步行路线。
- Tavily：公开网页中的活动、人文故事、临时开放/关闭证据、专业摄影资料和近期提及。
- Context Service：天气、光线、安全、天文和摄影事实。
- Discovery Service：证据落库、候选归一、来源追溯和去重。
- Data Broker：鉴权、限流、供应商密钥、服务代理和 LLM 路由。

### 21.2 联网地点流程

```text
搜索→来源Allowlist→内容净化→LLM结构化抽取→名称解析→AMap地理编码→坐标区域检查→POI去重→Insight
```

无可靠坐标的结果可以成为地方故事/人文线索，不得成为 Marker 或路线目标。

### 21.3 Mission 类型

```text
popularPlaces, hiddenPlaces, humanityEvents, localStories,
routeConditions, openingAndClosure, seasonalSignals
```

现有 `/v1/explore/discover` Request 扩展：

```json
{
  "missionType": "humanityEvents",
  "focus": "早市 夜市 展览",
  "locale": "zh-CN",
  "region": {"latitude": 30.25, "longitude": 120.15, "radiusMeters": 5000},
  "timeRange": {"startsAt": "ISO", "endsAt": "ISO"},
  "routeCorridor": null,
  "interests": ["humanityStreet"]
}
```


### 21.3.1 每种 Mission 的固定查询模板

| Mission | 查询1 | 查询2 | 查询3 |
|---|---|---|---|
| popularPlaces | `{地区} 最近热门 地点` | `{地区} 摄影机位` | `{地区} 本月 热门旅行地点` |
| hiddenPlaces | `{地区} 小众地点` | `{地区} 本地人常去` | `{地区} 非热门摄影地点` |
| humanityEvents | `{地区} 今日 市集 活动` | `{地区} 本周 民俗 节庆` | `{地区} 早市 夜市 展览` |
| localStories | `{地点} 历史` | `{地点} 当地文化` | `{地点} 传统手艺` |
| routeConditions | `{道路名称} 当前路况` | `{路线名称} 临时封闭` | `{路线名称} 施工 管制` |
| openingAndClosure | `{地点} 今日开放` | `{地点} 临时关闭` | `{地点} 营业时间` |
| seasonalSignals | `{地区} 本月 花期` | `{地区} 候鸟` | `{地区} 季节景观` |

### 21.3.2 现有 Discovery 代码的分流要求

现有 `discovery/ingestion.mjs` 明确禁止 LLM 输出 `safety/risk/route/popularity`。保留该边界，并按 Mission 分流：

- `popularPlaces`：LLM 只抽取地点与来源；热度由 Broker 根据提及数量、来源数量和新鲜度计算；LLM 不输出热度。
- `hiddenPlaces`、`humanityEvents`、`localStories`：使用现有证据净化与结构化抽取。
- `routeConditions`：不使用通用 Discovery LLM；只使用 AMap 路况和 A/B 级官方来源。
- `openingAndClosure`：使用独立严格 Schema，只接受 A/B 级来源，不允许根据社区内容确认开放。
- `seasonalSignals`：来源不足时只生成“季节线索”，不得生成精确花期/迁徙事实。

Tavily `sourcePolicies` 继续遵守现有上限 **16 个审核域名**；搜索未配置时返回 `search_unconfigured`，客户端保留地图与环境能力。


### 21.4 热度定义

热度只表示近期公开内容的相对发现信号，不显示虚构分数。

```dart
class DiscoveryPopularitySignal {
  int recentMentionCount;
  int distinctSourceCount;
  DateTime latestMentionAt;
  double sourceDiversity;
  double freshnessScore;
}
```

前台只显示：`多个来源近期提到`、`最近一周讨论增加`、`当地长期热门`、`信息不足`。

### 21.5 来源等级与新鲜度

A级：政府、景区/交通/气象/主办方、博物馆和文化机构。B级：地图、票务、路线和结构化活动平台。C级：地方媒体、专业摄影/户外组织。D级：游记、短视频公开页、社区帖子。

开放、道路、票务、安全必须由 A/B 级支撑；D 级不得单独证明。

新鲜度：道路15m、临时活动2h、营业6h、热门24h、小众72h、当地故事30d、季节24h、POI7d。

---

## 22. 主动陪伴与通知

前台渠道：`foregroundInline`、`foregroundBanner`、`pushNotification`。

- 普通变化优先 inline；
- 用户不在相关页面但时效强时 Banner；
- 只有高价值、用户授权且时效强才 Push；
- 安静时段默认当地时间 22:30–07:30；安全、主动会话和路线关键变化例外；
- 驾驶状态普通 Push 不连续出现，只保留安全和路线关键变化。

主动档位：

| 档位 | 普通提醒 | 路线/会话中 | Push |
|---|---:|---:|---:|
| 静静陪着 | 2/日 | 2/日 | 1/日 |
| 正常搭子 | 6/日 | 8/日 | 3/日 |
| 热情跟班 | 10/日 | 14/日 | 5/日 |

普通主题冷却90分钟；快速变化机会20分钟；安全不计入。

人格状态：`scouting, excited, waiting, guiding, reassuring, urgent`。热情来自主动完成任务和持续跟进，不使用“主人、宝宝”等称呼。

---


### 22.1 文案长度与人格示例

| 位置 | 最大长度 |
|---|---:|
| Today 主判断 | 1–2句，最多40个汉字 |
| 纸条展开 | 1句，最多32个汉字 |
| 路线提醒 | 结论+动作，最多36个汉字 |
| Push 标题 | 最多16个汉字 |
| Push 正文 | 最多40个汉字 |

固定人格状态示例：

```text
scouting：我再替你看看附近有没有更合适的方向。
excited：西边这次真有点意思，云缝正在往太阳方向开。
waiting：先别动，风还在往下掉。再看十分钟。
guiding：从北边绕过去更快，还能避开拥堵。
reassuring：这一轮不用硬等。我给你换一个方向。
urgent：雷暴正在靠近。停止守候，立即返回车辆或室内。
```

禁止客服欢迎语、无意义卖萌、恋爱式称呼和用感叹号代替行动信息。

### 22.2 四类生活陪伴 Insight

| 类型 | 触发条件 | 短词 | 动作 |
|---|---|---|---|
| food | 当地11:30–13:30或17:30–20:30；附近有已验证餐饮/商店 | 前面有饭 | openPlaceDetail |
| supplies | 徒步/路线进行中；补给空档明显；附近有补水/商店 | 补点水 | openPlaceDetail |
| fuel | 驾车路线进行中；前方稳定加油站后存在长空档 | 该加油了 | openRoute |
| rest | 连续路线时间较长；存在合法安全休息点 | 歇一会儿 | openPlaceDetail |

生活陪伴可以进入灵感瓶；安全风险不能伪装为生活纸条。


## 23. 记忆与隐私

| 数据 | 默认存储 | 保留 |
|---|---|---|
| explicitPreference | 本地+账户同步 | 直到用户删除 |
| behaviorAffinity | 本地；匿名同步可选 | 180天滚动 |
| dismissalHistory | 本地 | 30天 |
| sessionOutcome | 本地；同步可选 | 直到用户删除 |
| equipmentProfile | 本地+账户同步 | 直到用户删除 |
| 精确位置历史 | 默认仅本地 | 7天滚动 |
| 用户保存的路线/轨迹 | 本地；同步可选 | 直到用户删除 |

行为权重：查看+1、停留20秒+1、收藏+4、创建路线+5、开始守候+6、拍摄成功+8、不感兴趣-6、连续忽略3次-3。30天无行为×0.85，90天×0.60。

用户可以查看依据、删除单项、清空学习、暂停学习。不得默认长期上传完整精确位置轨迹。

---

# 第七部分：API 与数据对象

## 24. CompanionInsight

```dart
class CompanionInsight {
  String id;
  InsightChannel channel;
  String title;
  String body;
  String shortLabel;
  String emoji;
  DateTime generatedAt;
  DateTime startsAt;
  DateTime? peaksAt;
  DateTime expiresAt;
  GeoScope geoScope;
  double confidence;
  int priority;
  ContextAction action;
  List<SourceReference> sources;
  bool canEnterBottle;
  bool canNotify;
  String? opportunityInstanceId;
  String? targetId;
  String? routeId;
  String? sessionId;
  String? searchMissionId;
}
```

LLM 只能修改 title/body/shortLabel；不能修改时间、位置、可信度、动作、安全、来源、ID 和通知权限。

### 24.1 `POST /v1/companion/refresh`

Headers：JWT、`Idempotency-Key` 必需。限流：6次/10分钟/用户。

Request：

```json
{
  "snapshotId": "ctx-...",
  "reason": "region_changed|route_created|route_started|time_phase_changed|dwell_reached|manual_refresh|opportunity_changed",
  "routeId": null,
  "visiblePage": "today",
  "localTimeZone": "Asia/Shanghai"
}
```

Response 200：

```json
{
  "primaryInsight": {},
  "secondaryInsights": [],
  "inventoryDelta": {"added": [], "expiredIds": []},
  "nextRefreshAt": "ISO",
  "partial": false
}
```

202：搜索仍在进行，返回已有内容和 `partial=true`。错误码：`invalid_snapshot`、`rate_limited`、`search_unconfigured`、`upstream_unavailable`、`unauthorized`。

### 24.2 `GET /v1/inspiration/inventory`

Query：`cursor`、`limit`（1–60）、`channels`。Response 含 `targetSize=36`、`minimumSize=20`、`maximumSize=60`、`nextCursor`。限流30/min。

### 24.3 `POST /v1/insights/:id/feedback`

Header `Idempotency-Key`。Action：`viewed,dismissed,saved,routed,started,completed,not_interested`。重复同 Key 返回原结果。限流60/min。

### 24.4 通用错误格式

```json
{"error":{"code":"rate_limited","message":"...","retryAfterSeconds":60,"requestId":"..."}}
```

---

# 第八部分：页面组件树

## 25. Today

```text
TodayPage
├─ TodayHeader
├─ TodayPrimaryNarrative
├─ TodayPrimaryInsightCard
│  ├─ TimeWindow
│  ├─ DirectionDistance
│  ├─ TrendLine
│  └─ PrimaryAction
├─ TodayEvidenceSummary (≤3)
├─ TodaySecondaryInsights (≤2)
└─ TodayCompanionLine (≤1)
```

`narrativeAsync` 优先级：验证 Narrative→本地规则模板→Catalog fallback→场景空状态。AI加载不阻塞快照。

删除“寻找水面”和通用湖岸空状态。各主场景使用专属空状态文案。


### 25.1 Today 场景空状态固定文案

| 主场景 | 主判断 | 主动作 |
|---|---|---|
| urban | 城市光线暂时平静。我再替你看看附近正在发生什么。 | 探索附近 |
| village | 街巷里暂时没有明显窗口，适合慢一点观察。 | 看看街巷 |
| mountain | 山体光线暂不突出，先看云层会不会继续打开。 | 查看山体方向 |
| plateau | 高原光线暂时稳定，我在看远处的天气变化。 | 查看远处天气 |
| desert | 现在没有明确光窗，可以先观察地表纹理和风向。 | 探索地貌 |
| forest | 林间光线比较均匀，适合慢一点找细节。 | 探索林间 |
| inlandWater | 水面暂时没有明显窗口，风还需要再下来一点。 | 查看水域 |
| coast | 海岸光线暂时平静，我会继续看潮位和天空。 | 查看海岸 |
| wetland | 湿地暂时没有明显窗口，适合先安静观察。 | 查看湿地 |
| unknown | 环境已经更新，我还没有找到足够可信的拍摄窗口。 | 探索附近 |


## 26. Explore

默认 SearchBar+Map+Intent+22% Sheet。意图固定：摄影机位、热门地点、小众地点、人文题材、当地活动、餐饮补给、加油站、休息点、野生动物。地点卡必须显示来源与更新时间。

## 27. Route

Sheet 26/55/90%。切换驾车/徒步保留旧路线，局部加载，新路线交叉淡入。沿途光窗必须有 legalStop；无该证据只显示“沿途光线观察”，不得建议停车。

## 28. Inspiration

库存与物理层分离。纸条必须从瓶中实际位置 Morph，不使用“瓶消失→卡片淡入”。Safety 永不进入。

## 29. Profile

首屏固定五入口：栖光如何理解我、摄影偏好、显示声音动态、隐私本机数据、我的收藏。摄影偏好固定 8 类：山地与地貌、水域与海岸、城市与建筑、人文与街头、星空与天象、野生动物与生态、森林与自然细节、航拍与空间视角。

---

# 第九部分：测试、性能与交付

## 30. 自动一致性测试

必须断言：48目录、16 Core、3 Legacy、29 Reserved、6/7/3能力、16时间策略、96标签、48创作提示、15 Golden 状态。

新增测试：

```text
opportunity_catalog_test.dart
legacy_opportunity_adapter_test.dart
scene_context_classifier_test.dart
opportunity_ranker_test.dart
opportunity_timing_policy_test.dart
narrative_boundary_test.dart
feedback_service_test.dart
inspiration_inventory_test.dart
```

服务端测试覆盖：Agent预算、来源Allowlist、地理编码校验、幂等、限流、partial response、安全覆盖和LLM字段边界。

## 31. 性能预算

- 普通设备接近60fps；
- 动态背景 RepaintBoundary；
- 物理纸条只模拟18张；
- 不可见 Tab 暂停高成本动画；
- 同屏长期大面积 Blur 仅导航一层；
- Shader 不每帧创建；
- build 中不计算机会或搜索排序；
- 短音预加载并设置50–120ms冷却；
- App后台暂停动画。

## 32. 验证命令

```bash
python3 tool/generate_catalog.py --check
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug

cd services/lumanest-context-service && pytest
cd ../lumanest-discovery-service && pytest
cd ../lumanest-data-broker && npm test
```

iOS环境可用时：`flutter build ios --simulator`。

## 33. 完成定义

实现完成必须同时满足：UI 15态 Golden 通过、目录计数通过、旧数据迁移通过、所有 Core 按能力状态运行、搜索来源可追溯、跨页面稳定ID连续、音效/触觉可关闭、减少动态完整、客户端无供应商私钥、Flutter与服务端测试通过。

最终体验不是“天气 App 加毛玻璃卡片”，而是一个界面轻盈、动作柔和、反馈细腻、主动侦察且不会夸大事实的旅行摄影搭子。
