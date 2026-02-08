# VibeSports — business-logic.md

> 面向不读代码的 AI：描述 **WHAT + WHY + WHERE**（业务目标、业务规则、以及“去哪找实现”）。

## 产品概述

VibeSports 是一款 macOS 原生「摄像头跑步游戏」原型：用户点击开始后，App 用摄像头 + Vision 做人体姿态估计，估计 step/cadence/speed，并用这些指标驱动 SceneKit 的无限跑道与 Runner 动画。当前阶段优先级是 **“动作同步感” > “真实速度精度”**。

技术栈：macOS 14+ / Swift 6 / SwiftUI + Combine（状态与事件流）/ Vision（pose）/ AVFoundation（camera）/ SceneKit（渲染）/ SwiftData（设置持久化）。

## 架构分层

- `VibeSports/Views/`：SwiftUI UI（只做展示与交互；不做业务计算）
- `VibeSports/ViewModels/`：会话状态机 + 业务编排（订阅 camera pose，产出 metrics，驱动 renderer）
- `VibeSports/Models/`：纯模型与算法（step/cadence/quality 等；禁止依赖 SwiftUI / Combine）
- `VibeSports/Services/`：副作用与基础设施（Camera、Vision、SceneKit renderer、Settings、依赖注入）

依赖方向：`Views → ViewModels → (Models + Services)`，`Services` 不反向依赖 UI 层。

关键入口/装配：
- App 入口：`VibeSports/Views/VibeSportsApp.swift`
- 根视图：`VibeSports/Views/RunnerGame/RunnerGameView.swift`
- 依赖装配：`VibeSports/Services/AppDependencies.swift`

## 核心业务流程

### 流程 A：开始会话 → 运行循环（pose 驱动场景与动画）

1. 用户在主窗口看到 `Ready` 覆盖层，点击 `Start`（`VibeSports/Views/RunnerGame/RunnerGameView.swift`）。
2. `RunnerGameViewModel.startTapped()` 切换到 running 并启动摄像头（`VibeSports/ViewModels/RunnerGameViewModel.swift`）。
3. `CameraSession` 请求权限、配置采集，并以固定频率处理视频帧；每帧尝试产出 `Pose?`（`VibeSports/Services/CameraSession.swift`、`VibeSports/Services/PoseDetector.swift`）。
4. ViewModel 接收 pose：
   - （可选）做姿态稳定化（`VibeSports/Models/Pose/PoseStabilizer.swift`）
   - `RunningMetrics.ingest(...)` 计算 `stepCount / cadence / speed / movementQuality / closeUpMode`（`VibeSports/Models/Running/RunningMetrics.swift`）
   - 将 `RunningMetricsSnapshot.motion` 送进 renderer（`VibeSports/Services/Renderer/RunnerSceneRenderer.swift`）
5. SceneKit 渲染每帧根据 `RunnerMotion` 更新：
   - cadence→speed 推导、平滑
   - 三段动画混合（Idle/SlowRun/FastRun）+ 基于 cadence 的播放速率
   - 无限跑道推进与 segment 回收（`TerrainSegmentPool`）

### 流程 B：结束会话 → 资源释放与指标归零

1. 用户点击 `End` 或窗口消失触发 stop（`VibeSports/Views/RunnerGame/RunnerGameView.swift`）。
2. `RunnerGameViewModel.stop()`：
   - 停止摄像头采集（`CameraSession.stop()`）
   - 重置渲染器状态（`RunnerSceneRenderer.reset()`）
   - 重置 RunningMetrics 与 UI 指标（`RunningMetrics.reset()`）

### 流程 C：调试与校准（Debug 面板/快捷键）

- 菜单 `Debug` 提供 pose overlay / 镜像 / stabilization / 坐标轴等开关（`VibeSports/Views/Commands/DebugCommands.swift`）。
- Debug 窗口：
  - `Runner Animations`：检查/播放 `Runner.usdz` 内 Skeleton clips（`VibeSports/Views/Debug/RunnerAnimationDebugView.swift`）
  - `Runner Tuning`：实时调 stride、steps/loop、blend 参数等（`VibeSports/Views/Debug/RunnerTuningDebugView.swift`）
- 调参流：`DebugToolsStore.runnerTuning` → 绑定到 `RunnerSceneRenderer.tuning`（`VibeSports/Services/DebugToolsStore.swift`）。

## 模块详情

### 1) 会话状态与 UI 反馈

- 做什么：把 App 体验压缩成 “Ready → Running → Ready”，并把摄像头状态/速度显示在 header。
- 业务规则：
  - 未授权时明确提示系统设置入口。
  - stop 后必须释放摄像头与渲染循环，并清空指标与 pose。
- 关键文件：
  - `VibeSports/Views/RunnerGame/RunnerGameView.swift`
  - `VibeSports/ViewModels/RunnerGameViewModel.swift`
  - `VibeSports/Services/CameraSession.swift`

### 2) Pose 输入：摄像头采集与 Vision 估计

- 做什么：从摄像头帧中输出 `Pose?`（关节坐标 + 置信度）。
- 业务规则：
  - 采样频率固定（当前约 20 Hz），丢帧时“宁可稀疏也不积压”。
  - pose 不可用时输出 nil，后续链路负责衰减到 idle。
- 关键文件：`VibeSports/Services/CameraSession.swift`、`VibeSports/Services/PoseDetector.swift`、`VibeSports/Models/Pose/Pose.swift`

### 3) 姿态稳定化与叠加显示（Debug 可控）

- 做什么：减少 pose overlay 的闪烁与抖动，提升调试可读性。
- 业务规则：
  - 用置信度滞回（on/off threshold）与短暂 hold window 抵抗丢帧。
  - 可通过开关完全关闭稳定化（便于对比）。
- 关键文件：`VibeSports/Models/Pose/PoseStabilizer.swift`、`VibeSports/Views/RunnerGame/PoseOverlayView.swift`
- 单测：`VibeSportsTests/PoseStabilizerTests.swift`

### 4) Running Metrics：step/cadence/speed/movementQuality

- 做什么：把 `Pose?` 转换成可用于渲染与 UI 的 `RunningMetricsSnapshot`。
- 指标口径（当前实现的业务定义）：
  - `step`：`RunningStepDetector.stepCount` 每 +1 记为 1 step（不除以 2）。
  - `cadence`：`CadenceModel.cadenceStepsPerSecond`（并提供 steps/min = *60）。
  - `speed`：`speedMetersPerSecond = cadence * strideLengthMetersPerStep`（用于场景推进与动画混合）。
  - `movementQuality`：动作有效性（0–1），用于 gating step 计数与抑制噪声。
  - `closeUpMode`：用户靠近镜头时（肩宽更大且置信度足够）降低阈值，提升可用性。
- 关键文件：
  - `VibeSports/Models/Running/RunningMetrics.swift`
  - `VibeSports/Models/Running/RunningStepDetector.swift`
  - `VibeSports/Models/Running/CadenceModel.swift`
  - `VibeSports/Models/Runner/RunnerMotion.swift`
- 单测：
  - `VibeSportsTests/RunningMetricsTests.swift`
  - `VibeSportsTests/CadenceModelTests.swift`

### 5) 场景与动画：cadence 驱动的“同步感”

- 做什么：用同一套 cadence→speed 来源同时驱动：
  - 无限跑道推进（`travelZ += speed * dt`）
  - Idle/SlowRun/FastRun 动画混合（按 speed）
  - SlowRun/FastRun 播放速率（按 cadence + steps/loop）
- 业务规则（验收口径）：
  - 正常跑步时不出现“真人慢跑但角色飞奔”的割裂感。
  - 停止动作后，速度与播放速率应在短时间内回落到 idle（非突变）。
  - 场景推进速度与动画节奏必须同源（避免视觉与数值脱节）。
- 关键文件：
  - `VibeSports/Services/Renderer/RunnerSceneRenderer.swift`
  - `VibeSports/Models/Runner/RunnerAnimationBlender.swift`
  - `VibeSports/Services/Renderer/TerrainSegmentPool.swift`
- 单测：`VibeSportsTests/RunnerAnimationBlenderTests.swift`、`VibeSportsTests/TerrainSegmentPoolTests.swift`

### 6) 设置持久化（用户偏好开关）

- 持久化项（当前仅偏好类开关）：
  - 是否显示 pose overlay
  - 是否镜像摄像头预览
  - 是否启用姿态稳定化
- 关键文件：`VibeSports/Services/Settings/`（`AppSettings` + `SwiftDataSettingsRepository`）
- 单测：`VibeSportsTests/SwiftDataSettingsRepositoryTests.swift`

### 7) Runner 资产（Runner.usdz）与可调参

- 做什么：Runner 模型需包含 Skeleton 与 3 个 clip（Idle/SlowRun/FastRun）；调参面板用于现场校准 stride、steps/loop、混合区间与平滑系数等。
- 关键文件：
  - `VibeSports/Resources/Runner.usdz`
  - `scripts/build_runner_usdz.sh`
  - `VibeSports/Views/Debug/RunnerTuningDebugView.swift`
  - `VibeSports/Services/DebugToolsStore.swift`

## 当前状态与待办

### 已完成

- [x] 会话开始/结束：停止检测并释放摄像头资源（`RunnerGameViewModel.stop()`）。
- [x] cadence 驱动的 motion：step→cadence→speed，并用于场景推进 + 动画混合 + 播放速率。
- [x] Debug 能力：pose overlay / 镜像 / stabilization 开关；Runner clip 检查；Runner tuning 实时调参。
- [x] SwiftData 设置持久化（含 legacy UserDefaults best-effort seed）。

### 进行中

- [ ] 暂无（以 `.github/plans/` 为准）。

### 已知问题 / 技术债

- Step 检测当前主要依赖手腕相位差（`RunningStepDetector`），对“手不摆臂/姿态不标准”不鲁棒。
- speed 目前是 cadence×stride 的“游戏速度”，stride 默认值需要靠调参/校准，不代表真实 km/h。
- Runner tuning 目前不持久化（重启会回到默认）。

### 下一步计划（建议，未开始）

- 优化 step/cadence 稳定性（结合腿部关节、更多 gating、或改进 close-up 策略）。
- 引入更多“短运动”模式（跳绳/开合跳/深蹲等），并提供明确的开始/计次/结束体验。
- 将 Runner tuning（stride、steps/loop、blend 参数）做可选持久化，便于不同用户快速复用。

## 设计决策记录

### 决策 1：用 cadence 驱动速度与动画（而不是固定加速度爬升）

- 背景：固定加速度会导致速度很快顶到上限，真人节奏变化也难以同步。
- 决定：以 step 事件估计 cadence，并用 cadence 同时驱动 speed、场景推进与动画播放速率。
- 相关实现：`VibeSports/Models/Running/CadenceModel.swift`、`VibeSports/Models/Running/RunningMetrics.swift`、`VibeSports/Services/Renderer/RunnerSceneRenderer.swift`

### 决策 2：Step 定义先用“摆臂相位变化”作为 MVP

- 背景：Vision 上半身关节更稳定，MVP 阶段先要一个可用的节奏输入。
- 决定：以左右手腕 y 差的相位变化计 step，并用 movementQuality 做 gating。
- 相关实现：`VibeSports/Models/Running/RunningStepDetector.swift`

### 决策 3：Debug 调参实时生效，但不做持久化

- 背景：当前重点是“同步感”快速迭代；持久化会增加迭代成本与迁移复杂度。
- 决定：Runner tuning 通过 `DebugToolsStore` 绑定到 renderer，即时生效；未来再决定是否进入 Settings。
- 相关实现：`VibeSports/Services/DebugToolsStore.swift`、`VibeSports/Views/Debug/RunnerTuningDebugView.swift`

## 构建与测试

- 打开工程：`open VibeSports.xcodeproj`
- Build：`xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Test：`xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`
- 单测示例：`xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/RunningMetricsTests`
