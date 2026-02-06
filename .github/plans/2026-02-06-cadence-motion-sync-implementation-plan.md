# 步频同步（Cadence-driven Motion）实施计划

> 执行方式：建议使用 `executing-plans` 按批次实现与验收（每批 2–4 个 task）。

**Goal（目标）:** 优先让 3D runner 的“跑步节奏/步频”与真人动作同步；并用步频推导场景前进速度（A2），避免速度快速打满 `21.6 km/h`。

**Non-goals（非目标）:**
- 不做实时动捕骨骼映射（Vision joints → Runner skeleton/IK）；
- 不追求“真实 km/h 精准”，只要节奏同步、观感合理即可（真实速度后续再校准）；
- 不做设置持久化（暂不写入 SwiftData Settings；全部调参先走 Debug 面板）。

**Approach（方案）:**
- 以现有 `RunningStepDetector` 的 step 事件为基础，估计 cadence（steps/sec、steps/min），并做平滑 + 超时衰减。
- 用 `speedMetersPerSecond = cadenceStepsPerSecond * strideLengthMetersPerStep` 推导“游戏速度”，同时驱动：
  - 场景推进（`travelZ += speed * dt`）
  - 三段动画混合（Idle↔SlowRun↔FastRun，输入 speed）
  - 跑步动画播放速率（输入 cadence；保证“步频”跟随真人）
- 默认假设：`stepCount` 每 +1 就是 1 step（不除以 2）；成人跑步 `strideLengthMetersPerStep` 默认 `1.0m`（可调）。

**Acceptance（验收）:**
- UI 不再在“正常跑步/摆臂”下迅速顶到 `21.6 km/h`（因为不再使用 `RunningSpeedModel` 的固定加速度爬升逻辑）。
- cadence 稳定时：runner 的步频随真人明显变快/变慢（无需相位锁定）。
- cadence 停止（无 step 事件）后：速度与播放速率在合理时间内回落到 idle（无明显抖动/卡顿）。
- Debug 面板可实时调 cadence→speed 映射参数（至少：stride length、cadence smoothing、timeout）。

---

## Plan A（主方案）：Cadence-driven Motion

### P1（最高优先级）：建立 cadence 模型 + 替换速度来源

#### Task 1：新增 `CadenceModel`（纯模型）+ 单测

**Files:**
- Create: `VibeSports/Models/Running/CadenceModel.swift`
- Test: `VibeSportsTests/CadenceModelTests.swift`

**Design:**
- 输入：step 事件时间 `now`（每当检测到 step 时喂入一次）。
- 输出：
  - `cadenceStepsPerSecond`（Double）
  - `cadenceStepsPerMinute`（Double，= *60）
- 配置项建议：
  - `minStepInterval`（过滤过快的噪声，例如 `< 0.15s` 直接忽略）
  - `maxStepInterval`（过慢视为停止/重置，例如 `> 1.5s`）
  - `smoothingAlpha`（EMA 平滑）
  - `timeoutToZero`（无 step 事件多久衰减到 0，例如 `0.8–1.2s`）

**Step 1: 写测试（先失败）**
- cadence 在固定间隔 step（例如 0.5s）时收敛到约 `2 steps/sec`；
- 没有 step 事件超过 `timeoutToZero` 后 cadence 下降到 0；
- 极端间隔（过小/过大）会被过滤/重置，不导致 cadence 爆炸。

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/CadenceModelTests`

**Step 2: 最小实现让测试通过**

**Step 3: 回归测试**
- 预期：PASS

---

#### Task 2：让 `RunningStepDetector` 把 “step 事件” 显式返回给上层

**Files:**
- Modify: `VibeSports/Models/Running/RunningStepDetector.swift`
- Test: `VibeSportsTests/RunningMetricsTests.swift`

**Change:**
- 把 `ingest(...)` 改为返回一个 step 事件（或至少返回 `Bool didCountStep`）。
  - 推荐返回：`StepEvent(intervalSincePreviousStep: TimeInterval?)`
  - `interval` 可以直接用 detector 内部 `lastStepTime` 计算，避免上层重复做时间管理。

**Step 1: 更新/新增测试**
- 保持现有 `test_stepsIncreaseWhenArmPhaseAlternates` 仍能验证 stepCount 增长；
- 增加一个断言：当 step 被计数时，`ingest` 返回非 nil（或 didCountStep == true）。

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/RunningMetricsTests`

---

#### Task 3：`RunningMetrics` 改为 cadence 驱动（替换 `RunningSpeedModel`）

**Files:**
- Modify: `VibeSports/Models/Running/RunningMetrics.swift`
- (Optional delete): `VibeSports/Models/Running/RunningSpeedModel.swift`（若完全不再使用）
- Test: `VibeSportsTests/RunningMetricsTests.swift`

**Change:**
- 从 `RunningMetrics` 移除 `speedModel = RunningSpeedModel()` 路径：
  - 不再用 `isMoving` 布尔 + 固定加速度爬升到 `maxSpeedMetersPerSecond`。
- 新增：
  - `cadenceModel: CadenceModel`
  - `configuration.strideLengthMetersPerStep: Double = 1.0`
- ingest 流程：
  1) 继续计算 `movementQuality`（用于 stepDetector gating）
  2) 调用 `stepDetector.ingest(...)`，若返回 step 事件 → `cadenceModel.ingestStep(now: now, interval: ...)`
  3) 每次 ingest 都调用 `cadenceModel.update(now:)`（用于 timeout 衰减）
  4) `speedMetersPerSecond = cadenceStepsPerSecond * strideLengthMetersPerStep`
  5) 产出 snapshot：`cadenceStepsPerSecond/Minute` + `speedMetersPerSecond/Kmh`

**Test updates（要改的断言口径）:**
- `test_speedIncreasesWhenMovementQualityHigh`：
  - 不再断言 `speedModel` 爬升；改为断言：有规律 step 时 `snapshot.cadenceStepsPerSecond > 0` 且 `speedMetersPerSecond > 0`
- `test_speedDecaysToZeroWhenNoPose`：
  - 改为：无 pose 时 step 不再触发，cadence 超时衰减到 0，speed 也衰减到 0

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/RunningMetricsTests`

---

### P1：把 cadence/speed 送进渲染器，并用 cadence 驱动播放速率

#### Task 4：引入 `RunnerMotion`（跨层 DTO）

**Files:**
- Create: `VibeSports/Models/Runner/RunnerMotion.swift`
- Modify: `VibeSports/Models/Running/RunningMetrics.swift`
- Modify: `VibeSports/ViewModels/RunnerGameViewModel.swift`

**Design:**
- `RunnerMotion` 至少包含：
  - `speedMetersPerSecond`
  - `cadenceStepsPerSecond`
  - （可选）`cadenceStepsPerMinute`
- `RunningMetricsSnapshot` 增加 cadence 字段，并提供 `motion`（或在 ViewModel 里组装 motion）。

**Verify:**
- `xcodebuild ... build` 通过。

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`

---

#### Task 5：`RunnerSceneRenderer` API 改为接收 `RunnerMotion`

**Files:**
- Modify: `VibeSports/Services/Renderer/RunnerSceneRenderer.swift`
- Modify: `VibeSports/ViewModels/RunnerGameViewModel.swift`

**Change:**
- 将 `setSpeedMetersPerSecond(_:)` 替换为：
  - `setMotion(_ motion: RunnerMotion)`
- 渲染侧用 lock 存 `motion`（speed + cadence），避免线程问题。

**Verify:**
- `xcodebuild ... build` 通过

---

#### Task 6：用 cadence 计算跑步动画播放速率（只同步步频）

**Files:**
- Modify: `VibeSports/Services/Renderer/RunnerSceneRenderer.swift`

**Design:**
- 三段动画混合权重仍沿用现有 `RunnerAnimationBlender`（输入 speed）。
- 只对 SlowRun/FastRun 设置 `player.speed`，使步频跟随真人：
  - 需要一个 “动画 loop 含几步” 的参数：`stepsPerLoop`（默认先设 `2`，但必须可调）。
  - 对某个 clip：`rate = cadenceStepsPerSecond * clipDurationSeconds / stepsPerLoop`
  - 然后 clamp（沿用 `RunnerAnimationBlender.Configuration.minPlaybackRate/maxPlaybackRate` 或单独给一套 cadence rate clamp）。
- cadence 为 0 时：rate 回到 1（或 0），并让 idle 权重占主导（靠 blender + speed 归零）。

**Manual verify（跑 App 看观感）:**
- 正常跑：cadence 上升 → 步频变快但不“飞起”
- 放慢/停下：cadence 下降 → 步频变慢并回 idle

---

### P1：把关键参数放进 Debug 调参面板（便于校准）

#### Task 7：新增 cadence→speed / cadence→rate 相关 tuning 参数并可实时调

**Files:**
- Modify: `VibeSports/Services/Renderer/RunnerSceneRenderer.swift`（`Tuning` 扩展字段）
- Modify: `VibeSports/Views/Debug/RunnerTuningDebugView.swift`
- (Optional) Modify: `VibeSports/Services/DebugToolsStore.swift`

**Tuning fields（建议最少集）:**
- `strideLengthMetersPerStep`（默认 `1.0`）
- `stepsPerLoop`（默认 `2.0`）
- `cadenceTimeoutToZero`（默认 `1.0s`，若 cadence 在 renderer/metrics 侧实现 timeout）
- `cadenceSmoothingAlpha`（若 cadence 在 metrics 侧实现平滑，则把该参数放进 `RunningMetrics.Configuration`，并在 Debug 面板联动修改）

**Verify:**
- `xcodebuild ... build`
- Debug 面板调参能立刻改变观感（不重启）

---

### P1：收尾与回归

#### Task 8：更新文档与回归命令

**Files:**
- Modify: `.github/docs/business-logic.md`（补充：速度/动画已改为 cadence 驱动）
- Modify: `.github/plans/1.md`（可选：加一行“动作同步后续见本计划”）

**Verify:**
- Build: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Test:  `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`

---

## 不确定项（执行前如需再确认）

- SlowRun/FastRun 每个动画 loop 里包含几步（默认 `2`；可通过肉眼校准 + Debug slider 解决）
- cadence 的平滑/timeout 应放在 `RunningMetrics` 侧还是 renderer 侧（建议放 `RunningMetrics`，renderer 只做显示层的轻微滤波）

