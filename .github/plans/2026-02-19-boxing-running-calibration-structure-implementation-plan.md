# 拳击模式（Boxing）+ 运动选择入口 + 跑步校准重构 + 业务目录重排 实施计划

> 执行方式：建议后续使用 `executing-plans` 按批次实现与验收。

**Status（状态）**
- Completed: 2026-02-19
- Verification:
  - `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
  - `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`

**Goal（目标）:**
- 在主窗口开始前让用户选择运动场景（Running / Boxing）。
- 新增 Boxing：以“摄像头大预览 + Debug 叠层”为主，**必须通过上半身校准**才能开始识别。
- Running：**完全重构改造**，并在开始前要求用户手动选择“上半身/全身”校准，**必须通过校准**才能开始。
- 最后按业务逻辑整理目录结构（保持 Views / ViewModels / Models / Services 四层边界）。

**Non-goals（非目标）:**
- P1/P2 不追求高精度动作识别模型；优先“稳定跑通 + 可观测 + 可调参”。
- 不引入第三方 ML 框架；仅基于 Apple Vision 人体关键点与启发式/状态机。
- P1 Boxing 不接入 3D SceneKit 世界（只做摄像头预览与调试 UI）。

**Approach（方案）:**
- 引入“运动场景（ExerciseKind）”与“会话状态（ExerciseSessionState）”概念，主窗口在 Idle 时选择并启动。
- 抽象“校准（Calibration）”为纯 Model 层：输入 `Pose? + now`，输出进度/通过/失败原因与 baseline（尺度、关键点基准）。
- Boxing / Running 各自实现自己的校准规则、处理器（processor）与 debug 输出，但复用相机、PoseDetector、PoseStabilizer。
- 最后做 P3：按业务逻辑重排目录与文件命名，把“入口/会话/校准/处理器”归到对应 Feature 目录中。

**Acceptance（验收）:**
- 选择 Boxing：
  - UI 进入校准态，给出上半身轮廓引导；
  - 校准未通过时不可开始识别；通过后进入识别态；
  - 能稳定产出 8 类拳法事件（按出拳手 + 类型）与计数，并可在 Debug 面板看到“为什么判成这一类”的关键信号。
- 选择 Running：
  - 开始前必须选择校准模式（上半身/全身）并通过校准；
  - 通过后跑步会话正常驱动现有 3D 场景，不回归现有功能（End/Stop、Pose overlay、镜像等）。
- 回归：
  - `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build` 通过
  - `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test` 通过

**Execution Order（执行顺序建议）:**
- 先做 P3（目录/命名重排，降低后续开发时的“边写边搬”摩擦），再做 P0/P1/P2。

---

## P0（基础入口）：主窗口运动场景选择 + 统一会话状态骨架

### Task 0.1: 定义运动场景与会话状态模型

**Files:**
- Create: `VibeSports/Models/Exercise/ExerciseKind.swift`
- Create: `VibeSports/Models/Exercise/ExerciseSessionState.swift`

**Step 1: 实现功能**
- `ExerciseKind`: `.running`, `.boxing`
- `ExerciseSessionState`（建议）：
  - `.idle(selectedKind: ExerciseKind, runningCalibrationMode: RunningCalibrationMode?)`
  - `.calibrating(kind: ExerciseKind, calibrationMode: ...)`
  - `.running(kind: ExerciseKind)`
- 先只把类型“表达清楚”，不在这里塞业务逻辑。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Expected: 编译通过

---

### Task 0.2: 主窗口 Idle UI 增加运动场景选择

**Files:**
- Modify: `VibeSports/Views/ExerciseHub/ExerciseHubView.swift`
- Modify: `VibeSports/ViewModels/ExerciseHub/ExerciseHubViewModel.swift`

**Step 1: 实现功能**
- 在 Idle overlay 中增加一个选择器：
  - Running / Boxing
  - 先只影响“Start 后进入哪个 flow”，不改 Settings 页。
- 当选择 Boxing：Start 后进入 Boxing 校准态（P1 会补完整 UI）。
- 当选择 Running：Start 后进入 Running 校准态（P2 会补完整 UI）。

**Step 2: 验证**
- Run app 手动验证：
  - Idle 时可切换场景；
  - 点击 Start 后状态切换正确（哪怕暂时只显示占位文案）。

---

## P1（Boxing MVP）：上半身强制校准 + 8 类拳法事件与 Debug UI（主窗口）

> 拳法标签（已确认）：
> - `leftStraight` / `rightStraight`
> - `leftHook` / `rightHook`
> - `leftUppercut` / `rightUppercut`
> - `leftOverhand` / `rightOverhand`（下砸拳）

### Task 1.1: 建立 Boxing 的 Model 层（事件、配置、状态机）

**Files:**
- Create: `VibeSports/Models/Boxing/BoxingPunchKind.swift`
- Create: `VibeSports/Models/Boxing/BoxingPunchEvent.swift`
- Create: `VibeSports/Models/Boxing/BoxingConfiguration.swift`
- Create: `VibeSports/Models/Boxing/BoxingPunchDetector.swift`

**Step 1: 实现功能**
- 定义 `BoxingPunchKind`（8 类）、`BoxingPunchEvent`（kind + timestamp + optional debug fields）。
- `BoxingPunchDetector` 以“左右手分别的状态机”工作：
  - 输入：`pose: Pose?`, `baseline: BoxingCalibrationBaseline`, `now: Date`
  - 输出：`BoxingPunchEvent?`
- P1 分类启发式建议（可调参）：
  - 以校准 baseline（肩宽/护脸拳位）归一化阈值
  - 用 wrist 的 `dx/dy`（相对 baseline）与速度峰值来判别：
    - `uppercut`: dy 显著上
    - `overhand`: dy 显著下
    - `hook`: abs(dx) 显著大且 dy 不主导
    - `straight`: 其他情况（以“伸出去但横竖位移不大”为默认）
  - 事件去抖：最小间隔、必须经历 “extend→recover” 或 “peak→return” 才记一次。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Expected: 编译通过

---

### Task 1.2: Boxing 上半身校准（必须通过）

**Files:**
- Create: `VibeSports/Models/Calibration/UpperBodyCalibration.swift`
- Create: `VibeSports/Models/Boxing/BoxingCalibrationBaseline.swift`

**Step 1: 实现功能**
- `UpperBodyCalibration`（纯 Model）：
  - 输入：`pose: Pose?`, `now`
  - 输出：进度（0~1）、当前失败原因（缺失关节/不稳定/距离不合适等）、通过时产出 baseline（肩宽、肩中心、左右拳位等）。
- 通过条件建议（可调参）：
  - 必需关节：双肩 + 双肘 + 双腕（必要时加鼻子用于稳定性提示）
  - 稳定窗口：N 帧内关键点位置变化小于阈值
  - 距离窗口：肩宽落在合理范围（太小=太远；太大=太近出画）
- Boxing 强制校准：校准未通过不进入识别态。

**Step 2: 验证**
- 补一个轻量单测（见 Task 1.4）覆盖“稳定窗口”与“缺失关节”分支。

---

### Task 1.3: Boxing ViewModel（接入 CameraSession.posePublisher）

**Files:**
- Create: `VibeSports/ViewModels/Boxing/BoxingSessionViewModel.swift`
- Modify: `VibeSports/Services/AppDependencies.swift`

**Step 1: 实现功能**
- `BoxingSessionViewModel` 负责：
  - 状态：`.idle / .calibrating / .running`
  - 订阅 `CameraSession.posePublisher`
  - 对 pose 做（可选）`PoseStabilizer`，并把 raw/stabilized 都用于 debug
  - 校准通过后开始 `BoxingPunchDetector`
  - 发布 debug 信息（最近一次 event、每类计数、阈值配置、校准进度/原因）
- 依赖注入：
  - 在 `AppDependencies` 增加 `makeBoxingSessionViewModel` 或提供 Boxing 所需 Service/Clock/Settings 的注入方式（避免 view 里 new）。

**Step 2: 验证**
- Run: `xcodebuild ... build`
- Expected: 编译通过

---

### Task 1.4: Boxing Debug UI（主窗口大预览 + 轮廓引导 + 面板）

**Files:**
- Create: `VibeSports/Views/Boxing/BoxingView.swift`
- Create: `VibeSports/Views/Boxing/BoxingCalibrationOverlayView.swift`
- Modify: `VibeSports/Views/ExerciseHub/ExerciseHubView.swift`

**Step 1: 实现功能**
- `BoxingView`：
  - 全屏 `CameraPreviewView`（使用当前 `CameraSession.captureSession`）
  - 覆盖层：
    - 校准态：显示上半身轮廓（肩线/头部区域/左右拳目标圈）+ 校准进度/提示文案
    - 运行态：显示计数与最近事件（可展开 Debug 面板）
  - Debug 面板建议包含：
    - 当前校准/运行状态
    - 关键关节 raw confidence、stabilized 是否输出
    - 配置阈值滑条（只要能实时生效即可；持久化可放 P1.5 或 P2）
- 在 `ExerciseHubView` 里，当用户选择 Boxing 时主区域显示 `BoxingView`，当选择 Running 时保持现有 `RunnerSceneView`（P2 会重构）。

**Step 2: 验证**
- 手动验证：
  - Boxing 进入校准态，未通过不可开始；
  - 通过后能看到事件与计数变化；
  - Debug 面板能帮助定位是 “Vision 没点” 还是 “阈值/状态机” 问题。

---

### Task 1.5: Boxing 单测（只测纯 Model/分类/校准）

**Files:**
- Create: `VibeSportsTests/UpperBodyCalibrationTests.swift`
- Create: `VibeSportsTests/BoxingPunchDetectorTests.swift`

**Step 1: 实现功能**
- 用合成 `Pose(joints:)` 序列模拟：
  - 稳定 guard → 校准通过
  - 缺失腕/肘 → 校准失败原因正确
  - 左手向上 dy 峰值 → 触发 `leftUppercut`（或最小可测：被归类为 uppercut）
  - 事件去抖：连续帧不应重复计数

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/UpperBodyCalibrationTests`
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/BoxingPunchDetectorTests`
- Expected: PASS

---

## P2（Running 重构）：强制校准（上半身/全身手动选择）+ 体验回归

### Task 2.1: 定义 Running 校准模式与校准 Model

**Files:**
- Create: `VibeSports/Models/Calibration/RunningCalibrationMode.swift`
- Create: `VibeSports/Models/Calibration/FullBodyCalibration.swift`
- Modify: `VibeSports/Models/Calibration/UpperBodyCalibration.swift`

**Step 1: 实现功能**
- `RunningCalibrationMode`: `.upperBody`, `.fullBody`
- `FullBodyCalibration`（纯 Model）：
  - 必需关节：肩/肘/腕 + 髋/膝/踝（按你们实际稳定性可调）
  - 稳定窗口 + 距离窗口（基于肩宽/髋宽/踝距的组合，给出“太近/太远/出画”提示）
- UpperBody / FullBody 都输出 baseline（尺度与关键点基准），供 RunningMetrics 使用（阈值归一化）。

**Step 2: 验证**
- Run: `xcodebuild ... build`
- Expected: 编译通过

---

### Task 2.2: RunningSessionViewModel 重构（替代/拆分 ExerciseHubViewModel 的 Running 部分）

**Files:**
- Create: `VibeSports/ViewModels/Running/RunningSessionViewModel.swift`
- Modify: `VibeSports/ViewModels/ExerciseHub/ExerciseHubViewModel.swift`
- Modify: `VibeSports/Services/AppDependencies.swift`

**Step 1: 实现功能**
- 把 Running 会话逻辑拆到 `RunningSessionViewModel`：
  - 强制校准：Start → calibrating（必须通过）→ running
  - 校准模式由用户在开始前选择（B 选项）
  - 通过校准后才开始 `RunningMetrics.ingest`
- `ExerciseHubViewModel` 作为“主窗口 orchestrator”（选择 ExerciseKind、持有 CameraSession、分发 pose 给 Running/Boxing 子 VM）。

**Step 2: 验证**
- Run: `xcodebuild ... build`
- Expected: 编译通过

---

### Task 2.3: Running UI：开始前必须选择校准模式 + 校准引导叠层

**Files:**
- Modify: `VibeSports/Views/ExerciseHub/ExerciseHubView.swift`
- Create: `VibeSports/Views/Running/RunningCalibrationOverlayView.swift`

**Step 1: 实现功能**
- Idle overlay 增加 Running 的校准模式选择（上半身/全身）。
- Running 校准态：
  - 轮廓引导（上半身 vs 全身两套简化 outline）
  - 进度与失败原因提示
  - 必须通过才能进入 Running 的 3D 场景态

**Step 2: 验证**
- 手动验证：Running 未校准通过时无法进入 3D running；通过后现有 3D 场景与 End 流程正常。

---

### Task 2.4: RunningMetrics 适配校准 baseline（阈值归一化）

**Files:**
- Modify: `VibeSports/Models/Running/RunningMetrics.swift`
- Modify: `VibeSports/Models/Running/RunningStepDetector.swift`

**Step 1: 实现功能**
- 把目前“固定阈值”的部分（movementThreshold、armPhaseThreshold 等）改为：
  - 以 baseline 尺度（肩宽/髋宽等）进行归一化或动态阈值
  - 在校准模式不同（上半身/全身）时选择不同 candidate joints / 权重
- 保持 Model 层不依赖 SwiftUI / Combine。

**Step 2: 验证**
- Run: `xcodebuild ... test -only-testing:VibeSportsTests/RunningMetricsTests`
- Expected: PASS（必要时更新测试数据以适配新阈值机制）

---

### Task 2.5: Running 回归验证（功能不回退）

**Step 1: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`
- 手动验证清单：
  - Pose Overlay / Mirror / Stabilization / Arm Debug Overlay 仍可用
  - Control Mode（camera/keyboard/mixed）仍可用
  - End 按钮结束会话会停止相机并 reset 指标

---

## P3（目录与文件重排）：按业务逻辑重构工程结构

> 建议在 P1/P2 跑通后进行（减少边做边搬家的摩擦）。

### Task 3.1: 建立 Feature 目录骨架（不挪文件，只创建目录）

**Files:**
- Create folders（说明：Xcode 使用 File System Synchronized Group，避免在 `VibeSports/` 下放置 `.gitkeep` 之类占位文件，否则会被当作资源复制进 app bundle；目录会在首次创建 Swift 文件时自然出现）:
  - `VibeSports/Views/Boxing/`
  - `VibeSports/Views/Running/`
  - `VibeSports/ViewModels/Boxing/`
  - `VibeSports/ViewModels/Running/`
  - `VibeSports/Models/Boxing/`
  - `VibeSports/Models/Calibration/`
  - `VibeSports/Models/Exercise/`

**Step 1: 验证**
- Run: `xcodebuild ... build`
- Expected: 编译通过（只加目录不影响）

---

### Task 3.2: 按业务逻辑移动文件并更新 Xcode 工程引用

**Files:**
- Modify: `VibeSports.xcodeproj/project.pbxproj`
- Move（示例，按最终落地调整）：
  - `VibeSports/Views/ExerciseHub/*` 明确为“入口/选择/编排层”
  - `VibeSports/Views/Running/*` 收敛为“跑步专属 UI”
  - `VibeSports/Views/Shared/*` 放置可复用组件（如 `CameraPreviewView`、`PoseOverlayView`）
  - `VibeSports/ViewModels/ExerciseHub/*` 收敛为“入口/选择/编排层 VM”
  - `VibeSports/ViewModels/Running/*` 与 `VibeSports/ViewModels/Boxing/*` 分别承载各自业务逻辑
  - Running/Boxing/Calibration 相关文件移动到各自目录

**Step 1: 实现功能**
- 只做“移动与重命名”，不改逻辑（避免 scope 漂移）。
- 保持每个文件名与主要类型同名。

**Step 2: 验证**
- Run: `xcodebuild ... build`
- Run: `xcodebuild ... test`
- Expected: 全部通过

---

### Task 3.3: 更新文档入口索引（可选但建议）

**Files:**
- Modify: `.github/docs/business-logic.md`
- Modify: `README.md`（如入口变更明显）

**Step 1: 实现功能**
- 在 Capabilities / Entry Index 增加 Boxing 与校准入口文件的索引（保持 3–5 个关键入口）。

**Step 2: 验证**
- 人工检查：链接/路径正确。

---

## 不确定项（执行前最后确认）

1. Running 的“全身校准”通过条件：是否强制要求膝/踝都可见？还是允许缺失腿部时直接失败并提示“退后一步”？
2. Boxing 的 silhouette 引导：是否需要提供镜像提示（用户看到的左右与 `PoseJointName.left/right` 语义不一致时的文案/标记）？
