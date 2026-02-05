# 2026-02-05 MVVM 架构重构计划（VibeSports）

目标：将当前项目重构为清晰的 **MVVM + 协议驱动 + 依赖注入** 结构（本 App **只做 macOS**），做到 View 仅负责 UI/交互，业务逻辑集中在 ViewModel，基础设施集中在 Service，并把当前 View 内的持久化（`@AppStorage`）迁移到 **SwiftData**。

> 约束：只支持 **macOS 14+**；不引入单例（`shared`）；不在 View 里直接访问数据库/持久化；Model/Domain 不引用 SwiftUI / Combine；尽量小步提交、保证每一步都能编译/测试通过。

---

## 0. 现状盘点（已确认）

- `Features/RunnerGame/*` 目前将“会话状态 + 业务逻辑 + 服务编排”放在 `RunnerGameSession: ObservableObject` 内，并由 View 直接持有与调用。
- `RunnerGameHomeView` / `RunnerGameSessionView` 在 View 内直接使用 `@AppStorage` 保存体重与 Debug 开关（持久化耦合到 UI 层）。
- Domain（`Domain/Running/*`、`Core/Time/*`、`Renderer/*`）整体较干净，可保留为独立层，但需要更清晰的边界与注入方式。

---

## 1. 目标分层与目录结构（重构后的落点）

### App / Composition Root

- `VibeSportsApp` 负责：
  - 初始化 SwiftData `ModelContainer`
  - 创建 `AppDependencies`（或 `DependencyContainer`）
  - 注入到根视图（推荐通过 SwiftUI `Environment` 注入，避免层层参数透传）

### Feature（以 RunnerGame 为例）

```
Features/RunnerGame/
├── Views/
│   ├── RunnerGameHomeView.swift
│   ├── RunnerGameSessionView.swift
│   └── Components/...
├── ViewModels/
│   ├── RunnerGameHomeViewModel.swift
│   └── RunnerGameSessionViewModel.swift
├── Models/
│   └── RunnerGameUIState.swift   (仅 UI 所需的轻量模型，可选)
└── Services/
    ├── RunnerGameSessionEngine.swift (编排摄像头/姿态/指标/渲染)
    └── Protocols.swift               (该 Feature 依赖的协议定义)
```

### Domain / Core / Services / Renderer

- `Core/`：纯工具/抽象（如 `Clock`、依赖容器定义、通用错误类型）。
- `Domain/`：纯业务计算（如 `RunningMetrics`）。**不引用 SwiftUI / Combine / AVFoundation / Vision**。
- `Services/`：系统能力/IO（Camera、Vision PoseDetector、Settings 存取）。
- `Renderer/`：SceneKit 渲染（保持为可注入 service）。

---

## 2. 依赖注入与协议驱动（先定协议，再落实现）

### 2.1 AppDependencies 扩展（建议方向）

把当前 `AppDependencies(clock:)` 扩展为清晰的“工厂/仓库”集合，例如：

- `clock: any Clock`
- `settingsRepository: any SettingsRepository`
- `cameraSessionFactory: () -> any CameraSessionProtocol`
- `poseDetectorFactory: () -> any PoseDetecting`（可选；也可由 CameraSession 内部管理）
- `sceneRendererFactory: () -> RunnerSceneRenderer`

> 原则：ViewModel 依赖协议；具体实现放在 `.live()`，测试放在 `.test(...)`。

### 2.2 关键协议（建议最小集合）

- `SettingsRepository`：读取/更新用户体重、Debug 开关等（SwiftData 实现 + InMemory/Fake 实现）。
- `CameraSessionProtocol`：抽象 `state`、`captureSession`、以及“pose 输出”的通道（Combine publisher 或 async stream 二选一）。
- `RunnerSceneRendering`（可选）：抽象 `setSpeedMetersPerSecond` / `reset`，让 ViewModel 不直接依赖 SceneKit 类型。

---

## 3. SwiftData 设置持久化（替换 @AppStorage）

### 3.1 数据模型

- 新增 `@Model`：`AppSettings`
  - `userWeightKg: Double`
  - `showPoseOverlay: Bool`
  - `mirrorPoseOverlay: Bool`
  - 采用“单行表”策略：保证始终只有 1 条记录（首次启动创建默认值）。

### 3.2 Repository

- `SwiftDataSettingsRepository`：封装 `ModelContext` 的查询/更新细节。
- ViewModel 只调用 repository，不接触 `ModelContext`。

### 3.3 迁移策略

- 第一阶段：保留旧 key 的读取（`runner.userWeightKg` 等）作为“只读迁移源”，首次启动写入 SwiftData 后就不再依赖 `@AppStorage`。
- 第二阶段：删掉 View 内所有 `@AppStorage`，并清理旧 key 的读写路径。

---

## 4. RunnerGame MVVM 重构（核心）

### 4.1 RunnerGameHomeViewModel

- 状态：
  - `userWeightKg`（来自 SettingsRepository，可编辑）
  - `isPresentingSession`（纯 UI 状态）
- 行为：
  - `load()`：读取设置
  - `updateWeight(_:)`：写入设置（带简单校验/边界限制）

### 4.2 RunnerGameSessionViewModel

- 状态：
  - `cameraState`（从 CameraSession 派生）
  - `latestPose`
  - `metrics: RunningMetricsSnapshot`
  - `showPoseOverlay` / `mirrorPoseOverlay`（来自设置，可切换）
- 行为：
  - `start()`：启动 camera session，开始消费 pose，驱动 `RunningMetrics` 与 `sceneRenderer`
  - `stop()`：停止 camera、重置渲染与指标
  - `updateWeight(_:)`：运行中修改体重用于热量计算

> `RunnerGameSessionEngine` 建议承载“pose → metrics → renderer”的纯编排逻辑，ViewModel 只负责把它作为一个依赖来驱动。

---

## 5. Service / Renderer 解耦整理

- `Pose`/`PoseJointName`/`PoseJoint` 更像 Domain Model：从 `Services/Pose/Pose.swift` 移到 `Domain/Pose/*`（或 `Domain/Running/Models/*`），让 `RunningMetrics` 只依赖 Domain。
- `CameraSession`：
  - 保留作为 Service，但将 pose 输出改为可测试的抽象通道（publisher/stream）
  - `OutputHandler` 中的 `PoseDetector` 改为注入 `PoseDetecting`，便于单元测试与替换实现
- `RunnerSceneRenderer`：
  - 可保留现状，但建议通过协议 `RunnerSceneRendering` 隔离 ViewModel 与 SceneKit 细节

---

## 6. 测试与验收

### 6.1 现有测试保持绿

- `VibeSportsTests/ClockTests.swift`
- `VibeSportsTests/RunningMetricsTests.swift`
- `VibeSportsTests/TerrainSegmentPoolTests.swift`

### 6.2 新增测试（建议）

- `RunnerGameHomeViewModelTests`：
  - 读取/更新体重会写入 SettingsRepository
- `RunnerGameSessionViewModelTests`：
  - fake camera pose 流输入 → metrics/steps/calories 更新
  - stop 会重置 metrics 与 renderer
- `SwiftDataSettingsRepositoryTests`（in-memory container）：
  - 首次创建默认 settings
  - 更新字段可持久化读取

### 6.3 验收标准

- View 中不再出现 `@AppStorage` / `ModelContext` 访问
- ViewModel 不直接依赖具体 Service 类型（依赖协议）
- `xcodebuild test` 通过（或 Xcode Test 通过）
- RunnerGame 功能行为不变：开始→运行→结束流程可用
