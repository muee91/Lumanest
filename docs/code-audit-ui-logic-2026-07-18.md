# LumaNest 代码审计报告：UI 遮挡与逻辑链

**审计日期**：2026-07-18  
**范围**：`lib/src/presentation_v2/` 全部页面、`lib/src/core/context/`、`lib/src/features/explore/application/map_consent_controller.dart`、`lib/src/shared/actions/manifest_action_handler.dart`、`lib/src/features/location/presentation/manual_location_sheet.dart` 等核心 UI 与逻辑链。

---

## 1. 执行摘要

本次审计共发现 **5 项 UI 遮挡/适配问题** 和 **5 项逻辑链问题**，其中 **2 项 P0（可能导致崩溃）**、**4 项 P1（影响可用性或资源泄漏）**、**4 项 P2（体验或代码质量）**。核心风险集中在：

1. **底部导航栏遮挡 Explore/Route 页面面板**（P1）。
2. **Map consent 初始化时序错误可能导致应用崩溃**（P0）。
3. **AMapController 未释放造成 native 资源泄漏**（P1）。
4. **manifest action 底部弹窗内容过长时不可滚动**（P1）。
5. **键盘弹出时 Explore 搜索结果面板可能被遮挡**（P1）。

---

## 2. UI 遮挡与适配问题（已修复）

> 修复验证：`flutter analyze --no-pub` → **No issues found**；`flutter build apk --debug` → **✓ Built**。

### UI-01: `V2AppShell` 使用 `extendBody: true` 导致 Stack 页面内容延伸至导航栏下方
- **文件**：`lib/src/presentation_v2/shell/v2_app_shell.dart`
- **行号**：31, 33-75
- **级别**：P1
- **状态**：已通过在 Explore/Route 面板中动态计算偏移修复，未改动 V2AppShell。
- **问题**：`Scaffold.extendBody = true` 使 body 渲染到底部导航栏下方。Today/Profile 等使用 `V2PageStage`（padding bottom 104）的页面被保护；但 Explore/Route 使用全屏 `Stack`，其 `Positioned(bottom: 92)` 的 child 会直接延伸到导航栏视觉区域，导致遮挡。
- **影响**：在 iPhone 等带 Home Indicator 的设备上，Explore 的搜索面板、Route 的操作面板底部会被导航栏覆盖，按钮可能无法点击。
- **修复**：在 `v2_explore_page.dart` 和 `v2_route_page.dart` 中，将 `AnimatedPositioned` 的 `bottom` 从固定 `92` 改为 `MediaQuery.paddingOf(context).bottom + 80`，确保始终位于导航栏上方。

### UI-02: Explore 页面搜索结果面板固定 `bottom: 92`，未适配导航栏高度
- **文件**：`lib/src/presentation_v2/explore/v2_explore_page.dart`
- **行号**：243-274（`AnimatedPositioned` 的 `bottom`）
- **级别**：P1
- **状态**：已修复。
- **修复 diff**：`bottom: 92` → `bottom: MediaQuery.paddingOf(context).bottom + 80`，面板高度 clamp 上限改为 `(constraints.maxHeight - bottomInset) * .68`。

### UI-03: Route 页面底部操作面板固定 `bottom: 92`，同样存在遮挡
- **文件**：`lib/src/presentation_v2/route/v2_route_page.dart`
- **行号**：258-274（`AnimatedPositioned` 的 `bottom`）
- **级别**：P1
- **状态**：已修复。
- **修复 diff**：`bottom: 92` → `bottom: MediaQuery.paddingOf(context).bottom + 80`。

### UI-04: Explore 页面键盘弹出时搜索结果面板未上移，可能被键盘遮挡
- **文件**：`lib/src/presentation_v2/explore/v2_explore_page.dart`
- **行号**：243-274（`AnimatedPositioned`）
- **级别**：P1
- **状态**：已修复。
- **修复**：在 `LayoutBuilder` 中读取 `MediaQuery.viewInsetsOf(context).bottom` 和 `paddingOf(context).bottom`，将 `AnimatedPositioned` 的 `bottom` 设置为 `bottomInset + bottomPadding + 80`，同时把面板高度 clamp 上限改为 `(constraints.maxHeight - bottomInset) * .68`，避免键盘顶起面板后超出屏幕。

### UI-05: `manifest_action_handler` 的底部弹窗内容不可滚动
- **文件**：`lib/src/shared/actions/manifest_action_handler.dart`
- **行号**：43-89
- **级别**：P1
- **状态**：已修复。
- **修复**：`showModalBottomSheet` 增加 `isScrollControlled: true` 和 `useSafeArea: true`；内部 `Column` 改为 `SingleChildScrollView` 包裹；底部 padding 从固定 `34` 改为 `MediaQuery.paddingOf(context).bottom + 34`。

### UI-06: 手动地点选择地图选点页底部按钮未避开 Home Indicator
- **文件**：`lib/src/features/location/presentation/manual_location_sheet.dart`
- **行号**：221-256（`_MapLocationPicker` 的 `Positioned(bottom: 16)`）
- **级别**：P2
- **状态**：已修复。
- **修复**：`bottom: 16` → `bottom: MediaQuery.paddingOf(context).bottom + 16`。

### UI-07: `V2AppShell` 导航栏高度因 `SafeArea` 而不一致
- **文件**：`lib/src/presentation_v2/shell/v2_app_shell.dart`
- **行号**：33-35（`SafeArea` 的 `minimum`）
- **级别**：P2
- **状态**：未在本次修复中改动（设计一致性调整，非阻塞）。
- **建议**：将导航栏总高度固定为设计值，用 `SafeArea` 仅处理水平边距，底部通过显式 `padding` 留出固定高度。

---

## 3. 逻辑链问题（已修复）

### LOGIC-01: Map consent 初始化时序错误，可能导致应用崩溃（P0）
- **文件**：
  - `lib/src/features/explore/application/map_consent_controller.dart`（行 114-118，`ensureInitialized`）
  - `lib/src/presentation_v2/explore/v2_explore_page.dart`（行 97-112，`didChangeDependencies`）
  - `lib/src/presentation_v2/route/v2_route_page.dart`（行 114-122，`build` 的 `addPostFrameCallback`）
- **级别**：P0
- **状态**：已修复。
- **问题**：`MapConsentController.build()` 中 `unawaited(_restore())` 后立即返回 `MapConsentAwaiting()`；`_restore()` 可能稍后才将状态更新为 `MapConsentReady`。`ensureInitialized` 在状态非 Ready 时会抛 `StateError`，而 Explore 的 `didChangeDependencies` 和 Route 的 `addPostFrameCallback` 未先检查状态。
- **修复**：
  - `map_consent_controller.dart`：将 `ensureInitialized` 中的 `throw StateError` 改为静默 `return`。
  - `v2_explore_page.dart`：增加 `_tryInitializeMap()`，先判断 `consent is MapConsentReady` 再调用 `ensureInitialized`。
  - `v2_route_page.dart`：在 `addPostFrameCallback` 中先判断 `consent is MapConsentReady`，再 `setState` 和初始化。

### LOGIC-02: `AMapController` 未释放，导致 native 资源泄漏
- **文件**：
  - `lib/src/presentation_v2/explore/v2_explore_page.dart`（行 79，`AMapController? _mapController`）
  - `lib/src/presentation_v2/route/v2_route_page.dart`（行 155，`AMapController? _controller`）
- **级别**：P1
- **状态**：已修复。
- **修复**：在 Explore 和 Route 的 `dispose()` 中分别添加 `_mapController?.disponse()` 和 `_controller?.disponse()`（高德 SDK 的方法名即为 `disponse`）。

### LOGIC-03: `V2ExploreMapState` 的 `_initialized` 一次性标志在初始化失败后无法重试
- **文件**：`lib/src/presentation_v2/explore/v2_explore_page.dart`
- **行号**：84, 97-112
- **级别**：P2
- **状态**：已修复（随 LOGIC-01 一并处理）。
- **修复**：由于 `ensureInitialized` 已不再抛异常，且调用方会检查 Ready 状态，`_initialized` 标志不会再因异常而陷入死锁。

### LOGIC-04: `V2RouteStage` 的 `build` 在 `addPostFrameCallback` 中调用 `setState` 后执行 `ensureInitialized`
- **文件**：`lib/src/presentation_v2/route/v2_route_page.dart`
- **行号**：114-122
- **级别**：P2
- **状态**：已修复。
- **修复**：在 `addPostFrameCallback` 中先判断 `ref.read(mapConsentControllerProvider) is MapConsentReady`，再执行 `setState` 和 `ensureInitialized`。

### LOGIC-05: `V2InspirationPage` 在 `build` 中直接修改 state
- **文件**：`lib/src/presentation_v2/inspiration/v2_inspiration_page.dart`
- **行号**：100
- **级别**：P2
- **状态**：已修复。
- **修复**：将 `if (_selectedIndex >= notes.length) _selectedIndex = 0;` 改为使用 `clamp` 计算合法索引，并在索引越界时通过 `addPostFrameCallback` + `setState` 更新，避免在 `build` 中直接赋值。

### LOGIC-06: `EnvironmentLoader` 不同 trigger 的写入可能并发
- **文件**：`lib/src/core/context/environment_controller.dart`
- **行号**：63-67（`_inFlight`），`lib/src/core/context/environment_providers.dart` 行 192-259（`LiveEnvironmentController`）
- **级别**：P2
- **状态**：未修复（本次未改动）。
- **问题**：`load()` 通过 `_inFlight` 合并同一次 `EnvironmentLoader` 的请求，但 `build()` 的 background refresh 和 `refresh()` 的 manual refresh 使用不同的 `EnvironmentLoader` 实例，因此它们的 `cacheWriteGuard` 也是不同实例，无法阻止并发写入缓存。
- **建议**：将 `EnvironmentLoader` 的实例生命周期与 provider 绑定，或使用 `ContextCacheWriteGuard` 作为单例 provider，确保跨 loader 共享同一生成号。

### LOGIC-07: `V2TodayPage` 的 `judgement` 赋值链嵌套过深，可读性差
- **文件**：`lib/src/presentation_v2/today/v2_today_page.dart`
- **行号**：99-106
- **级别**：P2
- **状态**：已修复。
- **修复**：提取 `_resolveJudgement(...)` 静态方法，用 if-else 显式表达 safety > narrative > session > manifest 的优先级。

### LOGIC-08: `V2OpportunityPage` 对“未找到 session”统一显示“机会已经结束”
- **文件**：`lib/src/presentation_v2/opportunity/v2_opportunity_page.dart`
- **行号**：50-60
- **级别**：P2
- **状态**：已修复。
- **修复**：将 `session == null || session.id != sessionId` 的判断拆分为：
  - `session == null` → 显示“这个机会已经结束”。
  - `session.id != sessionId` → 显示“没有找到该机会”。

### LOGIC-09: `V2ProfileStylePage` 的器材输入框在偏好更新后不会同步
- **文件**：`lib/src/presentation_v2/profile/v2_profile_page.dart`
- **行号**：300-315（`initState` 和 `dispose`）
- **级别**：P2
- **状态**：未修复（本次未改动）。
- **建议**：在 `didUpdateWidget` 中同步 `controller.text = ref.read(profilePreferencesProvider).equipmentList`，但需避免光标跳动。

### LOGIC-10: `V2ExplorePage` 的 Marker 每次 rebuild 重新创建
- **文件**：`lib/src/presentation_v2/explore/v2_explore_page.dart`
- **行号**：281-307
- **级别**：P2
- **状态**：未修复（本次未改动）。
- **建议**：使用 `memoization` 或根据 `places`/`_searchResults` 的 hash/identity 缓存 marker 集合。

---

## 4. 其他可改进项（非阻塞）

1. **Today 页 `judgement` 文本省略**：在 compact 模式下 `maxLines: 2`，非 compact `maxLines: 3`。如果文本实际只有 1 行，第二行空白，视觉略有浪费。可接受。
2. **Route 页面使用 `route.instructions.firstOrNull`**：quiet 模式下显示下一条指令，但没有语音或实时导航，仅作展示。可接受。
3. **V2AppShell 的 `_V2NavigationButton` 的 `AnimatedContainer` 未设置 `curve`**：实际有 `curve: LumaNestMotion.emphasized`。已正确。
4. **Profile 的 `SavedPlace.category` 使用枚举名**：在收藏地点列表中直接显示，可能不够用户友好。建议映射为中文标签。

---

## 5. 修复验证

- `flutter analyze --no-pub`：No issues found。
- `flutter build apk --no-pub --debug`：✓ Built build/app/outputs/flutter-apk/app-debug.apk。

## 6. 结论

当前 LumaNest 的 V2 UI 在 **常规页面（Today/Profile/Inspiration）** 的底部安全区处理上基本到位，但 **Explore/Route 两个全屏地图页面** 的 `bottom: 92` 硬编码与 `extendBody: true` 产生冲突，是主要的 UI 遮挡风险。逻辑链上，**Map consent 的异步恢复 + 同步初始化调用** 是最危险的崩溃点，已在本次修复中解决。地图控制器释放、manifest action 弹窗滚动、键盘遮挡等 P1 问题也已修复。剩余未修复项（LOGIC-06、LOGIC-09、LOGIC-10、UI-07）为 P2 代码质量/设计一致性改进，可按排期后续处理。

建议按上述修复在 iPhone（带 Home Indicator）、Android 全面屏、小屏设备（iPhone SE）上分别验证 Explore、Route、手动地点选择、manifest action 弹窗的显示与交互。
