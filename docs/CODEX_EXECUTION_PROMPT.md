# Codex 执行入口：栖光 LumaNest 全量重构

在仓库根目录执行本任务。工程事实源为：

```text
docs/LUMANEST_FINAL_ENGINEERING_SPEC.md
```

先完整阅读该文件，再修改代码。规格书中的计数、ID、状态机、API、时间策略、页面结构、动效、音效和测试均为已确定产品决策。

## 当前仓库与参考资源

- Flutter 根目录：当前仓库根目录（原压缩包中的 `on-the-way/`）
- 参考音频来源：用户提供的 `calLog_analysis/extracted_resources/audio/`
- 不导入参考项目的视频和字体。
- `click.wav` 与 `liveButton.wav` SHA-256 相同，只打包一个运行样本。
- `changeCard.wav` 转为 44.1kHz/16-bit 运行副本。

## 实施原则

1. 保留 Riverpod、GoRouter、Drift、Dio、高德地图、Context Service、Data Broker 和 Discovery Service。
2. 不重写现有安全与隐私边界。
3. 目录数据只来自 `catalog/*.v1.json`，Dart/Python/MJS 由 `tool/generate_catalog.py` 生成。
4. 页面只读取状态和组织组件；机会判断、排序、TTL、搜索和学习不得写进 Widget。
5. LLM 只改写表达，不能修改事实、时间、位置、动作、安全、来源或可信度。
6. Core 能力不足时严格使用 `degraded` 或 `unavailable`，不得创建模拟事实。
7. 不新增视频背景；保留并修复实时环境背景。
8. 跨 Tab 容器形变使用 Root Overlay/Root Navigator，不依赖跨 Navigator 自动 Hero。

## 修改范围

按规格书完成以下全部内容：

- 设计令牌、Motion、Morph、数字过渡、加载状态；
- 原生音频和触觉服务；
- AppShell、Router、Today、Explore、Route、Inspiration、Profile、Shooting Window；
- 复合 SceneContext；
- 48项目录、16套时间策略、96标签、48创作提示；
- 旧机会、旧事件和缓存迁移；
- 8智能体运行契约与 Companion Orchestrator；
- `/v1/companion/refresh`、`/v1/inspiration/inventory`、`/v1/insights/:id/feedback`；
- 扩展现有 `/v1/explore/discover`，不要创建重复搜索执行端点；
- 搜索来源校验、AMap地理编码、地点去重和热度信号；
- 记忆、主动提醒和隐私保留规则；
- 15个 Golden 状态与所有自动一致性测试。

## 源码审计锚点

优先检查并修复：

```text
lib/src/app/router.dart
lib/src/app/app_shell.dart
lib/src/features/today/presentation/today_page.dart
lib/src/features/explore/presentation/explore_page.dart
lib/src/features/route/presentation/route_page.dart
lib/src/features/inspiration/presentation/inspiration_page.dart
lib/src/features/inspiration/presentation/widgets/inspiration_bottle.dart
lib/src/features/profile/presentation/profile_page.dart
lib/src/features/shooting_window/presentation/shooting_window_page.dart
lib/src/shared/widgets/ambient/ambient_canvas.dart
lib/src/shared/widgets/ambient/ambient_shader_surface.dart
lib/src/core/context/context_snapshot.dart
lib/src/core/context/context_rule_engine.dart
lib/src/core/photography/photography_opportunity.dart
lib/src/core/photography/shooting_session.dart
lib/src/core/manifest/manifest_policy.dart
services/lumanest-context-service/app/
services/lumanest-data-broker/src/
services/lumanest-discovery-service/app/
```

## 执行顺序

执行顺序只用于控制依赖，不代表分批交付：

1. 建立 JSON Schema、4个Catalog文件和生成器，先让计数测试通过。
2. 完成 SceneContext、Evidence、Opportunity、Timing、Legacy迁移。
3. 完成 API 和 Agent 编排，只维护当前单一契约；除非产品负责人明确宣布“开始公测”并记录兼容窗口，不得保留旧端点或旧字段兼容。
4. 完成设计系统、反馈服务、Root Navigator 和页面状态机。
5. 重构六个页面并接通跨页稳定 ID。
6. 修复 Ambient Canvas/Shader。
7. 接入灵感库存、联网发现、记忆和主动提醒。
8. 完成 Golden、Widget、Dart、Python、Node测试与构建。

## 每次提交前检查

- 不存在新的自由字符串机会或标签；
- 不存在统一15分钟TTL；
- 不存在页面整页 `CircularProgressIndicator`；
- 不存在客户端供应商API Key；
- 不存在跨页面通过标题匹配对象；
- 不存在安全内容进入灵感瓶；
- 不存在 LLM 直接决定机会或安全；
- 不存在每帧创建 FragmentShader；
- 不存在 `click.wav` 和 `liveButton.wav` 重复打包。
- 在“开始公测”前，不存在旧客户端/API 兼容层、双读双写、旧参数默认值或静默协议回退。

## 最终运行

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

iOS环境可用时运行：

```bash
flutter build ios --simulator
```

## 最终报告

输出：

1. 修改/新增文件清单；
2. 目录计数与生成器校验结果；
3. 16个Core能力状态；
4. 旧数据迁移结果；
5. 六个页面的UI/UX变化；
6. Agent、搜索和API实现；
7. 音效、触觉和动态背景结果；
8. Golden与性能结果；
9. Flutter/Python/Node测试与构建日志摘要；
10. 仅列真实外部数据限制，不把规格书中的必做项列为后续任务。
