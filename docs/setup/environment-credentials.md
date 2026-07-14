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
  → Broker /v1/context/snapshot
  → Broker 使用 Ed25519 私钥访问和风天气
  → FastAPI 情境规则
  → ContextSnapshotV2
```

新客户端只把 WGS84 坐标、观测时间、路线阶段、意图、语言和契约版本发给 Broker。API Host、私钥、Key ID 和 Project ID 均由服务端使用。`QWEATHER_API_HOST` 与 `QWEATHER_TOKEN_ENDPOINT` 暂时仍注入调试 App，只用于旧 NAS 不支持最小情境契约时的迁移回退；新服务成功返回快照后，App 不会直连和风。

> 当前代码中的 `QWEATHER_API_KEY` / `X-QW-Api-Key` 是先前的临时直连适配，**不满足 JWT 正式接入方案**。在进行带真实天气的真机联调前，需要先把客户端切换为调用你的 JWT 服务端端点；不要据此配置或发送私钥。

## 四、我下一步需要你准备什么

所有可配置项统一保存在本机唯一的 JSON 文件 `.secrets/environment.debug.json`。其中 `AMAP_WEB_KEY`、`QWEATHER_KEY_ID` 和 `QWEATHER_PROJECT_ID` 只供 NAS 部署读取，不能传入 Flutter 构建：

```json
{
  "AMAP_ANDROID_KEY": "你的本地高德 Android Key",
  "AMAP_WEB_KEY": "仅部署到 NAS 的高德 Web 服务 Key",
  "QWEATHER_API_HOST": "https://你的项目.qweatherapi.com（迁移期客户端回退，同时写入 NAS 环境）",
  "QWEATHER_KEY_ID": "你的和风天气凭据 ID",
  "QWEATHER_PROJECT_ID": "你的和风天气项目 ID",
  "QWEATHER_TOKEN_ENDPOINT": "https://你的服务域名/v1/qweather/token",
  "LUMANEST_SERVICE_TOKEN": "NAS JWT 服务的访问令牌",
  "SENTRY_DSN": "可选，Sentry Flutter 项目的 DSN"
}
```

`AMAP_WEB_KEY`、`QWEATHER_KEY_ID`、`QWEATHER_PROJECT_ID` 和 Ed25519 私钥仅用于 NAS 服务；Flutter 只读取经过白名单筛选的客户端字段。私钥必须独立保存在 `.secrets/qweather/ed25519-private.pem`，不能写入 JSON。`.secrets/` 已被 Git 忽略。启动方式：

```bash
tool/flutter_with_environment.sh run
```

构建 Debug APK：

```bash
tool/flutter_with_environment.sh build apk --debug
```

## 五、Android 正式签名

Debug APK 继续使用 Android 调试签名。正式 APK/AAB 必须使用独立的发布签名；项目会在缺少发布签名时主动终止 release 构建，不再回退到 debug 签名。

首次发布前，在本机创建签名库（别名可以保留为 `lumanest`）：

```bash
keytool -genkeypair -v \
  -keystore .secrets/android/lumanest-release.jks \
  -alias lumanest \
  -keyalg RSA -keysize 4096 -validity 10000
```

然后创建被 Git 忽略的 `android/key.properties`：

```properties
storePassword=你的签名库密码
keyPassword=你的密钥密码
keyAlias=lumanest
storeFile=../../.secrets/android/lumanest-release.jks
```

验证签名并取得用于高德正式 Android Key 的 SHA1：

```bash
keytool -list -v -keystore .secrets/android/lumanest-release.jks -alias lumanest
```

发布构建：

```bash
tool/flutter_with_environment.sh build appbundle --release
```

签名库、密码和 `key.properties` 都只保存在本机安全目录并另行加密备份。丢失发布签名后将无法正常更新已发布的 Android 应用。

## 六、隐私顺序

1. 先展示 App 内的环境数据与定位说明。
2. 用户明确同意后，才请求系统前台定位权限。
3. 高德地图首次开启时，单独展示并记录高德隐私授权，再初始化高德 SDK。
4. 定位、天气和地图权限都可在“我的”页恢复或关闭；后续会加入持久化记录。

Android 正式包默认关闭系统应用数据备份，避免位置快照、路线记录和偏好数据进入设备云备份。App 只申请前台精确/粗略定位，不申请后台定位，也不申请修改 Wi-Fi 状态。

## 七、可选崩溃监控

在 Sentry 创建 Flutter 项目后，将项目 DSN 写入唯一配置文件 `.secrets/environment.debug.json` 的 `SENTRY_DSN`。DSN 会随 APK 配置进入客户端，这是 Sentry 的公开项目入口，不是账户 API Token。

未配置 DSN 时，Sentry 完全不初始化。配置后仅发送异常类型、堆栈、App 版本以及系统和设备技术信息；项目明确关闭默认 PII、截图、视图层级、交互记录、网络请求上下文、面包屑和性能追踪。定位、路线和用户收藏不写入崩溃事件。
