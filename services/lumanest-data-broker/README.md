# LumaNest 数据代理

这是部署在 NAS Docker 上的轻量服务。它用 NAS 中的 Ed25519 私钥签发 15 分钟有效的和风天气 JWT，并代理高德 Web 服务；和风私钥、高德 Web Key 与项目凭据都不会进入 Flutter App。

## 网络与接口

- 容器端口：`8787`
- 健康检查：`GET /healthz`
- JWT 签发：`POST /v1/qweather/token`
- 周边 POI：`GET /v1/amap/nearby`
- 驾车路线：`GET /v1/amap/driving`
- 野生动物区域线索：`GET /v1/wildlife/nearby`
- JWT 签发接口需要请求头：`Authorization: Bearer <LUMANEST_SERVICE_TOKEN>`

将你的域名反向代理到 NAS 的 `8787` 端口即可。例如域名为 `weather.example.com` 时，App 端点是：

```text
https://weather.example.com/v1/qweather/token
```

不要把 NAS 的 `8787` 端口直接暴露到公网；仅让 NAS 的 HTTPS 反向代理访问它，并在反向代理处启用速率限制。

野生动物接口只返回 GBIF 公开观测的区域级物种汇总（鸟类、兽类、两爬、昆虫等），不会返回观测坐标，也会过滤常见家养种。它仅用于创作线索，不能视为实时动物分布或安全预警；风险提示必须来自独立、权威或人工核验的风险区数据。

## NAS 部署

1. 将整个 `services/lumanest-data-broker` 目录复制到 NAS，例如：

   ```text
   /volume1/docker/lumanest/data-broker
   ```

2. 将本机生成的 `ed25519-private.pem` 安全复制到 NAS，例如：

   ```text
   /volume1/docker/lumanest/secrets/ed25519-private.pem
   ```

   在 NAS 上限制私钥文件权限：

   ```bash
   chmod 600 /volume1/docker/lumanest/secrets/ed25519-private.pem
   ```

3. 复制环境变量模板并填写值：

   ```bash
   cp qweather-token-broker.env.example qweather-token-broker.env
   ```

   - `QWEATHER_KEY_ID`：和风天气凭据 ID。
   - `QWEATHER_PROJECT_ID`：和风天气项目 ID。
   - `QWEATHER_PRIVATE_KEY_FILE`：NAS 私钥的绝对路径。
   - `LUMANEST_SERVICE_TOKEN`：运行 `openssl rand -hex 32` 生成的随机值。
   - `AMAP_WEB_KEY`：高德控制台创建的 Web 服务 Key，仅部署在 NAS。

4. 启动容器：

   ```bash
   docker compose up -d --build
   ```

5. 在 NAS 本机或局域网验证：

   ```bash
   curl http://NAS_IP:8787/healthz
   ```

   成功时只返回：

   ```json
   {"status":"ok"}
   ```

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

绑定 TLS 证书后，再请求：

```text
https://你的域名/healthz
```

确认健康检查成功后，告诉我域名即可。我会继续把 Flutter 从旧的 `X-QW-Api-Key` 改为调用此 JWT 服务，并把服务访问令牌作为本地 Dart define 注入，绝不写入仓库。

## 运维

```bash
# 查看状态与日志（日志不会记录 JWT 或私钥）
docker compose ps
docker compose logs --tail=100 qweather-token-broker

# 更新后重新构建
docker compose up -d --build
```

如果泄露了 `LUMANEST_SERVICE_TOKEN`，生成一个新随机值、更新 NAS 的 `qweather-token-broker.env` 并重启容器即可。若怀疑 Ed25519 私钥泄露，需要在和风控制台删除旧凭据、生成新密钥对并重新上传公钥。
