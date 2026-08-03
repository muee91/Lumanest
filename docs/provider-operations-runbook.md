# Provider Hub 生产运行手册

"
    "## 控制台职责

"
    "所有 Provider 端点、Token、Map Key 和审核公告源均从 NAS 管理台的“密钥与服务 → Provider Hub”录入。密钥由现有加密配置存储保存，读取接口只返回是否配置和末四位。Flutter 不包含任何第三方凭据。

"
    "## 数据闭环

"
    "1. Broker 按 Provider 独立超时、缓存、合并并记录健康指标。
"
    "2. Sentinel Raster Gateway 仅接受 NDVI/NDSI/NDWI/地表变化的结构化观测元数据，前端不得将变化指数改写为最佳季节结论。
"
    "3. CAMS 和 Marine Gateway 只接受白名单信号类型。海洋模型不替代官方潮汐表。
"
    "4. 官方公告可来自标准网关或审核 Feed 注册表。只有 HTTPS、覆盖当前位置、仍在有效期、权威且显式允许晋升的关闭/封路/防火/管制公告进入 Context V5 安全链。
"
    "5. App 依据当前场景和路线状态显示最多四条信号；没有当前信号时不占位。

"
    "## Sentinel Raster Gateway 合同

"
    "返回 `observations` 数组，每项包含：`metric` (`ndvi|ndsi|ndwi|surfaceChange`)、`delta`、`cloudCoverage`、`spatialResolutionMeters`、`confidence`、`comparisonStart`、`comparisonEnd`、`observedAt`、`expiresAt`、`sourceUrl`。

"
    "## 标准化 CAMS / Marine / 官方公告 Gateway 合同

"
    "返回 `signals` 数组，每项包含：`kind`、`title`、`summary`、`verification`、`observedAt`、`expiresAt`、`sourceUrl`。Broker 会拒绝来源不明、过期、非 HTTPS 或类型不在白名单内的数据。

"
    "## 验收矩阵

"
    "仓库固定覆盖杭州西湖、海宁盐官、赛里木湖、独库公路、德令哈、珠峰大本营、贡嘎、梅里雪山、平潭和乌兰布统。上线后在控制台逐个选择坐标执行单源检测，并确认：无错误地理匹配、无过期信号、弱网不阻塞探索、海外源经当前后端出口可访问。
"
