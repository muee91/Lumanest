# LumaNest · 栖光

栖光——循光而行，择光而栖。

一个以**拍摄决策为第一优先级**的环境感知摄影与探索助手。当前开发范围以
[`docs/core-1.0-scope.md`](docs/core-1.0-scope.md) 为唯一产品范围权威。

## Core 1.0

当前应用只有四个常驻一级入口：

- **今日**：现在/今天最值得关注的一个拍摄机会。
- **探索**：到达一个区域后，理解这里值得拍、值得看、值得体验什么。
- **路线**：去一个目的地途中需要提前知道的摄影、天气、限制与补给信息；导航交给外部地图。
- **我的**：少量真正需要保存的偏好与内容。

**栖光 AI** 是全局按需入口，不是第五个常驻 Tab。旧 `/inspiration` 仅保留深链兼容并进入同一 AI 页面。

当前产品不以 Provider 数量、机会目录数量、模型数量或后台能力数量作为完成度。功能只有在生产入口可达、用户能看懂并能据此行动时才算完成。

## 文档

先读 [`docs/README.md`](docs/README.md)。版本化设计、审计和历史 Markdown 都是支持材料；与 Core 1.0 冲突时不能恢复已冻结能力。

## 验证

```bash
flutter analyze
flutter test
./tool/flutter_with_environment.sh test
```

真实 Broker 集成测试使用：

```bash
./tool/flutter_with_environment.sh test-configured <测试路径>
```

真机运行使用：

```bash
./tool/flutter_with_environment.sh run
```

Debug APK 仍可在本地按需构建，但当前 GitHub CI 的职责是 Flutter analyze/test 与服务测试，不把远端 APK artifact 当作发布闭环。
