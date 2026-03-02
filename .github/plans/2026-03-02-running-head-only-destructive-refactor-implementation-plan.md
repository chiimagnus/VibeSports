# Running 头部单信号（破坏性）重构 实施计划

> 执行方式：建议使用 `executing-plans` 按批次实现与验收。

**Goal（目标）:** 将 Running 会话重构为“仅头部检测”链路：只基于头部信号产出 `steps + cadence`，并移除 Running 校准流程。

**Non-goals（非目标）:**
- 不改 Boxing 业务流程与拳击识别逻辑
- 不做向后兼容层（允许删除旧 Running 识别路径/字段/UI）
- 不把 cadence 用于调节跑者动画播放速率（动画速率固定）

**Approach（方案）:**
- 在 Running 领域新增头部观测模型（`noseY + faceHeight + confidence`）与事件检测器（上/下相位 + 迟滞 + 最小步间隔）。
- 在 Service 层新增 Running 专用头部 Vision 检测（人脸框高度 + 鼻子位置），并由 `CameraSession` 按 exercise 模式切换分析管线（Running 头部、Boxing 姿态）。
- 在 ViewModel 层重写 Running 状态机为 `idle/running`，删除校准链路与旧手臂计步依赖；输出收敛到 `steps + cadence`。
- 在渲染层固定动画播放速率，保留 cadence 作为指标和前进驱动，不再参与动画速度映射。

**Acceptance（验收）:**
- Running `start` 后立即进入可运行态（无 Running calibrating overlay / 文案 / 状态依赖）。
- Running 只在头部观测有效时计步；一次 `nose.y` 的“上下”计 1 步。
- `cadence` 来自步间隔（平滑型），并满足“丢脸后 hold 再 decay 到 0”。
- UI 不再展示 Running 速度指标（km/h），仅展示步数与步频。
- 跑者动画不再随 cadence 改变播放速率。
- Boxing 主流程保持可用（校准与出拳逻辑不回退）。

---

## P1（最高优先级）：建立 Running 头部识别核心模型

### Task 1: 新建 Running 头部观测与简化快照模型

**Files:**
- Create: `VibeSports/Models/Running/RunningHeadObservation.swift`
- Modify: `VibeSports/Models/Running/RunningMetrics.swift`

**Step 1: 实现功能**
- 在 `RunningHeadObservation` 中定义 Running 需要的最小输入：`noseY`、`faceHeight`、`confidence`、`isDetected`。
- 将 `RunningMetricsSnapshot` 收敛为 Running 对外最小输出：`steps`、`cadenceStepsPerSecond`、`cadenceStepsPerMinute`（可选保留 `isHeadTracked` 供 UI 状态展示）。
- 删除/移除 `movementQualityPercent`、`speedMetersPerSecond`、`speedKilometersPerHour`、`isCloseUpMode`、`shoulderDistance` 等 Running 旧输出字段。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Expected: 编译通过（此时允许测试暂未全绿，后续任务补齐）

---

### Task 2: 新建头部步事件检测器（上/下相位 + 迟滞）

**Files:**
- Create: `VibeSports/Models/Running/HeadBobStepDetector.swift`

**Step 1: 实现功能**
- 使用归一化信号 `normalizedNoseY = noseY / max(faceHeight, ε)`。
- 建立有限状态机（如 `seekingPeak` / `seekingValley`），通过“上下相位切换”触发步事件。
- 引入关键参数：`minAmplitudeRatio`（相对头高阈值）、`hysteresisRatio`、`minStepInterval`、`minConfidence`。
- 明确计步语义：一次完整“上下”输出 1 次 `StepEvent`。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/RunningMetricsTests`
- Expected: 先观察编译与基础测试可执行；该命令在 Task 12 重写测试后必须 PASS

---

### Task 3: 重写 RunningMetrics 为“头部计步 + cadence 估计”

**Files:**
- Modify: `VibeSports/Models/Running/RunningMetrics.swift`
- Modify: `VibeSports/Models/Running/CadenceModel.swift`

**Step 1: 实现功能**
- `RunningMetrics` 输入改为 `RunningHeadObservation?`，移除对 `Pose` 与手臂相位检测的依赖。
- 保留 `CadenceModel` 作为步频平滑核（平滑型），将默认参数调到“约 3–5 步平滑”。
- 增加“丢脸容错”状态：
  - `hold` 窗口内不立即清零 cadence
  - 超过 hold 后按衰减策略回落到 0
- `RunningMetrics` 只维护：步数、cadence、跟踪状态，不再负责速度指标。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Expected: 编译通过

---

## P2：Service 层改造为 Running 头部专用输入

### Task 4: 新增 Running 头部 Vision 检测服务

**Files:**
- Create: `VibeSports/Services/Running/RunningHeadDetector.swift`

**Step 1: 实现功能**
- 新增 `RunningHeadDetecting` 协议与默认实现 `RunningHeadDetector`。
- 检测策略：
  - 用 `VNDetectFaceRectanglesRequest` 获取 `faceHeight`
  - 用人脸关键点（鼻子）或等价稳定鼻部定位得到 `noseY`
- 输出 `RunningHeadObservation`；无有效人脸时输出 `nil`（由上层执行 hold/decay）。
- 约束：Running 链路不依赖手臂/肩/腿关键点。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Expected: 编译通过

---

### Task 5: 扩展 CameraSession，按模式发布 Running 头部流

**Files:**
- Modify: `VibeSports/Services/CameraSession.swift`

**Step 1: 实现功能**
- 在 `CameraSession` 新增分析模式（建议）：`runningHeadOnly` / `boxingPose`。
- 新增 `runningHeadPublisher`（`AnyPublisher<RunningHeadObservation?, Never>`）与对应回调。
- `OutputHandler` 根据当前模式执行检测：
  - Running：仅跑 `RunningHeadDetector`
  - Boxing：保持原 `PoseDetector`
- `stop()` 时清理并复位模式，避免跨会话残留。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Expected: 编译通过；切换 Running/Boxing 不崩溃

---

## P3：ViewModel 破坏性重写（去校准、去旧输入）

### Task 6: 重写 RunningSessionViewModel 为 idle/running 双态

**Files:**
- Modify: `VibeSports/ViewModels/Running/RunningSessionViewModel.swift`

**Step 1: 实现功能**
- 删除 Running `calibrating` 状态与 `UpperBodyCalibration` 依赖。
- `start()` 直接进入 `.running`；`stop()` 归零 steps/cadence 并重置检测器。
- `ingest(...)` 签名改为消费 `RunningHeadObservation?`（不再接收 `rawPose/controlPose`）。
- `RunnerMotion` 组装逻辑：
  - `cadence` 使用新指标
  - `forwardInput` 依据 cadence 是否有效
  - 不引入速度指标回填到 UI

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Expected: 编译通过

---

### Task 7: 调整 ExerciseHubViewModel 的会话编排

**Files:**
- Modify: `VibeSports/ViewModels/ExerciseHub/ExerciseHubViewModel.swift`

**Step 1: 实现功能**
- Running `startTapped()`：
  - 直接 `sessionState = .running(kind: .running)`
  - 配置 `cameraSession` 为 `runningHeadOnly`
- Boxing `startTapped()`：保持校准流程，模式设为 `boxingPose`
- 订阅流拆分：
  - Running 消费 `runningHeadPublisher`
  - Boxing 继续消费 `posePublisher`
- 仅在 Boxing 路径上应用 `PoseStabilizer`（Running 不再依赖姿态稳定器）。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Expected: 编译通过；Running/Boxing 切换状态正确

---

## P4：UI 与文案清理（Running 去校准、去速度）

### Task 8: 删除 Running 校准 UI 与入口文案

**Files:**
- Delete: `VibeSports/Views/Running/RunningCalibrationOverlayView.swift`
- Modify: `VibeSports/Views/ExerciseWindow/ExerciseWindowView.swift`
- Modify: `VibeSports/Views/ExerciseHub/ExerciseHubView.swift`
- Modify: `VibeSports/Views/Home/HomeView.swift`

**Step 1: 实现功能**
- 移除 Running 校准 overlay 入口与相关 `if case .calibrating` 分支（保留 Boxing 校准 UI）。
- Running 状态文案改为 head-only（例如“Head Tracking Running”），去掉“calibrate”叙述。
- Home Running 副标题从“Upper-body calibration...”改为“Head-only detection ...”。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Expected: 编译通过；界面不再出现 Running Calibration

---

### Task 9: HUD 指标收敛到 steps/cadence

**Files:**
- Modify: `VibeSports/Views/ExerciseWindow/ExerciseWindowView.swift`
- Modify: `VibeSports/Views/ExerciseHub/ExerciseHubView.swift`

**Step 1: 实现功能**
- Running 顶部状态从 `km/h` 改为 `steps + cadence(spm)`。
- 所有 Running 相关速度展示删干净；保留 Boxing 现有展示不动。

**Step 2: 验证**
- 手动验证：启动 Running，观察 HUD 实时显示步数与步频；停止后清零。

---

## P5：渲染约束落地（不再 cadence→动画速率）

### Task 10: 固定 Runner 动画播放速率

**Files:**
- Modify: `VibeSports/Services/Renderer/RunnerSceneRenderer.swift`

**Step 1: 实现功能**
- 在 `updateRunnerAnimation(...)` 中移除 `cadenceStepsPerSecond -> player.speed` 映射逻辑。
- `slowRunPlayer.speed` / `fastRunPlayer.speed` 固定为常量（建议 `1.0`）。
- 保留 blend（idle/slow/fast）与导航速度逻辑，避免场景移动回退。

**Step 2: 验证**
- 手动验证：快跑/慢跑时动画切换可发生，但单段动画播放速率不再随 cadence 拉伸。

---

### Task 11: 清理调试面板中“动画速率映射”参数

**Files:**
- Modify: `VibeSports/Views/Settings/RunnerTuningDebugView.swift`
- Modify: `VibeSports/Services/Renderer/RunnerSceneRenderer.swift`

**Step 1: 实现功能**
- 删除/隐藏 `Steps / Loop` 与 `Min Rate / Max Rate` 的调参入口与说明文字。
- 保留仍有效的参数（如 `strideLengthMetersPerStep` 用于 cadence->位移速度映射，若仍采用）。

**Step 2: 验证**
- 手动验证：Runner Tuning 页面不再出现“动画播放速率映射”相关项。

---

## P6：删除旧 Running 路径并补测试

### Task 12: 删除旧手臂计步实现与失效测试

**Files:**
- Delete: `VibeSports/Models/Running/RunningStepDetector.swift`
- Modify: `VibeSportsTests/RunningMetricsTests.swift`

**Step 1: 实现功能**
- 移除旧手臂相位检测实现与调用。
- 重写 `RunningMetricsTests` 用例为 head-only 语义（删除 wrist/shoulder close-up 相关断言）。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/RunningMetricsTests`
- Expected: PASS

---

### Task 13: 新增头部计步与 cadence 行为测试

**Files:**
- Create: `VibeSportsTests/HeadBobStepDetectorTests.swift`
- Modify: `VibeSportsTests/RunningMetricsTests.swift`

**Step 1: 实现功能**
- 覆盖关键行为：
  - 规则“上下”波形可稳定累计步数
  - 高频噪声/小振幅不误触发（受 `minAmplitudeRatio` + `hysteresisRatio` 保护）
  - `minStepInterval` 生效，避免连击
  - 丢脸时 `hold` 生效，超时后 `cadence` 衰减到 0

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/HeadBobStepDetectorTests`
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/RunningMetricsTests`
- Expected: PASS

---

## 回归验证（每完成一个优先级分组后执行）

- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`
- Expected: 全部通过；若失败，先确认是否为本次重构影响再定向修复

---

## 提交策略（可选，若需要提交）

- 建议按 Task 粒度原子提交，避免跨任务混合。
- Commit message 使用 Conventional Commits，subject 以 `taskN - ` 开头。
  - 例：`refactor: task6 - rewrite running session to head-only state machine`

---

## 执行顺序建议

1. 先落地 P1/P2（模型与输入管线）再改 P3/P4（状态机与 UI）。
2. P5（渲染约束）与 P6（清理测试）在功能跑通后收尾。
3. 每完成一个 P 组，先跑对应最小验证，再进下一组。
