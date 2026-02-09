# 第三人称转向动画（简版）实施计划

> 执行方式：建议使用 `executing-plans` 按批次执行。  
> 实施风格：**非 TDD**（先做最小可用实现，再做回归验证）。

**Goal（目标）:**  
在现有“真实转弯”基础上，加入第三人称角色转向表现与相机跟随调优，让 `A/D` 或头部转向时视觉反馈更自然。

**Non-goals（非目标）:**  
- 不重做导航系统（保留当前 heading + position 方案）；  
- 不新增复杂战斗/碰撞玩法；  
- 不做资产管线重构（优先复用现有角色资源）。

**Approach（方案）:**  
- 先准备并确认 `Left Turn` / `Right Turn` 两个转向 clip；  
- 再把“转向强度”稳定输出为统一动画驱动参数（-1...1）并接入 clip 混合；  
- 若资产未就绪，可先走程序化临时转向，不阻塞相机调优；  
- 相机仅做跟随参数与阻尼调优，不改变第三人称架构。

**Acceptance（验收）:**  
- 连续转向时：输入越大，角色转向表现越明显；  
- 输入回中后：角色平滑回到直行姿态，不抖动；  
- 第三人称镜头跟随稳定，无明显“抽动/闪烁”；  
- `camera / keyboard / mixed` 三模式下行为一致可复现。

---

## Plan A（主方案）

### P0：转向动画资产就绪（前置）

### Task 0：确认并接入 `TurnLeft` / `TurnRight` 动画资源

**Files:**
- Modify: `VibeSports/Assets/Runner.usdz`（或等价角色资产）

**需要你提供/确认:**
1. 两个 clip 的精确名称（例如 `TurnLeft`、`TurnRight`）。  
2. clip 是否循环、时长与帧率。  
3. 最大转向建议幅度（例如 30° 或 45°）。

**Verify:**
- 手测：在 Debug 动画检查视图中可看到并播放左右转 clip（不报错、不缺失）。

---

### P1：角色转向动画接线（最小闭环）

### Task 1：统一输出“转向动画驱动参数”

**Files:**
- Modify: `VibeSports/Models/Runner/RunnerMotion.swift`
- Modify: `VibeSports/ViewModels/RunnerGameViewModel.swift`

**Steps:**
1. 在 `RunnerMotion` 中明确/补齐动画可直接消费的转向参数（例如 `turnInputSmoothed`）。  
2. 在 ViewModel 中做轻量平滑（进入/退出转向都避免突变）。  
3. 确保 `camera / keyboard / mixed` 最终都走同一参数出口。

**Verify:**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`  
- 预期：`BUILD SUCCEEDED`

---

### Task 2：角色转向表现（clip 混合优先，程序化兜底）

**Files:**
- Modify: `VibeSports/Services/Renderer/RunnerSceneRenderer.swift`
- Optional Create: `VibeSports/Models/Runner/RunnerTurnAnimationBlender.swift`

**Steps:**
1. 使用左/右转 clip，按转向参数进行权重混合。  
2. 若 clip 不完整或临时不可用：对角色上半身或根节点施加小幅程序化侧倾/偏航作为兜底。  
3. 保持与现有跑步动画并存，不破坏 cadence 驱动主循环。

**Verify:**
- 手测：按住 `A`/`D` 时角色有清晰但不过度的左/右转向表现。  
- 手测：松开后 0.3~0.6s 内平滑回中。

---

### P2：第三人称相机手感优化

### Task 3：相机跟随参数与阻尼调优

**Files:**
- Modify: `VibeSports/Services/Renderer/RunnerSceneRenderer.swift`
- Optional Modify: `VibeSports/Views/Debug/RunnerTuningDebugView.swift`

**Steps:**
1. 调整相机 yaw 跟随速度、boom 距离/高度、阻尼参数。  
2. 减少急转时镜头“抢转”与抖动。  
3. 如有必要，在 Debug 面板暴露 2–4 个核心参数用于现场调参。

**Verify:**
- 手测：连续左右转向时镜头稳定、可预期，无明显延迟跳变。  
- 手测：直行时镜头快速收敛，不残留偏航。

---

### P3：回归与文档

### Task 4：回归验证 + 文档同步

**Files:**
- Modify: `README.md`（如行为有用户可见变化）
- Modify: `.github/docs/business-logic.md`（补充转向动画/相机行为）

**Steps:**
1. 执行构建与测试回归。  
2. 记录手测口径（输入模式、操作步骤、预期行为）。  
3. 更新文档中关于“转向动画与相机跟随”的描述。

**Verify:**
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`  
- Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`  
- 预期：`BUILD SUCCEEDED` + `TEST SUCCEEDED`

---

## 建议执行顺序（小批次）

1. 先做 Task 0（确认动画资源可用）。  
2. 资源就绪后做 Task 1 + Task 2（形成可见转向动画闭环）。  
3. 再做 Task 3（调镜头手感）。  
4. 最后 Task 4（回归与文档）。

## 资源未就绪时的并行路径（临时）

1. 先做 Task 1（统一转向驱动参数）。  
2. 再做 Task 3（相机手感调优）。  
3. Task 2 先落程序化兜底，待 Task 0 完成后替换为 clip 混合。  
