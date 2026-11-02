# 栖光「野外取景器」设计

## 目标

为已接通 Data Broker 的 Flutter 客户端建立更明确的现场工具感，让用户打开今日页后能快速回答“现在适不适合拍、依据是什么、下一步去哪里”。

## 设计决定

- 保留 Core 1.0 的四个一级入口和全局 AI 入口，不增加新的常驻页面。
- 用暖白、松针绿和环境辅助色建立静态 UI；天气与光线继续由现有 Ambient 层表达。
- 今日页增加品牌锁定区，并把动态判断提升为唯一主标题；标题下明确显示本次快照整理时间。
- 宽屏侧栏显示品牌标记，AI 按钮提供“问栖光”提示；底部导航与路由结构保持不变。
- 所有内容仍来自 `ContextSnapshot`、`SurfaceComposition` 与现有 entry registry；不改 Broker 契约，不新增假数据。

## 影响范围

修改集中在设计 token、共享 stage 品牌组件、今日页首屏和 shell 导航。探索、路线、我的、Provider、缓存和错误降级保持原调用链。

## 验证

- `dart analyze`
- `flutter test`
- `cd services/lumanest-data-broker && npm test`
- Data Broker `/healthz` 返回 HTTP 200
