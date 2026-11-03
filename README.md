# LumaNest · 栖光

栖光——循光而行，择光而栖。

一个以**拍摄决策为第一优先级**的环境感知摄影与探索助手。当前开发范围以
[`docs/core-1.0-scope.md`](docs/core-1.0-scope.md) 为唯一产品范围权威；该文件现记录
2.0 任务优先重构阶段的真实运行面，文件名暂保留以避免历史链接失效。

## 栖光 2.0 · 任务优先重构

当前应用只有三个常驻一级入口，路线作为任务场景进入：

- **此刻**：现在/今天最值得关注的一个拍摄机会。
- **发现**：到达一个区域后，理解这里值得拍、值得看、值得体验什么。
- **我的**：少量真正需要保存的偏好与内容。

路线不是底栏一级入口，而是从出行任务或明确地点进入的全屏行动场景；导航交给外部地图。

出行任务 `TripTask` 统一承载规划、出发、现场、完成和取消状态，当前以本地持久化为主。
AI 可以从明确的目的地请求创建任务，并在地点结果不唯一时要求补充区域。

**栖光 AI** 是全局按需入口，不是第五个常驻 Tab。旧 `/inspiration` 仅保留深链兼容并进入同一 AI 页面。

2.0 仍处于早期重构阶段。Mission API、PostgreSQL 任务事实和独立 Worker 已进入实现，但需要专用 NAS 角色、迁移和真实部署验收；远程推送、服务端业务工具编排、实时语音副驾和新版专业图表仍未交付，不应按已实现能力使用或对外承诺。

当前产品不以 Provider 数量、机会目录数量、模型数量或后台能力数量作为完成度。功能只有在生产入口可达、用户能看懂并能据此行动时才算完成。

## 文档

先读 [`docs/README.md`](docs/README.md)。版本化设计、审计和历史 Markdown 都是支持材料；与当前 2.0 范围冲突时不能恢复已冻结或尚未交付的能力。

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

Debug APK 仍可在本地按需构建。GitHub CI 同时验证 Flutter、服务端测试、Android Debug 构建和 Android Release R8 保留规则；CI 通过仍不替代真机、NAS 和真实天气接口验收。
