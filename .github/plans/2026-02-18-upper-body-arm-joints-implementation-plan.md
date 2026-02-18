# 上半身姿态检测（手肘/手腕）增强 实施计划

> 执行方式：建议后续使用 `executing-plans` 按批次实现与验收。

**Goal（目标）:** 在“上半身为主”的构图下，让 `.leftElbow/.rightElbow/.leftWrist/.rightWrist` 更容易被稳定检测/显示（减少“只有鼻子/肩膀稳定、肘/腕经常缺失”的情况）。

**Non-goals（非目标）:**
- 不替换 Apple Vision 的人体姿态模型、不引入第三方 ML 框架
- 不在第一步就做人物分割/抠图（见文末【第二步】）
- 不更换 `HeadSteeringSignal` 的输入关节（仍基于鼻子+双肩），仅允许按需微调门槛参数

**Approach（方案）:**
- 现状：`PoseDetector` 输出原始关节点；`PoseStabilizer` 用统一阈值（默认 `on=0.35/off=0.20/hold=0.20`）决定“点亮/熄灭”；上半身特写时肘/腕置信度往往长期低于 `0.35`，导致永远点不亮。
- 改进：为 `PoseStabilizer` 增加“按关节的阈值/保活覆盖（override）”，并在运行时对肘/腕采用更宽松的 `on/off/hold`（例如 `on≈0.18–0.25`、`off≈0.08–0.15`、`hold≈0.30–0.50s`）。
- 可观测性：加一个轻量 Debug 读数（显示 raw pose 的肘/腕置信度 + stabilized 是否输出该点），并通过开关控制显示，用于快速验证“是 Vision 没给点，还是被阈值挡掉”。

**Acceptance（验收）:**
- 在上半身构图中（不要求全身入镜），开启 `Pose Stabilization` 后，肘/腕点不再长期缺失，能在数百毫秒内“点亮并保持”（允许轻微抖动）。
- `HeadSteeringSignal` 行为不回退（鼻子/肩膀仍可稳定驱动转向）。
- `xcodebuild ... build` 通过，且 `PoseStabilizerTests` 覆盖新增行为。

---

## P1（最高优先级）：按关节放宽肘/腕阈值

### Task 1: 为 `PoseStabilizer.Configuration` 增加“按关节覆盖”的配置入口

**Files:**
- Modify: `VibeSports/Models/Pose/PoseStabilizer.swift`

**Step 1: 实现功能**
- 在 `PoseStabilizer.Configuration` 内新增一个小型可 `Sendable` 的 override 结构（例如 `JointOverride`：`on/off/hold`）。
- 新增 `jointOverrides: [PoseJointName: JointOverride] = [:]`，并提供 `override(for:)` 或 `configuration(for:)` 的查询方法：
  - 默认走全局 `onConfidenceThreshold/offConfidenceThreshold/holdDuration`
  - 若存在 override，优先使用 override 的 `on/off/hold`
- 保持现有字段与默认值不变（不影响旧调用方式）。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Expected: 编译通过

---

### Task 2: 在 `PoseStabilizer.ingest` 中应用按关节阈值/保活

**Files:**
- Modify: `VibeSports/Models/Pose/PoseStabilizer.swift`

**Step 1: 实现功能**
- 在 `for name in PoseJointName.allCases` 循环里，读取该 `name` 的 `on/off/hold`（来自 Task 1 的查询方法），替代当前统一阈值/保活时长。
- 保持输出 `PoseJoint.confidence = 1.0` 的语义不变（避免影响 `HeadSteeringSignal` 对 stabilized pose 的 `minConfidence` 判断）。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/PoseStabilizerTests`
- Expected: PASS

---

### Task 3: 提供“上半身友好”的默认 override 组合，并在运行时启用

**Files:**
- Modify: `VibeSports/Models/Pose/PoseStabilizer.swift`
- Modify: `VibeSports/ViewModels/RunnerGameViewModel.swift`

**Step 1: 实现功能**
- 在 `PoseStabilizer.Configuration` 增加一个静态/工厂方法（例如 `upperBodyArmsPreset()` 或 `withUpperBodyArmOverrides()`），返回一组仅针对肘/腕的 `jointOverrides`。
  - 建议初始值（后续可按体验微调）：
    - 肘：`on=0.25, off=0.12, hold=0.40`
    - 腕：`on=0.20, off=0.10, hold=0.45`
  - 说明：更低的 on + 更长 hold，优先“让它出现并保持”，符合当前需求。
- 在 `RunnerGameViewModel.init`（或首次开始 session 的时机）启用该 preset：
  - 若希望风险更小：只在 `poseStabilizationEnabled == true` 时启用
  - 若希望更可控：先做成常量开关（后续再接入 Settings 持久化）

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Expected: 编译通过
- 手动验证：运行 App，在上半身构图下打开 `Pose Overlay` + `Pose Stabilization`，观察肘/腕是否明显更常出现。

---

### Task 4: 为“override 生效”补一个单测，防止回归

**Files:**
- Modify: `VibeSportsTests/PoseStabilizerTests.swift`

**Step 1: 实现功能**
- 新增测试：当全局 `onConfidenceThreshold=0.35` 时，给 `.leftWrist` 输入 `confidence=0.22`：
  - 未设置 override：应为不可见
  - 设置 wrist override（如 `on=0.20`）：应可见
- 再补一个测试覆盖 `holdDuration` override（例如 elbow/wrist 在 nil pose 窗口内仍保持）。

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/PoseStabilizerTests`
- Expected: PASS

---

## P2（可观测性）：加一个“置信度/输出状态”Debug 读数（可选但强烈建议）

### Task 5: 在相机预览上叠加肘/腕 raw confidence 与 stabilized 输出状态

**Files:**
- Modify: `VibeSports/Views/RunnerGame/RunnerGameView.swift`

**Step 1: 实现功能**
- 在 `cameraPreview` 的 overlay 内（与 `PoseOverlayView` 同层或更上层）添加一个小型文本面板：
  - 展示 `latestPose` 的 `.leftElbow/.rightElbow/.leftWrist/.rightWrist` raw confidence（没有则显示 `—`）
  - 展示 stabilized pose 是否包含该关节（有/无）
- 显示条件建议：仅当 `showPoseOverlay == true` 时显示，避免干扰常规 UI。
- 补充：建议再加一个独立开关（例如 `Arm Debug Overlay`）控制是否显示该面板，并持久化到设置。

**Step 2: 验证**
- 手动验证：运行 App，打开 `Pose Overlay`，确认读数随动作变化；并能区分“Vision 不给点（raw=—）”与“被阈值挡住（raw 有值但 stabilized 无点）”。

---

## 回归验证（完成 P1/P2 后）

- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`
- Expected: 全部通过

---

## 实施记录（已完成）

- P1/P2 已落地：`PoseStabilizer` 支持按关节 override，并默认对肘/腕启用上半身 preset（更低 on/off + 更长 hold）。
- P2 叠层已加开关：`Arm Debug Overlay` 可在 Settings 中打开/关闭，且持久化保存。
- 额外调整（按需）：将 `HeadSteeringSignal.configuration.minConfidence` 下调（例如从 `0.35` 到 `0.20`），用于低光/噪点环境下仍能产生转向输入（不改变输入关节，仅调门槛）。

---

# 【第二步】（可选增强）：抠人/背景净化（人物分割）以提升肘/腕置信度

> 当你确认“背景杂乱/对比度低”时，这一步通常能显著提升肘/腕的 raw confidence，从根上减少缺失。

**目标：** 在送入 `VNDetectHumanBodyPoseRequest` 之前，先用人物分割生成 mask，把背景置为纯色/模糊，仅保留人物区域，再进行姿态估计。

**建议实现路径（高层任务，先不做 P1 以外改动）：**
1. 在 `VibeSports/Services/PoseDetector.swift` 引入可选的 `VNGeneratePersonSegmentationRequest`（作为开关/策略），输出 `CVPixelBuffer` mask。
2. 用 CoreImage（`CIFilter.blendWithMask` / `CISourceOverCompositing` 等）把背景替换为纯色（如黑色）或强模糊，合成新的 `CVPixelBuffer`。
3. 将合成后的 buffer 输入现有 `VNDetectHumanBodyPoseRequest`，并通过 Debug 面板对比 raw confidence 的提升幅度。
4. 性能控制：
   - 复用 `VNSequenceRequestHandler` 或按帧率节流（你当前已有 20fps 处理间隔）。
   - 分割质量与速度折中（如 `.balanced` / `.fast`），优先保证实时性。
5. 提供一个 Settings/Debug 开关（并持久化到 `SwiftDataSettingsRepository`），便于 A/B 对比与回退。
