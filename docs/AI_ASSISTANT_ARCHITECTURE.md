# 栖光 AI 助理架构基线

状态：`main` 实施基线  
适用范围：Flutter 客户端、Data Broker、LLM 路由、今日摘要、灵感标签、问栖光

## 1. 核心原则

栖光不是让大模型判断天气、风险、机位和拍摄机会的聊天应用。

固定链路：

```text
可信数据源
  → 确定性领域规则
  → ContextSnapshot / ContextEntry / ShootingSession
  → 确定性模板答案
  → 可选 LLM 自然语言改写
  → Grounding Guard
  → 用户可见文本
```

模型永远不是以下事实的来源：

- 安全预警与风险等级
- 天气、天象和时间窗口
- 摄影机会等级或概率
- 地点是否为已审核机位
- 路线可达性与导航结果
- 器材必要性
- 用户是否应当出发

## 2. 当前两条 AI 链路

### 2.1 问栖光

```text
用户输入
  → AssistantIntentParser
  → 本地结构化意图
  → 本地确定性答案
  → 非安全、非附近、无本地约束时可请求 /v1/assistant
  → 服务端 Snapshot 与事件引用验证
  → 模型仅改写模板
  → Grounding Guard
  → 模型失败时回退本地答案
```

支持意图：

- `why`
- `prepare`
- `wording`
- `nearby`
- `timing`
- `creative`
- `safety`

强制本地回答：

- `safety`
- `nearby`
- 包含可用分钟数的提问
- 包含步行/驾车约束的提问
- 指定器材的提问

原因：当前 Broker Fact Contract 尚未携带这些用户约束。将其发送给模型会丢失约束或诱导模型补事实。

### 2.2 Narrative

```text
UiManifest 已成立创作事件
  → templateSummary
  → /v1/narrative
  → 模型生成 summary + noteLabels
  → 服务端 Grounding Guard
  → 客户端 Schema Guard
  → ManifestNarrative
```

Narrative 只能改变：

- 今日摘要的表达
- 已允许创作事件的 2–8 字标签

不能新增事件、地点、安全结论、动作或数字。

## 3. 模型输出守卫

`services/lumanest-data-broker/src/llm/grounding-guard.mjs` 对受控 Prompt 执行：

- JSON 结构与长度检查
- URL 与换行禁止
- 新数字禁止
- 新时间禁止
- 新器材禁止
- 新地点实体禁止
- 新安全结论禁止
- 新行动建议禁止
- 概率和百分比禁止
- Narrative 标签 ID 白名单

任何一项失败：

```text
模型候选丢弃 → 确定性模板继续返回
```

不得将 Guard 失败展示成用户错误。

## 4. 模型路由

`routeNarrative` 支持：

- Primary Profile
- 最多两个 Fallback Profile
- 最大三次尝试
- 仅 timeout、rate limit、upstream unavailable 触发 fallback
- 非法响应、认证失败、模型不存在不盲目切换
- Grounding Guard
- 路由指标
- 服务级 Prompt Budget 熔断

Prompt Budget 是服务级保护，不是用户配额。真实用户限流应继续在 Broker 身份/IP 边界执行。

## 5. 客户端会话

客户端保留最多八个已完成回合，目的仅是维持当前 Bottom Sheet 的可读性。

当前不会把历史回答重新发送给模型，因此不得宣称：

- 模型记住了完整对话
- 模型理解上一轮自由文本
- 存在长期用户记忆

新问题会取消旧请求。会话关闭后不持久化原始问题、定位轨迹或完整环境数据。

## 6. 地点边界

当前附近地点来自客户端 AMap/Discovery 链路，服务端 `/v1/assistant` 尚未拥有可按 Place ID 重新解析的权威地点存储。

因此：

- Nearby 回答完全本地生成
- 客户端不向模型传输 `NearbyPlace`
- 不允许模型把普通候选升级成审核机位
- 地图继续使用完整 `NearbyPlace` 列表
- `ContextEntry` 只用于编排和跨 Surface 投放

未来只有在服务端支持 `placeIds → verified place facts` 后，才允许附近问题进入模型改写。

## 7. 安全边界

安全问题不调用模型。

固定链路：

```text
官方预警 / 确定性规则
  → SafetyEntry
  → 独立安全卡
  → 固定模板或官方原文摘要
```

禁止：

- 模型降低或提高风险等级
- 模型生成撤离、进入、绕行等行动指令
- 模型根据普通天气字段自行创建预警
- 将内部 confidence 显示为安全概率

## 8. 多输入扩展门槛

参考成熟旅行应用，可以逐步加入文本、语音、图片、链接和拍照输入，但必须遵循以下门槛。

### 8.1 语音

```text
端侧 Speech-to-Text
  → 用户可编辑文本
  → AssistantIntentParser
```

不得默认上传原始录音。必须有麦克风权限说明和明确录音状态。

### 8.2 图片 / OCR

```text
端侧 OCR / EXIF
  → 脱敏
  → 用户确认识别文本或地点
  → Discovery Candidate
```

不得把 OCR 结果直接升级为 POI、机位或路线事实。

### 8.3 链接

```text
用户主动粘贴并授权
  → URL 安全检查
  → Crawl4AI / Discovery Service
  → 证据化候选
  → 用户确认
```

禁止客户端直接抓取任意 URL，禁止把网页文本直接作为可信事实。

### 8.4 拍照

端侧可做主体检测、EXIF 和简单分类。云端图像理解只能生成创作建议或记录草案，不得生成安全判断。

## 9. 流式输出

当前模型输出最长 80 字，普通 HTTP + 可取消请求优于 SSE：

- 实现简单
- 弱网降级稳定
- 不显示未经 Guard 校验的中间 Token
- 不产生“思维链”展示风险

只有出现长行程、长路线研究或多工具任务时，才评估服务端事件流。即使启用流式，也必须先在服务端完成完整候选，再通过 Guard 后一次性向业务层提交。

禁止展示或存储模型私有思维链。界面只能显示“正在整理已成立的信息”等产品状态。

## 10. 缓存与恢复

Narrative 缓存必须包含：

- Snapshot ID
- Snapshot observedAt
- Manifest creative IDs
- Manifest summary
- 用户偏好指纹
- Narrative tone

模型失败只执行短退避，不把模板缓存为长时间成功结果。缓存必须有容量上限并清理过期项。

## 11. 隐私与日志

日志只记录枚举状态，不记录：

- 用户原始问题
- 模型完整回答
- 经纬度
- 地点名称
- Snapshot ID
- API Key
- Prompt 内容

允许记录：

- started / completed / failed
- model / template
- timeout / rate limit / invalid response / fallback
- 调用次数和缓存命中

## 12. Codex 验证清单

必须运行：

```bash
flutter analyze
flutter test
cd services/lumanest-data-broker
npm test
```

重点用例：

1. 安全问题不触发模型请求。
2. 附近问题不发送地点名称给模型。
3. 指定“20 分钟、驾车、长焦”等约束后保持本地确定性。
4. 模型新增地点、数字、时间、器材、概率、行动结论时回退模板。
5. Snapshot 过期返回本地答案。
6. 新问题取消旧模型请求。
7. Narrative 不同 tone 不复用缓存。
8. 新环境批次不复用旧 Narrative。
9. 模型临时失败后只短退避，随后可恢复。
10. 上游响应过大、重定向、非法 JSON 被拒绝。
11. 日志不包含问题正文、地点名、坐标或 Prompt。

## 13. 完成定义

只有同时满足以下条件，才可将当前 AI MVP 标记为完成：

- 规则和数据决定事实，模型只决定表达
- 所有模型输出经过服务端 Guard
- 客户端始终有确定性回退
- 安全和附近链路不依赖模型
- 本地约束不会在远端调用中丢失
- 请求可取消、错误可分类、日志可观测
- 缓存按数据批次和语气隔离
- 多模型 fallback 不绕过事实守卫
- Flutter 与 Broker 全量测试通过
