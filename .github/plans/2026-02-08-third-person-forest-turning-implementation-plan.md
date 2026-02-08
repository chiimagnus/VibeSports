# 第三人称真转弯 + 森林世界（方案 B）实施计划

> 执行方式：建议使用 `executing-plans` 按批次实现与验收（每批 2–4 个 task）。
> 实施风格：本计划采用**非 TDD**流程（先实现最小闭环，再补测试与回归验证）。

**Goal（目标）:** 将当前“线性跑道”升级为可连续左右转弯的第三人称森林场景：头部左右摇摆（鼻子相对肩中心）与 `WASD` 调试输入都能驱动真实朝向变化与前进方向变化。

**Non-goals（非目标）:**
- 不实现角色 IK / 实时骨骼重定向；
- 不做复杂任务系统、碰撞玩法、敌人 AI；
- 不追求真实地理导航，仅保证可玩与稳定；
- 首版不新增持久化设置（输入模式与调参先走 Debug）。

**Approach（方案）:**
- 把“控制输入”抽象为统一的 `turnInput(-1...1)` 与 `forwardInput(-1...1)`，来源可为相机头部或键盘，渲染层只消费统一输入。
- 渲染从单轴 `travelZ` 升级为 `position(x,z)+headingYaw`；每帧积分朝向和位移，实现“头回中后保持当前朝向直行”。
- 场景从“赛道 segment”升级为“森林 chunk 网格”动态加载，去除赛道/马路视觉语义。
- 相机改为第三人称 rig（YawPivot + Boom + Camera 跟随），而不是旋转整个世界根节点。

**Acceptance（验收）:**
- 连续转向：头偏越大或 `A/D` 输入越大，角速度越大；输入归零后不继续转向。
- 真转弯：前进方向跟随 `headingYaw` 变化，而非仅镜头偏航。
- 森林化：不再出现赛道/马路视觉元素，仅地面与树木/装饰块。
- Debug 可用：关闭相机检测时，仅靠 `WASD` 也可完整联调前进与转向。
- 稳定性：鼻子/肩点丢失时不会突发甩头（输入平滑降到 0）。

---

## Plan A（主方案，采用方案 B 架构）

### ✅P1（最高优先级）：输入与控制模型先行（纯模型优先）

### ✅Task 1：新增“头部转向信号”模型（鼻子相对肩中心）

**Files:**
- Create: `VibeSports/Models/Pose/HeadSteeringSignal.swift`
- Test: `VibeSportsTests/HeadSteeringSignalTests.swift`

**Step 1: 实现最小可用逻辑**
- 在 `HeadSteeringSignal` 中实现：
- `raw = (noseX - shoulderCenterX) / max(shoulderWidth, epsilon)`
- deadzone + clamp 到 `[-1, 1]`
- 可选响应曲线（例如 `pow(abs(x), gamma)` 保留符号）

**Step 2: 补充测试覆盖**
- 鼻子在肩中心右侧时 `turnInput > 0`，左侧时 `< 0`
- 按肩宽归一化后，远近变化对输出影响小
- 低于 deadzone 返回 0
- 鼻子/肩缺失时返回 0（降级安全）

**Step 3: 运行验证**

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/HeadSteeringSignalTests`

Expected: PASS

---

### ✅Task 2：扩展 Pose 关节以支持头部输入（至少 nose）

**Files:**
- Modify: `VibeSports/Models/Pose/Pose.swift`
- Modify: `VibeSports/Services/PoseDetector.swift`
- Modify: `VibeSports/Views/RunnerGame/PoseOverlayView.swift`
- Test: `VibeSportsTests/HeadSteeringSignalTests.swift`

**Step 1: 实现最小改动**
- `PoseJointName` 增加 `.nose`
- `PoseDetector` 从 Vision points 映射 `.nose`
- `PoseOverlayView` 将头部连线最小集加入（`nose -> leftShoulder/rightShoulder` 或点位显示）

**Step 2: 补充测试/断言**
- 测试样本可构造 `.nose`，并能产出稳定 `turnInput`

**Step 3: 运行验证**

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/HeadSteeringSignalTests`

Expected: PASS

---

### ✅Task 3：新增键盘调试输入状态机（WASD）

**Files:**
- Create: `VibeSports/Models/Input/KeyboardDebugInputState.swift`
- Test: `VibeSportsTests/KeyboardDebugInputStateTests.swift`

**Step 1: 实现输入状态机**
- `A` -> `turnInput=-1`，`D` -> `turnInput=+1`
- `W` -> `forwardInput=+1`，`S` -> `forwardInput=-1`
- 同时按下对向键时输出 0
- keyUp 后正确复位

**Step 2: 补充单测**
- 覆盖单键、对向同按、按下释放、快速切换

**Step 3: 运行验证**

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/KeyboardDebugInputStateTests`

Expected: PASS

---

### ✅Task 4：新增输入融合器（camera / keyboard / mixed）

**Files:**
- Create: `VibeSports/Models/Input/RunnerControlInput.swift`
- Create: `VibeSports/Models/Input/RunnerControlComposer.swift`
- Test: `VibeSportsTests/RunnerControlComposerTests.swift`

**Step 1: 实现融合规则**
- `camera` 模式只吃头部输入
- `keyboard` 模式只吃 WASD
- `mixed` 模式默认键盘优先（若键盘无输入则回退相机）
- 输入缺失时安全归零

**Step 2: 补充单测**
- 固化三种模式行为与边界条件

**Step 3: 运行验证**

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/RunnerControlComposerTests`

Expected: PASS

---

### ✅P1 分组回归

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests`

Expected: P1 新增测试全部通过。

---

### ✅P2：第三人称导航状态（heading + 2D 位移）与渲染接线

### ✅Task 5：引入导航状态与积分器（纯模型）

**Files:**
- Create: `VibeSports/Models/Runner/RunnerNavigationState.swift`
- Create: `VibeSports/Models/Runner/RunnerNavigationIntegrator.swift`
- Test: `VibeSportsTests/RunnerNavigationIntegratorTests.swift`

**Step 1: 实现最小积分逻辑**
- `headingYaw += yawRate * dt`
- `position += forwardVector(headingYaw) * speed * dt`
- clamp 角速度与速度

**Step 2: 补充单测**
- `turnInput > 0` 时 `headingYaw` 增加
- `turnInput == 0` 时保持当前 heading（不自动回正）
- `forwardInput > 0` 时沿 heading 前进（含 90° 方向验证）
- clamp 生效

**Step 3: 运行验证**

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/RunnerNavigationIntegratorTests`

Expected: PASS

---

### ✅Task 6：扩展 RunnerMotion 为“控制 + 导航”载体

**Files:**
- Modify: `VibeSports/Models/Runner/RunnerMotion.swift`
- Modify: `VibeSports/Models/Running/RunningMetrics.swift`
- Modify: `VibeSports/ViewModels/RunnerGameViewModel.swift`
- Test: `VibeSportsTests/RunningMetricsTests.swift`

**Step 1: 扩展数据结构与映射**
- `RunnerMotion` 增加：`forwardInput`、`turnInput`、`headingYaw`（首版可选回填）
- `RunningMetricsSnapshot.motion` 维持向后兼容默认值

**Step 2: 补充/修正测试**
- 更新 `RunningMetricsTests` 中 motion 字段断言

**Step 3: 运行验证**

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/RunningMetricsTests`

Expected: PASS

---

### ✅Task 7：ViewModel 接入输入融合链路

**Files:**
- Modify: `VibeSports/ViewModels/RunnerGameViewModel.swift`
- Modify: `VibeSports/Views/RunnerGame/RunnerGameView.swift`
- Create: `VibeSports/Views/RunnerGame/KeyboardInputCaptureView.swift`

**Step 1: 接入键盘与相机控制合成**
- View 捕获 `W/A/S/D` down/up，更新 `KeyboardDebugInputState`
- ViewModel 每帧/每次 pose 更新时合成 `RunnerControlInput`
- 将控制信息注入 `RunnerMotion` 发给 renderer

**Step 2: 补充行为测试（模型层）**
- 在 `RunnerControlComposerTests` 增加“相机缺失 + keyboard 模式仍输出控制”

**Step 3: 构建验证**

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED

---

### ✅P2 分组回归

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`

Expected: TEST SUCCEEDED

---

### P3：森林 Chunk 世界替换线性赛道

### Task 8：新增森林 Chunk 协调器（纯模型）

**Files:**
- Create: `VibeSports/Models/World/ForestChunkCoordinator.swift`
- Test: `VibeSportsTests/ForestChunkCoordinatorTests.swift`

**Step 1: 实现 chunk 协调逻辑**
- 给定玩家 `position(x,z)`，返回周围 `N x N` 活跃 chunk 集合
- 玩家跨 chunk 边界后，活跃集合按预期更新
- 提供稳定 key（避免渲染抖动）

**Step 2: 补充单测**
- 覆盖边界穿越、重复更新、稳定排序/稳定 key

**Step 3: 运行验证**

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/ForestChunkCoordinatorTests`

Expected: PASS

---

### Task 9：Renderer 改为第三人称导航 + 森林 chunk 渲染

**Files:**
- Modify: `VibeSports/Services/Renderer/RunnerSceneRenderer.swift`
- (Optional keep/retire): `VibeSports/Services/Renderer/TerrainSegmentPool.swift`
- Create: `VibeSports/Services/Renderer/ForestChunkNodeFactory.swift`

**Step 1: 结构改造（先可编译）**
- 用 `RunnerNavigationIntegrator` 替换 `travelZ` 单轴推进
- 引入相机 rig 节点（`yawPivot`, `cameraBoom`, `cameraNode`）
- `setMotion(_:)` 消费 `forwardInput/turnInput`

**Step 2: 场景语义替换**
- 去掉“赛道/marker”视觉语义
- chunk 地面统一森林风格材质 + 树木/植被装饰

**Step 3: 手动验收（关键）**
- 仅按 `A/D` 可连续转向
- `W` 前进时轨迹随 heading 变化
- `A/D` 松开后保持当前朝向直行

**Step 4: 构建验证**

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED

---

### Task 10：Debug 菜单接入输入模式切换

**Files:**
- Modify: `VibeSports/Views/Commands/DebugCommands.swift`
- Modify: `VibeSports/Views/RunnerGame/RunnerGameView.swift`
- Modify: `VibeSports/ViewModels/RunnerGameViewModel.swift`

**Step 1: 增加模式与展示**
- `camera / keyboard / mixed`
- UI 可见当前模式（header 或 debug overlay）

**Step 2: 验证行为**
- camera 模式：WASD 不影响运动
- keyboard 模式：无相机也可跑全链路
- mixed 模式：按既定优先级融合

**Step 3: 运行验证**

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/RunnerControlComposerTests`

Expected: PASS

---

### P3 分组回归

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`  
Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`

Expected: BUILD SUCCEEDED + TEST SUCCEEDED

---

### P4：文档与收尾

### Task 11：更新业务文档与调试说明

**Files:**
- Modify: `.github/docs/business-logic.md`
- Modify: `README.md`

**Step 1: 更新 WHAT/WHY/WHERE**
- 明确：导航由 heading + forest chunks 驱动
- 明确：头部转向与 WASD debug 的输入口径

**Step 2: 回归命令记录**

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`

Expected: TEST SUCCEEDED

---

## 风险与缓解

- 风险：头部点短时丢失导致转向闪断  
缓解：`HeadSteeringSignal` 输出做平滑 + 丢点降级为渐进归零，不立即跳零。

- 风险：Renderer 改造过大导致回归难定位  
缓解：先完成 P1/P2 纯模型改造，再做渲染替换；每个 P 结束跑全量 test。

- 风险：键盘事件在 NSView/SwiftUI 生命周期中丢失  
缓解：使用专用输入捕获 `NSView`，并在 `onAppear/onDisappear` 明确焦点与复位。

---

## 不确定项（执行前建议确认）

- `mixed` 模式优先级：计划默认“键盘优先，键盘无输入回退相机”。
- 第三人称相机参数默认值：跟随距离、高度、阻尼（建议先在 Debug 面板暴露最小参数集）。
- 森林 chunk 半径默认值（性能与观感平衡）：建议先从 `5x5` 活跃区开始。

---

## 执行建议

- 先从 P1 开始（全是可快速验证的模型/输入任务），通过后进入 P2/P3。
- 每完成 2–4 个任务，使用 `executing-plans` 批次执行并回报验证结果与手测录屏。
