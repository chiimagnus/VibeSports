# Pose Stabilization（骨骼闪烁修复）实施计划

> 执行方式：建议使用 `executing-plans` 按批次实现与验收。

**Goal（目标）:** 在上半身 close-up 场景下，显著降低手腕/肘关节骨骼叠加的闪烁与断线。

**Non-goals（非目标）:**
- 不替换 Apple Vision 姿态模型（继续使用 `VNDetectHumanBodyPoseRequest`）。
- 不做 ROI 裁剪/输入方向大改（后续如仍需再做）。

**Approach（方案）:**
- 引入 `PoseStabilizer`：对每个关节做“滞回阈值 + 短时保留 + 低通滤波（EMA）”的时序稳定。
- 先仅影响骨骼叠加（overlay path），保留 RunningMetrics 继续消费原始 pose；通过 Debug 开关做 Raw/Stabilized 对比。

**Acceptance（验收）:**
- 开启 `Debug → 骨骼叠加` 时，手腕/肘的点线在举手/快速摆动时不再频繁消失（肉眼可见明显改善）。
- `Debug → Pose Stabilization` 开关可即时切换 Raw/Stabilized 表现。
- 单元测试覆盖：滞回不抖动、短时保留生效、滤波平滑输出。
- 通过：`xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`

---

## Plan A（主方案）

### P1：模型层稳定器

### Task 1: 新增 `PoseStabilizer`

**Files:**
- Create: `VibeSports/Models/Pose/PoseStabilizer.swift`
- Test: `VibeSportsTests/PoseStabilizerTests.swift`

**Step 1: 写失败用例**
- 关节置信度在 `onThreshold/offThreshold` 附近波动时，visible 状态不应每帧切换。
- measurement 短暂缺失时，在 hold window 内仍输出上一次关节。

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/PoseStabilizerTests`

Expected: FAIL

**Step 2: 最小实现**
- 实现 per-joint 状态：`isVisible / lastSeenAt / filteredLocation`
- 实现：滞回阈值 + hold-last + EMA 滤波

**Step 3: 测试通过**

---

### P1：Debug 开关与 UI 接入

### Task 2: 增加 Debug 开关（Pose Stabilization）

**Files:**
- Modify: `VibeSports/Views/App/DebugFocusedValues.swift`
- Modify: `VibeSports/Views/App/DebugCommands.swift`
- Modify: `VibeSports/Views/RunnerGame/RunnerGameView.swift`

**Step:**
- 添加 `FocusedValues.poseStabilizationEnabled`（`Binding<Bool>`）
- Debug 菜单中加入 Toggle（建议快捷键 `⌘⇧S`）
- `RunnerGameView` 将 focused binding 与 `RunnerGameViewModel` 绑定

Verify: `xcodebuild ... build`

---

### P1：持久化（可选但建议）

### Task 3: 保存 Pose Stabilization 开关到 SwiftData Settings

**Files:**
- Modify: `VibeSports/Services/Settings/AppSettings.swift`
- Modify: `VibeSports/Services/Settings/SettingsRepository.swift`
- Modify: `VibeSports/Services/Settings/SwiftDataSettingsRepository.swift`
- Modify: `VibeSportsTests/SwiftDataSettingsRepositoryTests.swift`

**Step:**
- 添加字段 `poseStabilizationEnabled`（默认 true）
- 测试覆盖 load 默认值 + update 持久化

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/SwiftDataSettingsRepositoryTests`

---

### P1：ViewModel 接入（仅 overlay）

### Task 4: ViewModel 输出 Stabilized Pose（不影响 RunningMetrics）

**Files:**
- Modify: `VibeSports/ViewModels/RunnerGame/RunnerGameViewModel.swift`
- Modify: `VibeSports/Views/RunnerGame/RunnerGameView.swift`

**Step:**
- `RunnerGameViewModel` 新增 `poseStabilizer` 与 `stabilizedPose`
- `PoseOverlayView` 使用 `stabilizedPose`（当 stabilization 开启时）

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`

