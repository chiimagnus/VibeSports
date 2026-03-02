# Running 头部单信号（破坏性）重构 实施计划（v2）

> 执行方式：建议使用 `executing-plans` 按批次实现与验收。

**Goal（目标）:** 将 Running 会话重构为“仅头部检测”链路：只基于头部信号产出 `steps + cadence`，移除 Running 校准流程，并保持 Boxing 主流程不回退。

**Non-goals（非目标）:**
- 不改 Boxing 校准/出拳业务逻辑
- 不做 Running 旧识别路径的向后兼容（允许删除旧模型字段与实现）
- 不把 cadence 用于调节动画播放速率（动画播放速率固定）

**Approach（方案）:**
- Running 输入统一收敛为头部观测：`noseX/noseY + faceWidth/faceHeight + confidence + isDetected`。
- 计步采用“位移归一化”而非“绝对位置归一化”：`(noseY - baselineY) / faceHeight`，避免机位/构图漂移误触发。
- Camera 分析链路按模式切换：`runningHeadOnly` / `boxingPose`，并在 OutputHandler 内锁保护模式状态，避免串流污染。
- cadence 采用明确状态机：`tracked -> hold -> decay -> zero`，参数化 `holdDuration` 与 `decayDuration`。
- 对会导致大面积编译断裂的契约变更，按“垂直切片”一次切换（Model + ViewModel + HUD 同批改完再 build）。

**Acceptance（验收）:**
- Running `start` 后直接进入运行态，无 Running calibrating UI/文案/状态依赖。
- Running 步数仅来自头部观测；`nose.y` 完整一次“上+下”计 1 步。
- 丢检后 cadence 先 hold，再按 decay 衰减到 0；静止时也可自然回落。
- Running HUD 仅展示 `steps + cadence(spm)`，不再展示 `km/h`。
- 跑者动画不再随 cadence 改变播放速率；仅保留 idle/slow/fast blend 切换。
- Boxing 保持可用：可校准、可检测拳击事件。

---

## 先决规格（先写死，避免执行期分叉）

### S1. 头部观测模型（RunningHeadObservation）
- 必含字段：`noseX`、`noseY`、`faceWidth`、`faceHeight`、`confidence`、`isDetected`。
- 坐标系：全部使用 Vision 归一化坐标（0...1），在模型注释写清楚。
- `confidence` 语义统一为“鼻子定位置信度”；若仅有人脸框、无鼻子点，则 `isDetected = false`。

### S2. 计步语义（HeadBobStepDetector）
- 一次完整“上+下”计 1 步（事件定义固定）。
- 采用迟滞阈值与最小步间隔：`minAmplitudeRatio`、`hysteresisRatio`、`minStepInterval`、`minConfidence`。
- 核心信号：`normalizedDisplacementY = (noseY - baselineNoseY) / max(faceHeight, ε)`。
- `baselineNoseY` 用低通更新（仅在可跟踪时更新），防止缓慢漂移被当作步态。

### S3. cadence 容错语义（CadenceModel）
- `holdDuration`：丢检后 cadence 保持原值的时间窗。
- `decayDuration`：超出 hold 后线性或指数衰减到 0 的时长（实现时二选一，但要固定）。
- `lostTracking` 与 `noStep` 分开处理，防止“丢脸”和“站着不动”混淆。

---

## P1（最高优先级）：建立 Running 头部识别核心（仅新增，不切断现有链路）

### Task 1: 新增 Running 头部观测模型

**Files:**
- Create: `VibeSports/Models/Running/RunningHeadObservation.swift`

**Step 1: 实现功能**
- 定义 `RunningHeadObservation` 与必要构造（包含 S1 全字段）。
- 添加最小校验（例如 `faceHeight/faceWidth` 下限保护）。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Expected: 编译通过

---

### Task 2: 新增头部步检测器（位移归一化 + 相位状态机）

**Files:**
- Create: `VibeSports/Models/Running/HeadBobStepDetector.swift`
- Create: `VibeSportsTests/HeadBobStepDetectorTests.swift`

**Step 1: 实现功能**
- 实现 `HeadBobStepDetector`（含状态机、迟滞、最小步间隔）。
- 以 `RunningHeadObservation` 为唯一输入；不依赖 `Pose`。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/HeadBobStepDetectorTests`
- Expected: PASS

---

### Task 3: 扩展 CadenceModel 为 hold + decay 状态机

**Files:**
- Modify: `VibeSports/Models/Running/CadenceModel.swift`
- Modify: `VibeSportsTests/CadenceModelTests.swift`

**Step 1: 实现功能**
- 在 `CadenceModel.Configuration` 增加 `holdDuration`、`decayDuration`（替代单一 `timeoutToZero`）。
- 新增 `update(now:isTracking:)`（或等价接口）以显式区分丢检与静止。
- 平滑参数固定为“约 3–5 步响应”的默认值，并在注释说明。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/CadenceModelTests`
- Expected: PASS

---

## P2：Service 层改造（Running/Boxing 分析模式明确隔离）

### Task 4: 新增 Running 头部 Vision 检测服务

**Files:**
- Create: `VibeSports/Services/Running/RunningHeadDetector.swift`

**Step 1: 实现功能**
- 新增 `RunningHeadDetecting` 协议与默认实现 `RunningHeadDetector`。
- 使用 `VNDetectFaceRectanglesRequest` 取人脸框，使用 face landmarks 取鼻子点（无鼻点则视为未检测）。
- 输出 `RunningHeadObservation?`；无有效结果输出 `nil`。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Expected: 编译通过

---

### Task 5: 扩展 CameraSession 为模式化双流发布

**Files:**
- Modify: `VibeSports/Services/CameraSession.swift`

**Step 1: 实现功能**
- 新增 `AnalysisMode`：`runningHeadOnly` / `boxingPose`。
- 新增 `setAnalysisMode(_:)`、`runningHeadPublisher`、`onRunningHead`。
- `OutputHandler` 锁状态中加入当前 mode，按 mode 只执行对应检测器。
- `stop()` 时禁用输出并复位模式，防止跨会话残留。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Expected: 编译通过；切换 Running/Boxing 不崩溃

---

## P3：Running 业务切换（垂直切片，一次切断旧契约）

### Task 6: 重写 RunningMetrics + RunningSessionViewModel（头部输入）

**Files:**
- Modify: `VibeSports/Models/Running/RunningMetrics.swift`
- Modify: `VibeSports/ViewModels/Running/RunningSessionViewModel.swift`
- Create: `VibeSports/Models/Running/RunningHeadSteeringSignal.swift`

**Step 1: 实现功能**
- `RunningMetrics` 输入改为 `RunningHeadObservation?`，使用 `HeadBobStepDetector + CadenceModel`。
- 删除 `UpperBodyCalibration`、`RunningStepDetector`、手臂 movementQuality 依赖。
- `RunningSessionViewModel.State` 改为 `idle/running`。
- `start()` 直接 `.running`；`ingest(...)` 改为消费 `RunningHeadObservation?`。
- 头部转向改为基于 `noseX/faceWidth`（不再依赖 Pose shoulder）。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Expected: 编译通过

---

### Task 7: 调整 ExerciseHubViewModel 的编排与订阅拆分

**Files:**
- Modify: `VibeSports/ViewModels/ExerciseHub/ExerciseHubViewModel.swift`

**Step 1: 实现功能**
- Running `startTapped()`：先 `cameraSession.setAnalysisMode(.runningHeadOnly)`，再进入 `.running(kind: .running)`。
- Boxing `startTapped()`：设为 `.boxingPose`，保持当前校准流程。
- 订阅拆分：Running 订阅 `runningHeadPublisher`；Boxing 订阅 `posePublisher`。
- `PoseStabilizer` 仅用于 Boxing 路径；Running 不再走 pose stabilization。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Expected: 编译通过；Running/Boxing 切换正确

---

## P4：UI/文案收敛（Running 去校准、去速度）

### Task 8: 删除 Running 校准 UI 与校准文案

**Files:**
- Delete: `VibeSports/Views/Running/RunningCalibrationOverlayView.swift`
- Modify: `VibeSports/Views/ExerciseWindow/ExerciseWindowView.swift`
- Modify: `VibeSports/Views/ExerciseHub/ExerciseHubView.swift`
- Modify: `VibeSports/Views/Home/HomeView.swift`

**Step 1: 实现功能**
- 删除 Running 校准 overlay 分支与引用。
- Running 相关文案去掉 “calibrate”，改为 head-only 语义。
- 保留 Boxing 校准文案与行为。

**Step 2: 验证**
- 手动验证：Running 进入后不出现校准遮罩；Boxing 仍显示校准遮罩。

---

### Task 9: HUD 指标切换为 steps + cadence

**Files:**
- Modify: `VibeSports/Views/ExerciseWindow/ExerciseWindowView.swift`
- Modify: `VibeSports/Views/ExerciseHub/ExerciseHubView.swift`
- Modify: `VibeSports/ViewModels/Running/RunningSessionViewModel.swift`

**Step 1: 实现功能**
- Running 状态文本改为 `Running • {steps} steps • {spm} spm`。
- 删除 Running 的 `km/h` 展示与依赖字段。
- `stop()` 后 steps/cadence 清零。

**Step 2: 验证**
- 手动验证：Running 中步数/步频实时变化；停止后清零。

---

## P5：渲染与调参面板清理（去动画速率映射）

### Task 10: 固定 Runner 动画播放速率

**Files:**
- Modify: `VibeSports/Services/Renderer/RunnerSceneRenderer.swift`

**Step 1: 实现功能**
- 在 `updateRunnerAnimation(...)` 中移除 cadence 到 `player.speed` 的映射。
- `idle/slow/fast` 的 `player.speed` 固定常量（`1.0`）。
- 保留速度到 blend 的权重映射；保留 cadence->位移速度映射。

**Step 2: 验证**
- 手动验证：快/慢跑可切换动画段，但单段播放速率不拉伸。

---

### Task 11: 删除动画速率相关死参数（UI + 模型 + 测试）

**Files:**
- Modify: `VibeSports/Views/Settings/RunnerTuningDebugView.swift`
- Modify: `VibeSports/Services/Renderer/RunnerSceneRenderer.swift`
- Modify: `VibeSports/Models/Runner/RunnerAnimationBlender.swift`
- Modify: `VibeSportsTests/RunnerAnimationBlenderTests.swift`

**Step 1: 实现功能**
- 删除 `stepsPerLoop`、`baseSpeedMetersPerSecond`、`minPlaybackRate`、`maxPlaybackRate` 及相关文案/测试。
- `RunnerAnimationBlend` 删除 `playbackRate`（若无其他用途）。
- 仅保留仍有效参数（如 `strideLengthMetersPerStep`、blend 区间参数）。

**Step 2: 验证**
- Run: `rg -n "stepsPerLoop|minPlaybackRate|maxPlaybackRate|baseSpeedMetersPerSecond|playbackRate" VibeSports VibeSportsTests`
- Expected: 仅保留确有用途的引用，不再存在动画速率映射链路

---

## P6：删除旧 Running 路径并补齐测试

### Task 12: 删除旧手臂计步实现并重写 RunningMetricsTests

**Files:**
- Delete: `VibeSports/Models/Running/RunningStepDetector.swift`
- Modify: `VibeSportsTests/RunningMetricsTests.swift`

**Step 1: 实现功能**
- 移除 `RunningStepDetector` 及所有调用。
- `RunningMetricsTests` 全量改为 head-only 语义：计步、hold/decay、噪声抑制、最小步间隔。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/RunningMetricsTests`
- Expected: PASS

---

### Task 13: 全量回归与模式切换冒烟

**Files:**
- Modify: `VibeSports/ViewModels/ExerciseHub/ExerciseHubViewModel.swift`（如需补漏）
- Modify: `VibeSports/Services/CameraSession.swift`（如需补漏）

**Step 1: 实现功能**
- 补齐 Running/Boxing 切换边界：start/stop/重复 start/窗口关闭后的状态恢复。
- 确认不会出现 mode 残留导致的错误流订阅。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`
- Expected: 全部通过

---

## 执行顺序建议（强约束）

1. 先做 P1/P2（输入链路成型）再做 P3（业务切换）。
2. P3 必须一次完成 Task 6 + Task 7 再提交，避免中间态编译失败。
3. P4 在 P3 后立即做，确保 UI 不引用已删除字段。
4. P5 完成后必须跑 `rg` 死引用检查，避免“删 UI 未删底层”。
5. P6 收尾做全量 build/test。

---

## 提交策略（可选）

- 建议按 Task 粒度原子提交，避免跨任务混合。
- Commit message 采用 Conventional Commits，subject 以 `taskN - ` 开头。
  - 例：`refactor: task6 - switch running metrics/session to head-only pipeline`

