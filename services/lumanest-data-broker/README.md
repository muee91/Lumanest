# LumaNest 数据代理

这是部署在 NAS Docker 上的轻量服务。它统一获取和风天气并代理高德 Web 服务；和风私钥、高德 Web Key 与项目凭据都不会进入 Flutter App。旧版 JWT 签发接口仅作为客户端迁移兼容入口保留。

## 网络与接口

- App API 端口：`8787`
- 局域网管理端口：`8788`，入口 `http://NAS_IP:8788/admin`
- 健康检查：`GET /healthz`
- 旧客户端 JWT 签发：`POST /v1/qweather/token`
- 周边 POI：`GET /v1/amap/nearby`
- 驾车路线：`GET /v1/amap/driving`
- 步行路线：`GET /v1/amap/walking`
- 路线高程剖面：`GET /v1/elevation/profile`
- 野生动物区域线索：`GET /v1/wildlife/nearby`
- AI 创作文案：`POST /v1/narrative`
- 在线情境快照：`POST /v1/context/snapshot`
- 情境来源状态：`GET /admin-api/context/sources`，仅限已登录的 LAN 管理会话
- 审核数据导入：`POST /admin-api/context/imports`，需要 LAN 会话与 CSRF
- JWT 签发接口需要请求头：`Authorization: Bearer <LUMANEST_SERVICE_TOKEN>`

在线情境快照的标准输入只包含 WGS84 坐标、观测时间、语言、白名单意图、路线阶段和契约版本。Broker 从和风获取实时天气、24 小时预报、分钟降水和官方预警，使用 Redis 缓存标准化结果，再将权威天气交给内部 FastAPI。旧客户端携带的 `weather`、`evidence` 和 `solar` 字段暂时仍可通过输入校验，但不会进入服务端安全规则；服务端始终覆盖这些字段。

将你的域名反向代理到 NAS 的 `8787` 端口即可。例如域名为 `weather.example.com` 时，App 端点是：

```text
https://weather.example.com/v1/qweather/token
```

不要把 NAS 的端口直接映射到公网。路由器反向代理只能指向 `8787`；禁止为 `8788` 创建公网反向代理规则。

野生动物接口只返回 GBIF 公开观测的区域级物种汇总（鸟类、兽类、两爬、昆虫等），不会返回观测坐标，也会过滤常见家养种。它仅用于创作线索，不能视为实时动物分布或安全预警；风险提示必须来自独立、权威或人工核验的风险区数据。

路线高程接口通过 Open-Meteo Elevation API 获取最多 64 个路线采样点的高程，仅返回高程数组，不返回坐标。使用和展示时需保留 Open-Meteo 数据来源说明；高程用于行程估算，不替代专业测绘或户外安全设备。

AI 文案没有默认供应商，也不会自动启用任何模型。模型只接收场景、时间阶段、天气类型、路线状态、已成立创作事件 ID 和确定性模板摘要；不接收坐标、安全事件或跳转动作。未配置、超时、返回越权字段或格式错误时，App 自动继续使用本地模板。

## NAS 部署

1. 将整个 `services/lumanest-data-broker` 目录复制到 NAS，例如：

   ```text
   /vol2/docker/lumanest/qweather-token-broker
   ```

2. 将本机生成的 `ed25519-private.pem` 安全复制到 NAS，例如：

   ```text
   /vol2/docker/lumanest/secrets/ed25519-private.pem
   ```

   在 NAS 上限制私钥文件权限：

   ```bash
   chmod 600 /vol2/docker/lumanest/secrets/ed25519-private.pem
   ```

3. 复制环境变量模板并填写值：

   ```bash
   cp qweather-token-broker.env.example qweather-token-broker.env
   ```

   - `QWEATHER_KEY_ID`：和风天气凭据 ID。
   - `QWEATHER_PROJECT_ID`：和风天气项目 ID。
   - `QWEATHER_API_HOST`：和风控制台分配的项目 API Host，必须为 HTTPS `*.qweatherapi.com`。
   - `QWEATHER_PRIVATE_KEY_FILE`：NAS 私钥的绝对路径。
   - `LUMANEST_SERVICE_TOKEN`：运行 `openssl rand -hex 32` 生成的随机值。
   - `AMAP_WEB_KEY`：高德控制台创建的 Web 服务 Key，仅部署在 NAS。
   - `AI_API_KEY`、`AI_BASE_URL`、`AI_MODEL`：只为旧版部署保留的迁移输入；它们绝不会自动建立、选择或启用模型档案。新部署无需填写。
   - `LUMANEST_CONFIG_MASTER_KEY`：32 字节随机密钥的 Base64，用于加密持久化配置。
   - `LUMANEST_ADMIN_PASSWORD`：首次启动时写入 Argon2id 哈希；之后修改 Key 不会要求重复输入密码。

   生成配置加密密钥时，不要把结果粘贴到聊天或提交到 Git：

   ```bash
   openssl rand -base64 32
   ```

4. 启动容器：

   ```bash
   docker compose up -d --build
   ```

   NAS 正式更新应从按提交号隔离的 release 目录执行，并使用仓库内的部署脚本。脚本会先校验 Compose 和当前应用镜像，停止旧栈以一致性归档现有命名卷，再构建新栈；健康检查或管理端口边界失败时会恢复归档卷和旧镜像，再验证旧栈：

   release 可用 `rsync --delete` 更新，但必须排除 NAS 上独立维护的环境文件，避免同步删除密钥。Broker 和情境服务必须放在同一个提交目录下，保持 Compose 的相对构建路径：

   ```bash
   rsync -az --delete --exclude qweather-token-broker.env \
     services/lumanest-data-broker/ NAS:/vol2/docker/lumanest/releases/<commit>/qweather-token-broker/
   rsync -az --delete \
     services/lumanest-context-service/ NAS:/vol2/docker/lumanest/releases/<commit>/lumanest-context-service/
   ```

   ```bash
   cd /vol2/docker/lumanest/releases/<commit>/qweather-token-broker
   ./scripts/nas-deploy.sh
   ```

   新 release 没有环境文件时，脚本会从当前 release 继承受保护的环境文件并保持 `600` 权限。脚本在停服务前归档当前 Broker/Context 镜像和旧 release 源码，停服务后再一致性归档命名卷；新栈迁移、健康检查或管理端口边界失败时，会先停新栈、恢复旧卷和旧镜像，再启动并验证旧栈。任一步恢复失败都会明确报错，不会声称恢复成功。

   成功后，备份位置以原子方式写入 `/vol2/docker/lumanest/last-backup`。需要恢复旧配置、镜像和卷时必须显式确认破坏性卷恢复：

   ```bash
   backup=$(cat /vol2/docker/lumanest/last-backup)
   env CONFIRM_ROLLBACK=yes ./scripts/nas-rollback.sh "$backup"
   ```

   如果部署中断且自动恢复也明确失败，`current-release` 可能仍指向旧 release。确认使用的正是失败部署刚生成的备份后，才可增加二次确认重试恢复；此开关不允许把更早的备份跨过后续 release 覆盖回来：

   ```bash
   env CONFIRM_ROLLBACK=yes CONFIRM_FAILED_DEPLOY_RECOVERY=yes \
     ./scripts/nas-rollback.sh /vol2/docker/lumanest/backups/<failed-deploy-timestamp>
   ```

   部署账号必须属于 NAS 的 `docker` 组。脚本通过受限、无网络的临时容器读取和恢复命名卷，不再读取宿主机 Docker 卷目录，也不要求以 root 运行。回滚会先校验路径、源码归档、镜像归档和全部卷归档，再停止当前 release；恢复后必须通过 Broker、管理端口边界和内部情境服务健康检查，才会更新 `current-release`。执行前应确认备份路径和时间。

5. 在 NAS 本机或局域网验证：

   ```bash
   curl http://NAS_IP:8787/healthz
   ```

   成功时只返回：

   ```json
   {"status":"ok"}
   ```

6. 在局域网浏览器打开 `http://NAS_IP:8788/admin`。密钥仅显示配置状态和末四位，保存后对后续请求立即生效，无需重启 Docker。

完整情境服务还需要两个仅保存在 NAS 环境文件中的值：

- `CONTEXT_INTERNAL_TOKEN`：Broker 与 FastAPI 情境服务之间的独立随机令牌，不能传入 Flutter。
- `LUMANEST_DATABASE_PASSWORD`：PostgreSQL 专用随机密码，不能与管理密码或 App 服务令牌复用。

Broker 还通过 Compose 内部的 `REDIS_URL` 缓存和风标准化结果。缓存键使用位置网格哈希，不保存可读精确坐标；缓存不可用时直接请求和风，来源失败时最多使用两小时内、明确标记为陈旧的缓存，陈旧天气不会生成创作机会或预报事件。

Compose 不向宿主机映射 FastAPI、PostgreSQL 或 Redis 端口。App 仍只能访问 `8787`，管理台仍只能通过局域网 `8788` 访问。

情境导入接口只接受严格校验的 `spatialFeatures` GeoJSON 或
`astronomyEvents` 目录，每次最多 500 条、请求体最多 2 MiB。同一来源的新版本以事务方式替换旧数据。
来源必须包含许可状态、署名和版本；只有 `approved` 来源允许启用。敏感空间记录不能导入精确点位，
必须先降精度为至少约 0.01 度跨度的区域。导入审计只记录操作类型和结果，不记录几何、目录内容或内部令牌。
当前有效的已审核天象记录可以携带目录标题和 HTTPS 权威来源进入情境快照；Broker 会拒绝 HTTP、缺少标题、
来源类别不符或尝试把链接挂到其他动作上的响应。该事件只确认目录事实，不保证本地可见。

## 模型服务

在局域网管理台的“模型服务”中新建档案，再明确选择主模型；没有档案时，App 保持本地确定性模板，不会暗中请求任何供应商。内置模板包括 OpenAI、Anthropic、Gemini、通义千问、DeepSeek、智谱、Moonshot、火山引擎、OpenRouter、Ollama 和自定义 OpenAI 兼容服务。

- 每个档案的 Key 只以加密形式保存在 NAS，界面只显示末四位。
- 备用链默认关闭。开启前请确认各家模型的计费、额度与数据处理规则；一次创作请求最多尝试三个已明确排序的档案。
- Ollama 可以不填 Key，但其服务端点必须能从 NAS 容器访问。不要把未鉴权的 Ollama 端口暴露到公网；建议使用 NAS 局域网地址、访问控制或反向代理鉴权。
- 单个档案的“测试连接”只返回稳定的连接类别，不返回上游错误正文、请求内容或密钥。

## 域名反向代理

在 NAS 的反向代理管理页创建规则：

| 项目 | 值 |
| --- | --- |
| 来源协议 | HTTPS |
| 来源主机名 | 你的天气服务域名，例如 `weather.example.com` |
| 来源端口 | `443` |
| 目标协议 | HTTP |
| 目标主机 | `127.0.0.1` 或 NAS 内网地址 |
| 目标端口 | `8787` |

管理端口 `8788` 不得加入这条规则，也不得创建独立公网规则。

绑定 TLS 证书后，再请求：

```text
https://你的域名/healthz
```

确认健康检查成功后，Flutter 只需访问 Broker；`/v1/qweather/token` 在旧客户端兼容期结束前保留。

## 运维

```bash
# 查看状态与日志（日志不会记录 JWT 或私钥）
docker compose ps
docker compose logs --tail=100 qweather-token-broker

# 更新后重新构建
docker compose up -d --build

# 忘记管理密码时，在 NAS 本机通过环境文件重置；不会输出哈希
docker compose --env-file qweather-token-broker.env run --rm qweather-token-broker node src/admin/admin-cli.mjs reset-password
```

如果泄露了 `LUMANEST_SERVICE_TOKEN`，生成一个新随机值、更新 NAS 的 `qweather-token-broker.env` 并重启容器即可。若怀疑 Ed25519 私钥泄露，需要在和风控制台删除旧凭据、生成新密钥对并重新上传公钥。
