# 栖光（LumaNest）本地配置与密钥说明

本文只说明本地调试和真机联调所需的配置。密钥、JWT、私钥、截图和日志都不得提交到 Git，也不要直接粘贴到对话中。

## 一、高德地图 Android Key

在高德开放平台创建 Android Key，填写：

- 包名：`com.muee.lumanest`
- 当前 Debug SHA1：`53:6C:6B:58:4A:02:03:44:B2:BA:BC:51:9B:66:AD:4E:99:5B:60:55`

正式发布时必须用发布签名的 SHA1 另建一个 Key；不要把 Debug Key 当成正式 Key 使用。

## 二、和风天气：正式环境使用 JWT

和风天气同时支持 API Key 和 JWT。按照官方推荐及本项目的移动端安全要求，正式环境使用 **JWT**，不把和风天气的 Ed25519 私钥放进 App。

官方认证文档：<https://dev.qweather.com/docs/configuration/authentication/#json-web-token>

### 你需要在和风控制台完成的事情

1. 创建或选择一个和风天气项目，记录该项目的 API Host，例如 `https://abcxyz.qweatherapi.com`。
2. 在本机生成 Ed25519 密钥对：

   ```bash
   openssl genpkey -algorithm ED25519 -out ed25519-private.pem
   openssl pkey -pubout -in ed25519-private.pem > ed25519-public.pem
   ```

3. 打开“控制台 → 项目管理 → 对应项目 → 添加凭据”，认证方式选择“JSON Web Token”，上传 `ed25519-public.pem` 的完整内容。
4. 记录控制台给出的“凭据 ID（Key ID）”和“项目 ID（Project ID）”。
5. 将 `ed25519-private.pem` 保存在后端的密钥管理服务或受限环境变量中；不要上传到代码仓库、云盘公开链接、手机 App、本地 Dart defines 或聊天记录。

### JWT 的固定规则

| 位置 | 字段 | 值 |
| --- | --- | --- |
| Header | `alg` | `EdDSA` |
| Header | `kid` | 和风天气凭据 ID（Key ID） |
| Payload | `sub` | 和风天气项目 ID（Project ID） |
| Payload | `iat` | 当前 UNIX 时间戳减 30 秒 |
| Payload | `exp` | 到期 UNIX 时间戳；最长有效期 24 小时 |

JWT 以 `Authorization: Bearer <JWT>` 请求头发送。Header 和 Payload 是可读的，因此不要加入任何额外敏感数据。

## 三、推荐接入结构

```text
LumaNest App
  → 你的服务端 JWT 端点
  → 服务端使用 Ed25519 私钥签发短期 JWT
  → 和风天气 API
```

App 只需要知道 API Host 和你自己的 JWT 端点；服务端才保存私钥、Key ID 和 Project ID。建议 JWT 的有效期设为 15 分钟，并在到期前由服务端刷新。

> 当前代码中的 `QWEATHER_API_KEY` / `X-QW-Api-Key` 是先前的临时直连适配，**不满足 JWT 正式接入方案**。在进行带真实天气的真机联调前，需要先把客户端切换为调用你的 JWT 服务端端点；不要据此配置或发送私钥。

## 四、我下一步需要你准备什么

你无需把任何私钥、API Key 或 JWT 发给我。所有可配置项统一保存在本机唯一的 JSON 文件 `.secrets/environment.debug.json`；不要再新建第二个 JSON 文件：

```json
{
  "AMAP_ANDROID_KEY": "你的本地高德 Android Key",
  "QWEATHER_API_HOST": "https://你的项目.qweatherapi.com",
  "QWEATHER_KEY_ID": "你的和风天气凭据 ID",
  "QWEATHER_PROJECT_ID": "你的和风天气项目 ID",
  "QWEATHER_TOKEN_ENDPOINT": "https://你的服务域名/v1/qweather/token",
  "LUMANEST_SERVICE_TOKEN": "NAS JWT 服务的访问令牌"
}
```

`QWEATHER_KEY_ID`、`QWEATHER_PROJECT_ID` 和 Ed25519 私钥仅用于 NAS 上的 JWT 服务；Flutter 只读取 API Host、JWT 端点和服务访问令牌。私钥必须独立保存在 `.secrets/qweather/ed25519-private.pem`，不能写入 JSON。`.secrets/` 已被 Git 忽略。启动方式：

```bash
flutter run --dart-define-from-file=.secrets/environment.debug.json
```

构建 Debug APK：

```bash
flutter build apk --debug \
  --dart-define-from-file=.secrets/environment.debug.json
```

## 五、隐私顺序

1. 先展示 App 内的环境数据与定位说明。
2. 用户明确同意后，才请求系统前台定位权限。
3. 高德地图首次开启时，单独展示并记录高德隐私授权，再初始化高德 SDK。
4. 定位、天气和地图权限都可在“我的”页恢复或关闭；后续会加入持久化记录。
