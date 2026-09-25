# 共享契约

这里放的是一份**跨语言契约的事实来源**。同一条规则此前在三种语言里各写一遍，
靠注释互指，任何一方单独演进都不会在本地报错，只会在另一台设备上变成"上游异常"。

| 文件 | 作用 | 谁读它 |
| --- | --- | --- |
| `context-v5.snapshot.golden.json` | 一份真实部署产出的 V5 响应（无坐标、无地名，见 AGENTS.md §12.1） | Context 服务、Broker 代理、Flutter 解析器 |
| `context-v5.policy.json` | 三边必须相等的数字与集合 | 同上 |

## 为什么必须有

`services/lumanest-context-service/app/v5.py`、`services/lumanest-data-broker/src/context/proxy.mjs`
和 `lib/src/infrastructure/context/data_broker_context_repository.dart` 都做**双向严格**的
键集合校验：字段数与允许集合都要相等。所以服务端新增一个字段，若 broker 与客户端不同步修改，
App 会把整个合法响应判为不可用。这条约束只能靠"同时改三处 + 三处都被测到"来保证。

## 怎么改

1. 改服务端投影，同时更新这里的 golden（用一次真实响应覆盖最省事）。
2. 三边各自的契约测试会立刻红：`tests/test_v5_contract_golden.py`、
   `test/context-contract-golden.test.mjs`、`test/contract/context_v5_contract_test.dart`。
3. 三个套件在 CI 里已经都要过，`contract-drift` 作业另外校验 `catalog/*.json` 生成的三份镜像没被落下
   （`python3 tool/generate_catalog.py --check`）。

`policy.json` 里的数值只有一份是对的：`interruptLeadLimitSeconds` 对应
`INTERRUPT_LEAD_LIMIT`（Python）、`entryNotificationLeadLimit`（Dart）、
`NOTIFICATION_LEAD_LIMIT_MS`（Broker）；`baseSurfaces` / `safetyExtraSurfaces` 对应
`BASE_SURFACES`（Python）与 `entryBaseSurfaces` / `entrySafetySurfaces`（Dart）。
