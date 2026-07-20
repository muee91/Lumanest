# 栖光 Ambient V2 动态环境背景吸收技术规范

**文档版本：** 1.0
**日期：** 2026-07-19
**状态：** 已落地（V2 默认接入 Today；预设仍按 draft 管理）
**适用范围：** Flutter App 的「今日」环境氛围层
**参考样本：** React Bits `Grainient` 与 Background Studio
**实现原则：** 吸收视觉算法类别、参数组织方法和调试工作流；不引入 React、OGL、WebView，也不逐行移植 React Bits Shader。

---

## 0. 决策结论

栖光已经具备 Flutter 原生环境 Shader、确定性天气映射、机会色彩增强、雨雪/雷暴图层和动效降级，不需要新建另一套背景系统。

Ambient V2 应当在现有链路上增量升级：

```text
ContextSnapshot / SkyOpportunityForecast / ProfilePreferences / DeviceEnergy
                                  ↓
                      AmbientVisualMapper
                                  ↓
                   SkyOpportunityAmbientMapper
                                  ↓
                     AmbientRenderingPolicy
                                  ↓
                    AmbientVisualComposition
                                  ↓
       AmbientCanvas → AmbientShaderSurface → lumanest_ambient_v2.frag
                                  ↓
               Rain / Snow / Thunder semantic layers
```

核心边界：

1. 环境事实决定基础视觉状态。
2. 摄影机会只能进行有上限的创意增强。
3. 安全状态出现时，创意增强必须完全退出。
4. AI 不得生成自由 Shader 参数，只能选择已审核预设或在限定范围内微调。
5. 动态背景只提供氛围，不承担天气事实、风险或机会质量的完整表达。
6. 非「今日」页面不得保留隐藏运行的环境 Shader。

---

## 1. 现有实现基线

### 1.1 已存在的工程能力

| 能力 | 当前锚点 | V2 处理 |
|---|---|---|
| App 级背景装配 | `lib/src/app/luma_nest_app.dart` | 保留 |
| 天气、昼夜、场景映射 | `ambient_visual_mapper.dart` | 扩展输出，不替换职责 |
| 摄影机会暖色增强 | `sky_opportunity_ambient.dart` | 保留安全优先和 0.25 上限 |
| 用户偏好、低电量、路由降级 | `ambient_rendering_policy.dart` | 增加质量档和刷新策略 |
| 动画、阵风、雨雪、雷暴 | `ambient_canvas.dart` | 拆分稳定时钟和语义图层 |
| FragmentProgram/Shader 复用 | `ambient_shader_surface.dart` | 保留并增加参数绑定对象 |
| Flutter Runtime Effect | `shaders/lumanest_ambient.frag` | 新建 V2 Shader，保留 V1 回退 |

### 1.2 当前状态流

```text
实时或初始 ContextSnapshot
    ↓
AmbientVisualMapper.resolveSnapshot()
    - weather / dayPhase / scene → palette
    - wind → flowDirection / motionIntensity / gustFactor
    - precipitation → texture type / density
    - cloud cover → cloudOpacity
    - dawn/sunset + clear sky → warmGlow
    ↓
SkyOpportunityAmbientMapper.apply()
    - 有 safetyEventIds → 原样返回基础状态
    - 无安全事件且有机会 → 最多 25% 创意色彩混合
    ↓
AmbientRenderingPolicy.resolve()
    - 用户减少动态/闪烁偏好
    - 设备节能状态
    - 当前路由
    ↓
AmbientCanvas
    - Shader 或静态渐变
    - 雨雪纹理
    - 阵风和雷暴脉冲
```

V2 不得绕过或复制上述状态流。

---

## 2. V2 领域模型

### 2.1 分离“语义状态”和“渲染参数”

`AmbientVisualState` 继续表达天气、时间、场景和机会语义，不直接膨胀为二十多个 Shader uniform。

新增两个中间对象：

```dart
class AmbientVisualComposition {
  const AmbientVisualComposition({
    required this.semanticState,
    required this.field,
    required this.quality,
    required this.transitionDuration,
  });

  final AmbientVisualState semanticState;
  final AmbientFieldParameters field;
  final AmbientQualityTier quality;
  final Duration transitionDuration;
}

class AmbientFieldParameters {
  const AmbientFieldParameters({
    required this.colors,
    required this.timeSpeed,
    required this.colorBalance,
    required this.warpStrength,
    required this.warpFrequency,
    required this.warpSpeed,
    required this.warpAmplitude,
    required this.blendAngleDegrees,
    required this.blendSoftness,
    required this.rotationAmountDegrees,
    required this.noiseScale,
    required this.grainAmount,
    required this.grainScale,
    required this.animateGrain,
    required this.contrast,
    required this.gamma,
    required this.saturation,
    required this.center,
    required this.zoom,
  });

  final List<Color> colors; // 必须为 3 色
  final double timeSpeed;
  final double colorBalance;
  final double warpStrength;
  final double warpFrequency;
  final double warpSpeed;
  final double warpAmplitude;
  final double blendAngleDegrees;
  final double blendSoftness;
  final double rotationAmountDegrees;
  final double noiseScale;
  final double grainAmount;
  final double grainScale;
  final bool animateGrain;
  final double contrast;
  final double gamma;
  final double saturation;
  final Offset center;
  final double zoom;
}

enum AmbientQualityTier {
  full,
  balanced,
  reduced,
  static,
}
```

职责划分：

- `AmbientVisualState`：产品语义和事实映射。
- `AmbientFieldParameters`：纯渲染参数，可插值、可序列化、可校验。
- `AmbientVisualComposition`：一次实际渲染决策。
- `AmbientRenderingPolicy`：决定质量、刷新频率及是否允许动画。

### 2.2 参数必须值相等

上述对象必须实现值相等，避免仅因重新构造对象而触发无意义重绘。颜色数组应使用不可变集合或逐项比较。

---

## 3. 参数体系与产品安全范围

React Bits 参数仅作为命名和调试维度参考。栖光必须使用自己的默认值、映射函数和 Shader 数学实现。

下表是 Ambient V2 第一版工程边界；上线前允许根据真机视觉 QA 收紧，但不得由服务端或 AI 越界。

| 参数 | 常驻环境范围 | 短时机会范围 | 静态/节能处理 |
|---|---:|---:|---|
| `timeSpeed` | 0.08–0.35 | 0.08–0.80 | 0 |
| `colorBalance` | -0.20–0.20 | -0.30–0.30 | 保留静态值 |
| `warpStrength` | 0.30–1.20 | 0.30–1.80 | 0–0.35 |
| `warpFrequency` | 2.5–6.0 | 2.5–7.0 | 保留 |
| `warpSpeed` | 0.20–1.20 | 0.20–1.80 | 0 |
| `warpAmplitude` | 35–90 | 24–90 | 保留 |
| `blendSoftness` | 0.25–0.85 | 0.20–0.92 | 保留 |
| `rotationAmountDegrees` | 80–420 | 80–620 | 0 |
| `noiseScale` | 1.2–2.6 | 1.2–3.2 | 保留 |
| `grainAmount` | 0.015–0.055 | 0.015–0.075 | ≤0.025 |
| `animateGrain` | false | 默认 false | false |
| `contrast` | 0.92–1.12 | 0.92–1.18 | ≤1.05 |
| `gamma` | 0.92–1.08 | 0.90–1.10 | 1.0 |
| `saturation` | 0.72–1.08 | 0.72–1.16 | ≤0.92 |
| `zoom` | 0.88–1.08 | 0.82–1.12 | 保留 |

规则：

- 用户案例中的 `timeSpeed=2.9`、`warpStrength=3.8`、`rotationAmount=730` 仅作为视觉探索样本，不进入生产预设允许范围。
- `blendSoftness=0.91` 可以用于短时特殊机会，但必须经过文字可读性验证。
- 动态颗粒默认关闭；静态颗粒可用于减少色带，但不能形成持续高频闪烁。
- 雷暴亮度脉冲继续由独立语义图层负责，不能通过提高 Grainient 对比度冒充雷电。
- 雨雪继续使用独立图层，Shader 色场只负责环境底色。

---

## 4. 确定性映射规则

### 4.1 权威顺序

```text
安全状态
  > 用户无障碍偏好
  > 设备能源与生命周期
  > 天气事实
  > 昼夜与太阳阶段
  > 地理场景
  > 经审核的摄影机会增强
  > 页面局部动效
```

高优先级状态可以压制低优先级效果，低优先级状态不得反向覆盖事实或安全表现。

### 4.2 环境事实映射

| 输入 | 主要输出 | 约束 |
|---|---|---|
| 风速 | `timeSpeed`、`warpSpeed`、`warpStrength` | 使用分段曲线并限幅，不能线性无限增长 |
| 风向 | `blendAngleDegrees`、流动方向 | 更新时做最短角度插值，避免跨 0° 跳转 |
| 云量 | `blendSoftness`、`saturation`、`contrast` | 云量高时降低饱和与局部对比 |
| 降水 | 冷色修正、语义雨雪图层 | 不用色场代替降水粒子 |
| 昼夜阶段 | 三色组、`gamma`、`colorBalance` | 太阳阶段变化必须平滑过渡 |
| 场景类型 | 第三色与轻微噪声尺度修正 | 只能作为弱修饰，不伪造天气 |
| 安全事件 | 压制机会增强、降低闪烁风险 | 永远优先于创意视觉 |

### 4.3 摄影机会增强

摄影机会增强必须满足全部条件：

1. 机会数据存在且未过期。
2. `presentation.ambientStrength > 0`。
3. 当前无安全事件。
4. 用户未关闭环境背景。
5. 当前路由为 `/today`。

增强边界：

- 保留现有 `ambientStrength ≤ 0.25`。
- 主要改变三色组、暖光位置和极小幅度的运动强度。
- 不改变雨雪类型、云量事实、风向和安全图层。
- “条件有限”不得使用比“较好”更强烈的动态暗示。
- 机会结束或过期后平滑回到天气基础预设，不残留暖色状态。

### 4.4 AI 边界

AI 允许：

- 从已审核 `presetId` 中选择候选；
- 解释当前视觉状态为何变化；
- 在预设声明的 `aiAdjustable` 小范围内建议修正值，最终由本地校验器限幅。

AI 禁止：

- 直接输出完整 uniform 集合并跳过校验；
- 创建运行时 Shader 代码；
- 根据文案情绪覆盖天气或安全状态；
- 每次启动随机生成颜色和速度；
- 用视觉强度暗示未经校准的机会概率。

---

## 5. 预设数据结构

### 5.1 JSON Schema 形态

开发期预设使用本地 JSON，生产构建打包为只读资源；第一版不从服务端动态下载 Shader 或任意参数。

```json
{
  "schemaVersion": 1,
  "id": "sunset_clear_balanced",
  "label": "晴朗日落",
  "semanticTags": ["clear", "sunset"],
  "colors": ["#D6E4E8", "#F3B078", "#C95F5B"],
  "field": {
    "timeSpeed": 0.18,
    "colorBalance": 0.04,
    "warpStrength": 0.82,
    "warpFrequency": 4.4,
    "warpSpeed": 0.72,
    "warpAmplitude": 58.0,
    "blendAngleDegrees": 18.0,
    "blendSoftness": 0.68,
    "rotationAmountDegrees": 280.0,
    "noiseScale": 1.8,
    "grainAmount": 0.035,
    "grainScale": 2.0,
    "animateGrain": false,
    "contrast": 1.02,
    "gamma": 1.0,
    "saturation": 0.96,
    "centerX": 0.05,
    "centerY": -0.04,
    "zoom": 0.94
  },
  "qualityOverrides": {
    "reduced": {
      "timeSpeed": 0.08,
      "warpStrength": 0.35,
      "grainAmount": 0.02
    },
    "static": {
      "timeSpeed": 0.0,
      "warpStrength": 0.0,
      "grainAmount": 0.015
    }
  },
  "transitionMilliseconds": 1800,
  "minTextContrast": 4.5,
  "review": {
    "status": "draft",
    "reviewedAt": null,
    "reviewedBy": null
  }
}
```

### 5.2 第一批预设

只建立能由现有事实可靠触发的预设：

1. `clear_day`
2. `cloudy_day`
3. `rain`
4. `snow`
5. `dust`
6. `clear_dawn`
7. `clear_sunset`
8. `blue_hour`
9. `night`
10. `energy_saver_static`

只有在对应机会数据真实存在、契约稳定并完成视觉审核后，才增加火烧云、银河、极光等机会预设。不存在可靠触发条件的预设不得为了展示效果接入产品。

---

## 6. Shader 实现要求

### 6.1 文件和运行时

建议新增：

```text
shaders/lumanest_ambient_v2.frag
lib/src/shared/widgets/ambient/ambient_field_parameters.dart
lib/src/shared/widgets/ambient/ambient_preset.dart
lib/src/shared/widgets/ambient/ambient_composer.dart
assets/ambient/presets_v1.json
```

保留 `lumanest_ambient.frag` 作为开发期回退，直到 V2 完成真机验收。

### 6.2 独立实现边界

V2 Shader 可以独立实现以下通用视觉技术：

- 三色空间混合；
- 连续噪声驱动的角度扰动；
- 低频正弦域形变；
- 静态细颗粒抑制色带；
- 对比度、Gamma、饱和度后处理；
- 中心和缩放控制。

禁止：

- 复制 React Bits Shader 函数、常量组合或代码结构；
- 将 React Bits 源文件、JSON 导出代码或 OGL 运行时加入仓库；
- 使用 `Grainient` 作为发布组件名或 Shader 文件名；
- 在没有许可证复核结论时对外声称是 React Bits 的 Flutter port。

### 6.3 Uniform 绑定

Uniform 顺序必须由 Dart 端常量或集中绑定函数维护，禁止在多个 Painter 内散落裸索引。

建议：

```dart
abstract final class AmbientUniformIndex {
  static const size = 0;       // vec2
  static const time = 2;       // float
  static const colors = 3;     // 3 × vec4
  // 后续索引只在此文件维护
}
```

要求：

- `FragmentProgram` 每个 Widget 状态只加载一次。
- `FragmentShader` 跨帧复用，只更新 uniform。
- Shader 加载失败时立即使用确定性静态渐变，不显示黑屏。
- 切换预设时插值参数，不销毁和重建 GPU 对象。
- 宽高为零时不绘制。

---

## 7. 动画、生命周期与性能策略

### 7.1 稳定时间源

V2 使用单调递增时间，不能继续使用往返 AnimationController 值作为 Shader 主时钟。往返曲线仅适合局部呼吸或阵风权重。

参数切换采用独立过渡进度：

```text
monotonic shader time + preset interpolation progress + semantic pulse progress
```

三种时间不得混用。

### 7.2 暂停条件

以下任一条件成立时停止连续 Shader repaint：

- App 进入 `inactive`、`paused`、`detached` 或 `hidden`；
- 当前路由不是 `/today`；
- Widget 不可见；
- 用户选择静态背景；
- 系统启用减少动态效果；
- 页面强交互期间进入冻结策略；
- Widget 已 dispose。

恢复时继续单调时间或重新计算相位，但不得瞬间跳到高强度状态。

### 7.3 质量档

| 档位 | 背景更新 | Shader | 天气图层 | 使用条件 |
|---|---|---|---|---|
| `full` | 上限 60 FPS | 完整 | 完整 | 高性能设备、短时机会过渡 |
| `balanced` | 上限 30 FPS | 完整 | 完整 | 默认常驻 |
| `reduced` | 上限 15 FPS | 降低形变和颗粒 | 简化 | 节能、热状态或交互抑制 |
| `static` | 0 FPS | 单帧或渐变 | 无闪烁 | 减少动态、静态偏好、极端降级 |

注意：背景降低到 30/15 FPS 不得降低前景滚动、手势和页面转场的刷新率。

### 7.4 雷暴和无障碍

- `reduceFlashing=true` 时完全禁用雷暴脉冲。
- 雷暴效果不进入基础 Shader，不通过随机高亮提高不可控闪烁频率。
- 系统 `disableAnimations` 必须至少等价于 `static` 或经审核的单帧状态。
- 键盘打开、用户滚动和驾驶场景降低背景运动，不影响安全提示稳定显示。

---

## 8. 开发期 Background Studio

### 8.1 目标

建立栖光自己的参数实验工具，避免通过改代码猜测视觉效果。

第一版可以是仅 Debug/Profile 可进入的 Flutter 页面：

```text
环境 Fixture / 实时 ContextSnapshot
          +
参数滑杆和颜色选择器
          ↓
实时 Ambient V2 预览
          ↓
JSON 导出 / 导入
          ↓
人工审核后进入 assets/ambient/presets_v1.json
```

### 8.2 必须能力

- 选择现有 `ContextFixtures`。
- 在 `full / balanced / reduced / static` 间切换。
- 显示所有参数当前值、允许范围和来源层级。
- 一键恢复预设值。
- 导入、导出单个预设 JSON。
- 并排显示动态版本和静态回退。
- 覆盖浅色/深色文字样本并计算最小对比度。
- 显示当前 FPS、Raster/UI frame time 和 Shader 是否在刷新。
- 标记预设为 `draft`，工具内不得直接标记为已审核。

### 8.3 发布隔离

- 入口只能在非 Release 构建出现。
- Release 构建不得包含编辑、远程代码执行或任意 Shader 导入能力。
- Release 只读取仓库内已经审核的只读预设。

---

## 9. 许可证和来源隔离

React Bits 仓库当前声明 `MIT + Commons Clause`，其中对组件本身、组件集合以及 ported version 的销售、再许可或再分发存在额外限制。

因此本项目采用以下保守策略：

1. 不复制 React、OGL 或 Shader 源码。
2. 不把其组件 JSON 或导出结果提交到栖光仓库。
3. 只记录公开参考链接、观察到的参数维度和通用视觉技术。
4. V2 Shader 从空文件独立编写，并保留设计推导记录。
5. 如果未来准备公开源码、发布 SDK 或对外提供可复用背景组件，发布前必须重新进行许可证审查。
6. 若最终实现被认定为衍生或 ported version，必须在分发前取得明确授权或移除相关实现。

参考：

- `https://github.com/DavidHDev/react-bits`
- `https://github.com/DavidHDev/react-bits/blob/main/LICENSE.md`
- `https://reactbits.dev/tools/background-studio?bg=grainient&timeSpeed=2.9&warpStrength=3.8&blendSoftness=0.91&rotationAmount=730&noiseScale=2.7`

本节是工程风险控制，不构成法律意见。

---

## 10. 分阶段实施

### Phase 0：冻结基线

- 保存当前 V1 在晴天、阴天、雨、雪、日出、日落和夜间的截图。
- 记录至少一台真实 Android 设备上的 GPU/Raster 基线。
- 运行现有 ambient 测试并保持全绿。

### Phase 1：参数对象与预设校验

- 新增 `AmbientFieldParameters`、`AmbientVisualComposition` 和 JSON 解析。
- 建立范围校验和非法预设拒绝测试。
- 现有 V1 Shader 继续渲染，确保本阶段不改变 UI。

### Phase 2：独立实现 V2 Shader

- 新建 `lumanest_ambient_v2.frag`。
- 集中管理 uniform 索引和颜色绑定。
- 保留静态渐变与 V1 Shader 回退开关。
- 补充 Shader 创建、复用、dispose 和加载失败测试。

### Phase 3：Composer 与平滑过渡

- 将事实状态、机会增强、质量策略合成为单个 Composition。
- 使用单调时间源。
- 对颜色、角度和数值参数分别使用正确插值。
- 机会过期、安全事件出现、路由切换时验证状态退出。

### Phase 4：Debug Studio

- 建立本地调参页面。
- 导出首批十个预设。
- 完成文字对比度与动效审核。

### Phase 5：真机验收

- 使用项目环境包装脚本在真实 Android 设备运行。
- 验证后台暂停、低电量、减少动态、滚动抑制和页面切换。
- 对比 V1/V2 截图、录屏和 Flutter DevTools 帧数据。
- 验收通过后再将 V2 设为默认；V1 回退的删除另开任务。

---

## 11. 自动化测试要求

### 11.1 单元测试

- 每种 `WeatherType × DayPhase` 都产生合法参数。
- 所有参数均被限制在产品范围内。
- 风向角跨 359°→1° 使用最短路径插值。
- 安全事件完全压制机会增强。
- 机会增强不改变降水类型、风向和云量语义。
- 过期机会不参与 Composition。
- JSON schemaVersion 不支持时明确拒绝。
- 非法颜色、缺少第三色、NaN、Infinity 和越界值明确拒绝。

### 11.2 Widget 测试

- Shader 跨 rebuild 只创建一次并在 dispose 时释放。
- 静态档无持续 Ticker。
- 路由离开 `/today` 后不保留 AmbientCanvas。
- `disableAnimations`、`reduceMotion`、`reduceFlashing` 行为正确。
- Shader 加载失败显示静态回退，不出现黑屏。
- 滚动和键盘打开时背景进入抑制状态。

### 11.3 Golden 与可读性

至少覆盖：

- 10 个首批预设；
- `full / reduced / static`；
- 晴朗日落机会增强；
- 安全事件覆盖机会增强；
- 浅色和高对比主题文字样本。

文字和主操作控件以主题层保证可读性，环境层不得成为文字色事实源；关键文本最低对比度目标为 4.5:1。

### 11.4 真机验证

- 页面静止 60 秒，确认无异常温升、持续掉帧或内存增长。
- 连续切换天气 Fixture，确认无 Shader 重建和明显跳色。
- 前后台切换，确认后台停止刷新且恢复平滑。
- Today 与其他 Tab 往返，确认非 Today 无隐藏动画。
- 开启系统减少动态效果、App 静态模式和低电量策略分别验证。
- 雨、雪、雷暴与安全内容叠加时确认信息层稳定可读。

---

## 12. 验收标准

只有同时满足以下条件，Ambient V2 才能替换默认 V1：

1. 不引入 React、OGL、WebView 或 React Bits 源文件。
2. 所有视觉参数来自确定性预设和本地校验。
3. 安全状态始终优先于创意增强。
4. 非 Today 页面无 Shader 动画。
5. 静态与减少动态模式无持续 repaint。
6. App 后台无持续背景刷新。
7. Shader 实例跨帧复用，切换预设不重建 GPU 对象。
8. Shader 失败时有可读静态回退。
9. 关键文本对比度达到 4.5:1 目标。
10. 首批预设全部完成 Golden、Widget 和真机审核。
11. 真实 Android 设备上没有相对 V1 明显恶化的交互卡顿、温升或耗电表现。
12. 许可证隔离检查完成，发布包不包含参考项目源文件或可复用 port 组件。

---

## 13. 明确不做

- 不把 React Bits 仓库作为依赖或子模块。
- 不通过 WebView 嵌入 Background Studio。
- 不用循环视频替代动态背景。
- 不让每个页面维护独立背景状态。
- 不让 AI 自由生成视觉参数或 Shader。
- 不一次性接入 Aurora、Silk、Lightfall、Particles、Waves 等多个模型。
- 不为了展示预设而伪造极光、银河、火烧云等机会。
- 不把创意机会颜色用于稳定安全提醒。
- 不在未完成真机验证前删除 V1 回退。

---

## 14. 首个实现任务的最小边界

首个代码任务只完成以下内容：

1. 新增 `AmbientFieldParameters` 和值相等。
2. 新增首批本地预设的数据模型、解析器和范围校验器。
3. 新增 `AmbientComposer`，把现有 `AmbientVisualState` 映射为 V2 参数。
4. 保持当前 V1 Shader 和界面输出不变。
5. 为参数边界、安全优先、机会增强和 JSON 非法输入补齐测试。

该任务已完成，并已继续完成 V2 Shader、运行时接线、生命周期降级和 Debug Studio。参数契约先于 Shader 固定，避免 Shader 反向修改产品语义。

---

## 15. 本次落地记录

已完成：

- `AmbientFieldParameters`、`AmbientVisualComposition` 与值相等。
- 本地十预设 JSON、严格 schema 解析、范围校验和确定性选择。
- `AmbientComposer`，包括天气语义颜色、风向、运动、云量、质量档和安全优先链路。
- 独立实现的 `shaders/lumanest_ambient_v2.frag`，不引入 React/OGL/WebView。
- V2 Shader surface、FragmentProgram/FragmentShader 复用和加载失败回退。
- Today 页运行时接线，非 Today 路由不保留环境层。
- App 生命周期暂停、单调 Shader 时钟、30/15 FPS 参数量化和静态档。
- Debug-only `/ambient-debug` Background Studio，支持 Fixture、质量档、参数滑杆和恢复预设。
- 预设、Composer、Shader surface、App 导航和全量 Flutter 回归测试。

验证结果：

| 验证 | 结果 |
|---|---|
| Ambient 定向分析 | 通过，无 issue |
| Flutter 全量测试 | 516 项全部通过 |
| Debug APK 构建 | 通过，`build/app/outputs/flutter-apk/app-debug.apk` |
| Android 真机安装 | 通过，`com.muee.lumanest` |
| Android 真机前台启动 | 通过，Impeller Vulkan/OpenGLES 正常 |
| V2 Shader Widget 加载 | 通过 |

当前仍保留的发布前工作：预设从 `draft` 提升为 `reviewed` 前，需要完成真机截图、文字对比度、温升/耗电和低电量行为的产品视觉审核；这不影响 V2 的默认技术接入和 V1 静态回退。
