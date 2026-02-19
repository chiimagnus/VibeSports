# Home（模式选择）+ Exercise（运动窗口）多窗口改造 & Running 仅上半身 实施计划

> 执行方式：建议使用 `executing-plans` 按批次实现与验收，并按 Task 原子化提交（Conventional Commits，subject 以 `taskN - ` 开头）。

**Goal（目标）**
- 主窗口变为 **Home**：只做模式选择（Running / Boxing）+ 右侧“校准轮廓示意预览”（不占用相机）。
- Home：**单击**切换模式并更新预览；**双击**进入对应 **Exercise Window**。
- Exercise Window：打开后**自动开相机并立刻进入校准**（无 Start）；点击 **End** 后窗口自关，并**自动回到 Home**。
- 同一时间只允许 1 个 Exercise Window（再次双击只会聚焦同一个窗口实例）。
- **彻底删除 Running 的全身能力**：删除全身校准/模式/识别分支与 UI 入口，只保留上半身校准与现有跑步体验回归。

**Non-goals（非目标）**
- Home 不显示真实相机预览，不占用摄像头资源。
- 不做多运动窗口并行、不做后台常驻相机。
- 不引入第三方库。

**Approach（方案）**
- 使用 SwiftUI 多 Scene（2 个 `WindowGroup`）：
  - `WindowGroup(id: "home")`：Home 选择页
  - `WindowGroup(id: "exercise")`：运动窗口（Running/Boxing）
- 用共享的 `AppNavigationState`（`ObservableObject`）在 Home 与 Exercise 之间传递“当前选择的运动模式”。
- 通过 `openWindow(id:)` 打开目标窗口；通过 AppKit 关闭当前窗口（`NSApp.keyWindow?.performClose(nil)`），实现“进入运动时隐藏 Home / End 回 Home”。
- Running 删除 full-body 路径：移除 `FullBodyCalibration`、移除 `RunningCalibrationMode.fullBody`，并把 Running 校准固定为上半身。

**Acceptance（验收）**
- 交互：
  - Home：单击 Running/Boxing 会切换右侧轮廓预览；双击会进入运动窗口，并且 Home 自动关闭。
  - Exercise Window：打开后立刻开始相机与校准；点击 End 会停止会话、关闭窗口，并自动回到 Home。
  - 同一时间只存在一个 Exercise Window（重复双击不会多开）。
- Running：
  - 工程与 UI 中不再出现 “Full Body / 全身” 选项；
  - 无 `FullBodyCalibration` / `.fullBody` 分支残留（代码与文档均删除/改写）。
  - 跑步 3D 场景、镜像、Pose overlay、稳定化、键盘输入仍可用。
- 回归：
  - `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build` 通过
  - `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test` 通过

---

## P1（最高优先级）：删除 Running 全身能力（只保留上半身）

### Task 1: 移除 Running “全身”模式与校准实现

**Files（预期）**
- Delete: `VibeSports/Models/Calibration/FullBodyCalibration.swift`
- Modify: `VibeSports/Models/Calibration/RunningCalibrationMode.swift`（如不再需要则删除）
- Modify: `VibeSports/ViewModels/Running/RunningSessionViewModel.swift`
- Modify: `VibeSports/Models/Running/RunningMetrics.swift`
- Modify: `VibeSports/Models/Running/RunningStepDetector.swift`（如有 scale/阈值适配残留需同步）
- Modify: `VibeSports/Models/Exercise/ExerciseSessionState.swift`（如存在 runningCalibrationMode 选择逻辑则移除/简化）

**Step 1: 实现功能**
- 删除 full-body 的校准与分支：
  - `RunningSessionViewModel.State` 不再携带 `.calibrating(mode: ...)` / `.running(mode: ...)` 的 mode（如 mode 仅剩一种则直接移除）
  - `RunningSessionViewModel.start(...)` 改为无参数或仅上半身固定参数
- `RunningMetrics` 移除 `calibrationMode` 与 `setCalibrationMode`，保留 baseline 尺度（肩宽）归一化能力即可。
- 全局搜索并移除：
  - `.fullBody`
  - `FullBodyCalibration`
  - UI 中的 “Full Body” 文案/Picker

**Step 2: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/RunningMetricsTests`
- Expected: PASS

**Step 3: 原子提交**
- `git commit -m "refactor: task1 - remove full-body running calibration"`

---

## P2：多窗口架构（Home / Exercise）

### Task 2: 引入全局导航状态（Home → Exercise）

**Files**
- Create: `VibeSports/ViewModels/Navigation/AppNavigationState.swift`

**Step 1: 实现功能**
- `@MainActor final class AppNavigationState: ObservableObject`
  - `@Published var selectedExerciseKind: ExerciseKind = .running`
  - （Running 仅上半身：不需要校准模式字段；如未来会扩展，可预留但默认不暴露 UI）

**Step 2: 验证**
- Run: `xcodebuild ... build`
- Expected: 编译通过

**Step 3: 原子提交**
- `git commit -m "feat: task2 - add app navigation state for windows"`

---

### Task 3: 拆分 App Scene 为 Home 与 Exercise 两个 WindowGroup

**Files**
- Modify: `VibeSports/Views/VibeSportsApp.swift`

**Step 1: 实现功能**
- 在 `VibeSportsApp` 增加 `@StateObject private var navState = AppNavigationState()`
- 把当前默认 `WindowGroup { ExerciseHubView(...) }` 拆成：
  - `WindowGroup(id: "home") { HomeView(dependencies: dependencies) ... .environmentObject(navState) }`
  - `WindowGroup(id: "exercise") { ExerciseWindowView(dependencies: dependencies) ... .environmentObject(navState) }`
- 保持 Settings scene 不变，并确保 `debugTools` / `runnerCommands` 注入到两个窗口视图（ExerciseWindow 需要；Home 可选）。

**Step 2: 验证**
- Run: `xcodebuild ... build`
- Expected: 编译通过

**Step 3: 原子提交**
- `git commit -m "feat: task3 - split home and exercise windows"`

---

### Task 4: 实现 Home 视图（单击切换、双击进入运动窗口）

**Files**
- Create: `VibeSports/Views/Home/HomeView.swift`
- Modify（或删除/迁移）: `VibeSports/Views/ExerciseHub/ExerciseHubView.swift`（Home 不再使用它作为主窗口）

**Step 1: 实现功能**
- Home UI 最小可用（MVP）：
  - 左侧/上方：Running 与 Boxing 两个可点击卡片（selected 状态高亮）
  - 右侧：轮廓示意预览（复用现有“校准轮廓绘制”逻辑；不占用相机）
  - 提示文案：单击选择，双击开始
- 交互：
  - 单击：`navState.selectedExerciseKind = ...`
  - 双击：先 `openWindow(id: "exercise")`，然后关闭 Home 当前窗口（用 AppKit：`NSApp.keyWindow?.performClose(nil)`；注意用 `DispatchQueue.main.async` 避免与 window open 同步冲突）

**Step 2: 验证（手动）**
- Run app：
  - 单击 Running/Boxing：右侧预览变化
  - 双击：进入 Exercise window，Home 自动关闭

**Step 3: 原子提交**
- `git commit -m "feat: task4 - add home view with mode preview and double-click start"`

---

### Task 5: 实现 Exercise Window（自动开相机并校准，无 Start；End 回 Home）

**Files**
- Create: `VibeSports/Views/ExerciseWindow/ExerciseWindowView.swift`
- （可选）Create: `VibeSports/ViewModels/ExerciseWindow/ExerciseWindowViewModel.swift`（若需要把“返回 Home”逻辑从 View 抽离）
- Modify: `VibeSports/ViewModels/ExerciseHub/ExerciseHubViewModel.swift`（如果要复用它作为 orchestrator：增加 “start(kind:)” 入口，去掉对 Home 选择 UI 的依赖）

**Step 1: 实现功能**
- ExerciseWindowView 根据 `navState.selectedExerciseKind` 决定展示内容：
  - Running：`RunnerSceneView(renderer: ...)` + Running 校准 overlay（复用现有 overlay 但无 “选择模式”）
  - Boxing：`BoxingView(...)`
- 自动启动：
  - `onAppear`：设置 kind → 调用 start（启动 camera + 进入 calibrating）
  - 保证不会重复 start（例如只在 idle 时 start）
- End：
  - 先 stop 会话（释放相机资源）
  - `openWindow(id: "home")`
  - 关闭当前 exercise window（`NSApp.keyWindow?.performClose(nil)` 或捕获该 window 进行关闭）
- 单实例：
  - 依赖 `WindowGroup(id:"exercise")` 的 id（系统会复用同一窗口）

**Step 2: 验证（手动）**
- 从 Home 双击进入 Running/Boxing：
  - Exercise window 打开后立即请求相机并进入校准
- 点击 End：
  - Exercise window 关闭
  - 自动回到 Home window

**Step 3: 原子提交**
- `git commit -m "feat: task5 - add exercise window auto-start and return home"`

---

## P3：轮廓预览复用与 UI 打磨（不影响业务逻辑）

### Task 6: 提取可复用的“轮廓示意预览”组件（供 Home 与校准态共用）

**Files**
- Create: `VibeSports/Views/Shared/CalibrationSilhouettePreview.swift`（或放入 `VibeSports/Views/Running/`，但需可被 Home 引用）
- Modify: `VibeSports/Views/Running/RunningCalibrationOverlayView.swift`（改为复用组件）

**Step 1: 实现功能**
- 把当前 `Canvas` 轮廓绘制从 overlay 内部 `private` 结构提取出来，支持：
  - Running silhouette（上半身）
  - Boxing silhouette（如要复用 Boxing 的 guard 目标圈，可后续扩展；MVP 先做 Running）

**Step 2: 验证**
- Run app：Home 与 Running 校准 overlay 均能显示轮廓预览

**Step 3: 原子提交**
- `git commit -m "refactor: task6 - extract calibration silhouette preview component"`

---

## P4：文档更新与回归

### Task 7: 更新文档（删除 Full Body 相关叙述，补充多窗口流程）

**Files**
- Modify: `README.md`
- Modify: `.github/docs/business-logic.md`
- （可选）Modify: `.github/plans/2026-02-19-boxing-running-calibration-structure-implementation-plan.md`（标注“running full-body 已移除/被新计划替代”）

**Step 1: 实现功能**
- README：描述 Home/Exercise 双窗口与自动校准；明确 Running 仅上半身
- business-logic：更新用户旅程与流程图（Home → Exercise；End → Home），移除 full-body 相关词汇

**Step 2: 验证**
- 人工检查：路径/入口索引正确

**Step 3: 原子提交**
- `git commit -m "docs: task7 - document window flow and upper-body-only running"`

---

### Task 8: 全量回归验证

**Step 1: 验证**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`
- 手动验证清单：
  - Home 不占用相机（打开 Home 不应触发相机权限/指示灯）
  - 双击 Running/Boxing 能进入 Exercise window 并自动校准
  - End 后回到 Home
  - Running 3D 场景与调试开关回归正常（Pose overlay / Mirror / Stabilization / Keyboard）

---

## 不确定项（执行前最后确认）

1. Exercise window 的标题与大小（Running/Boxing 是否不同 window size，是否需要固定最小尺寸？）
2. 双击行为是否需要同时支持 “Enter/Space 快捷键启动”？（如需要，补一个 Task 做键盘导航。）

