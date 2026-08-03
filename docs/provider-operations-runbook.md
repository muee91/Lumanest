# Provider Hub 生产运行手册

## 控制台职责

所有 Provider 端点、Token、Map Key 和审核公告源，均从 NAS 管理台的“密钥与服务 → Provider Hub”录入。

- 密钥使用现有加密配置存储保存。
- 管理 API 读取配置时，只返回“是否已配置”和末四位。
- Flutter 不包含任何第三方凭据。
- 修改 Provider 配置不要求重新构建 App。

## 数据闭环

1. Broker 对每个 Provider 独立执行超时、缓存、并发合并和健康记录。
2. Sentinel Raster Gateway 只接受 NDVI、NDSI、NDWI 和地表变化的结构化观测元数据；前端不得将指数变化改写为“最佳秋色”“已经积雪”等现场结论。
3. CAMS 和 Copernicus Marine Gateway 只接受白名单信号类型。海洋模型不能替代官方潮汐表。
4. 官方公告可以来自标准化 Gateway，也可以来自控制台登记的审核 Feed。
5. 只有满足 HTTPS、地理覆盖、当前有效、权威来源和显式安全晋升条件的关闭、封路、防火与管制公告，才能进入 Context V5 安全链。
6. App 根据当前场景和路线状态最多显示四条相关信号；没有当前有效信号时完全不占位。

## Sentinel Raster Gateway 合同

Gateway 返回 `observations` 数组。每项必须包含：

- `metric`：`ndvi`、`ndsi`、`ndwi` 或 `surfaceChange`
- `delta`
- `cloudCoverage`
- `spatialResolutionMeters`
- `confidence`：`limited`、`medium` 或 `high`
- `comparisonStart`
- `comparisonEnd`
- `observedAt`
- `expiresAt`
- `sourceUrl`

Broker 会检查时间顺序、数值范围、HTTPS 来源和数据新鲜度。无效项目会被丢弃，不会降级成猜测。

## CAMS、Marine 与官方公告 Gateway 合同

标准化 Gateway 返回 `signals` 数组。每项包含：

- `kind`
- `title`
- `summary`
- `verification`
- `observedAt`
- `expiresAt`
- `sourceUrl`

Broker 会拒绝来源不明、过期、非 HTTPS、验证等级非法或类型不在 Provider 白名单中的数据。

## 审核公告源注册

控制台中的 `officialNoticeSources` 是 JSON 数组。每个源至少需要：

```json
{
  "id": "zhejiang-scenic-notices",
  "name": "浙江景区公告",
  "feedUrl": "https://example.gov/feed.json",
  "homepageUrl": "https://example.gov/",
  "format": "jsonFeed",
  "enabled": true,
  "authoritative": true,
  "promoteToSafety": true,
  "allowDefaultSafetyExpiry": false,
  "defaultExpiryMinutes": 360,
  "refreshMinutes": 30,
  "coverage": {
    "latitude": 30.25,
    "longitude": 120.15,
    "radiusKm": 300,
    "regionCodes": ["330000"]
  },
  "allowedKinds": [
    "closure",
    "roadClosure",
    "fireRestriction",
    "regulation",
    "reopening",
    "eventChange"
  ]
}
```

安全晋升还要求公告当前有效。默认情况下，缺少明确结束时间的公告只作为参考信号；只有显式启用 `allowDefaultSafetyExpiry` 时，才允许使用源配置的默认有效期。

## 运维诊断

控制台提供：

- 配置状态
- 最近状态
- 最近成功时间
- 最近失败时间
- 最近响应耗时
- 最近信号数量
- 缓存命中、未命中和并发合并次数
- 单个 Provider 的坐标范围测试

单源测试的审计日志只保存 Provider ID 和脱敏 Trace ID，不保存测试坐标或密钥。

## 验收矩阵

仓库固定覆盖以下十个真实场景：

- 杭州西湖
- 海宁盐官
- 新疆赛里木湖
- 独库公路
- 青海德令哈
- 珠峰大本营
- 川西贡嘎
- 云南梅里雪山
- 福建平潭
- 内蒙古乌兰布统

上线后，应在控制台逐个选择坐标执行单源检测，并确认：

- 没有错误地理匹配
- 没有过期信号
- 弱网和单源故障不阻塞探索页
- 没有把模型或候选数据写成确定事实
- 海外数据源可通过当前后端出口稳定访问
- 官方公告只有在满足安全晋升门槛后才进入 Context V5
