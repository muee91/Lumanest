# 栖光文档索引与权威规则

> **先读：[`core-1.0-scope.md`](core-1.0-scope.md)**

仓库过去累积了大量阶段性方案。为避免旧 Markdown 重新驱动已经冻结的功能，文档按以下权威级别解释。

## 权威顺序

1. **产品范围权威**：`core-1.0-scope.md`。
2. **强制契约**：当前公开接口契约、隐私/安全边界、当前自动化测试。它们约束“怎么安全实现”，但不能自行扩大产品范围。
3. **当前支持文档**：运维 runbook、数据源说明、当前 UI 清晰度规范、路线 scout 说明。
4. **历史/版本化/审计文档**：`*-v1.md`、`*-v2.md`、`audits/` 以及已经被后续实现替代的设计说明。只用于追溯决策。

发生冲突时，高一级文档优先。历史文档不能恢复 Core 1.0 已冻结或退役的功能。

## 当前阅读路径

- 产品范围：`core-1.0-scope.md`
- AI 回答可读性：`assistant-answer-clarity.md`
- AI 上下文边界：`assistant-context-envelope.md`
- 环境页可读性：`environment-workbench-clarity.md`
- 路线探路：`route-scout-mode.md`
- 生态来源：`ecology-data-sources.md`
- Provider 运维：`provider-operations-runbook.md`
- 可观测性：`operational-observability.md`

## 历史材料处理规则

历史文件默认保留，不批量删除，因为它们仍有架构决策和验收背景价值。但：

- 不把历史数量目标（例如 48 个机会、96 个标签）当作当前交付目标；
- 不因为旧文档出现一个页面/Provider/后台任务就重新实现；
- 任何从历史文档恢复能力的改动，必须先修改 `core-1.0-scope.md`；
- 后续整理时优先合并重复文档，而不是继续新增同主题版本。

仓库中除本文件和 `core-1.0-scope.md` 外的 Markdown，会被标记为“支持性”或“历史/版本化参考”，明确其产品范围权威低于 Core 1.0。
