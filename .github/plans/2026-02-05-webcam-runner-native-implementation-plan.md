# Webcam Runner（macOS 原生复刻 / Phase B）实施计划

> 执行方式：建议使用 `executing-plans` 按批次实现与验收。

**Goal（目标）:** 做一个 macOS 原生“摄像头跑步游戏”：用户点击开始后开启摄像头，Apple Vision 估计人体姿态并计算速度/步数/热量，驱动 3D 无限场景向前推进；支持开始/结束会话与体重设置。

**Non-goals（非目标）:**
- 不做 Phase C（AI 陪跑：实时建议/个性化反馈/自适应难度）
- 不做自动提醒、不做前台 App 检测、不做强制不可跳过
- 不引入 Three.js / MediaPipe
- 不做运动历史、多端同步、Apple Watch

**Approach（方案）:**
- 采用“可测试的领域逻辑 + 依赖注入的系统服务”拆分：Camera → Pose → RunningMetrics → SceneRenderer → SwiftUI。
- 3D 渲染使用 SceneKit（`SCNView`）嵌入 SwiftUI，避免使用已废弃的 `SceneView`。
- 运动指标对齐 `cam-run-master`：`movementQuality`、`speed`、`steps`、`calories`、`weight`；并提供“标准模式/近距离模式”以适配可见范围差异。

**Acceptance（验收）:**
1. `xcodebuild` 可在 macOS 上成功 `build`，且首次点击「开始运动」会弹摄像头权限提示。
2. 点击「开始运动」后：3D 场景开始运行，UI 实时显示 Speed/Steps/Calories/Weight。
3. 人体未被检测到时：速度应平滑衰减到 0，UI 显示“未检测到有效姿势/请站入画面”等状态。
4. 原地跑步时：速度平滑上升并驱动相机/地形推进；步数持续增长；热量随时间累加；体重修改会影响热量估算。
5. 点击「结束」后：摄像头停止、检测停止、3D 停止并回到起始页；再次开始不应出现资源泄漏/多重 session。
6. 领域算法（速度平滑、计步、热量估算、地形段回收策略）具备单元测试覆盖，并可在 CI/本机重复运行通过。

---

## Plan A（主方案）

### P1（最高优先级）：工程基线与权限

#### ✅Task 1: 清理模板代码，建立 RunnerGame 入口

**Files:**
- Modify: `VibeSports/VibeSportsApp.swift`
- Replace: `VibeSports/ContentView.swift`
- Delete: `VibeSports/Item.swift`（不再使用 SwiftData 模板）

**Step 1: 先保证可编译（无功能变更）**

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`

Expected: PASS

**Step 2: 替换根视图为 RunnerGameHome（仅 UI 骨架）**

Expected: PASS（仍可 build）

#### ✅Task 2: 摄像头权限与 Info.plist 配置

**Files:**
- Modify: `VibeSports.xcodeproj/project.pbxproj`
- Create（如需要）: `VibeSports/VibeSports.entitlements`

**Step 1: 添加 `NSCameraUsageDescription`（通过 Build Settings 的 Info.plist key）**

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`

Expected: PASS（运行时会弹权限）

**Step 2: 校验沙盒权限（App Sandbox + Camera）**

Expected: 运行时能成功打开摄像头（系统弹窗授权后）

#### ✅Task 3: 锁定目标系统与 Swift 版本（破坏性调整）

**Files:**
- Modify: `VibeSports.xcodeproj/project.pbxproj`

**Step 1: 将 `MACOSX_DEPLOYMENT_TARGET` 调整到 `14.0`（或你要求的最低版本）**

**Step 2: 将 `SWIFT_VERSION` 调整到 `6.1`，并开启严格并发检查策略（按项目风格）**

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`

Expected: PASS

---

### P1：依赖注入与数据流（可测试）

#### Task 4: 定义核心协议与依赖容器

**Files:**
- Create: `VibeSports/Core/Dependencies/AppDependencies.swift`
- Create: `VibeSports/Core/Time/Clock.swift`

**Step 1: 写单测（Clock 可控时间，用于运动算法测试）**

Files:
- Create: `VibeSportsTests/ClockTests.swift`

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`

Expected: FAIL（先建立 test target / 或测试文件缺失）

**Step 2: 补齐测试 Target（如项目当前无测试）并让测试通过**

Expected: PASS

---

### P1：摄像头采集（AVFoundation）

#### Task 5: CameraSession（启动/停止/帧流）

**Files:**
- Create: `VibeSports/Services/Camera/CameraSession.swift`
- Create: `VibeSports/Services/Camera/CameraFrame.swift`

**Step 1: 实现可注入的 CameraSession 协议**

建议接口（示意）：
- `start() / stop()`
- 帧输出使用 `AsyncStream<CameraFrame>` 或 Combine Publisher（二选一，保持全项目一致）

**Step 2: 在 SwiftUI 中展示摄像头预览（不做骨骼叠加）**

Files:
- Create: `VibeSports/UI/Camera/CameraPreviewView.swift`

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`

Expected: PASS（真机/模拟运行验证画面）

---

### P1：姿态检测（Vision）

#### Task 6: PoseDetector（Human Body Pose）

**Files:**
- Create: `VibeSports/Services/Pose/PoseDetector.swift`
- Create: `VibeSports/Services/Pose/Pose.swift`

**Step 1: 定义 `Pose` 数据结构（关键点、可见性、时间戳）**

**Step 2: 将 `CameraFrame` 转换为 Vision request 输入并输出 Pose**

验收口径：
- 无人/关键点不可用：输出 `.noBody` 或 `nil`（显式区分）
- 有人：输出关键点集合与“可用性评分”

---

### P1：运动指标算法（对标 cam-run-master）

#### Task 7: RunningMetrics（速度/步数/热量/模式）

**Files:**
- Create: `VibeSports/Domain/Running/RunningMetrics.swift`
- Create: `VibeSports/Domain/Running/RunningStepDetector.swift`
- Create: `VibeSports/Domain/Running/RunningSpeedModel.swift`
- Create: `VibeSports/Domain/Running/CaloriesEstimator.swift`
- Test: `VibeSportsTests/RunningMetricsTests.swift`

**Step 1: 写失败测试：速度的加速度/减速度与平滑**

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`

Expected: FAIL（类型不存在/行为不符）

**Step 2: 实现 SpeedModel 让测试通过**

**Step 3: 写失败测试：标准模式计步（相位变化/冷却时间）**

**Step 4: 实现 StepDetector 让测试通过**

**Step 5: 写失败测试：热量估算（MET 分段 + 体重 + 时间累加）**

**Step 6: 实现 CaloriesEstimator 让测试通过**

验收口径（与 cam-run 对齐，但以测试为准）：
- `movementQuality` 0 → speed 逐帧衰减到 0
- `movementQuality` > 阈值 → speed 平滑上升到上限
- 近距离模式：下肢不可见仍可计步（摆臂节律）

---

### P1：3D 无限场景（SceneKit）

#### Task 8: RunnerSceneRenderer（地形段复用 + 相机动画）

**Files:**
- Create: `VibeSports/Renderer/RunnerScene/RunnerSceneRenderer.swift`
- Create: `VibeSports/Renderer/RunnerScene/RunnerSceneView.swift`（`NSViewRepresentable` 包装 `SCNView`）
- Create: `VibeSports/Renderer/RunnerScene/TerrainSegmentPool.swift`
- Test: `VibeSportsTests/TerrainSegmentPoolTests.swift`

**Step 1: 写失败测试：TerrainSegmentPool 不会无限增长，且能回收复用**

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`

Expected: FAIL

**Step 2: 实现段池化与回收策略，让测试通过**

**Step 3: 接入 RunnerSceneRenderer：速度 → 相机 Z 推进 + 轻微抖动**

验收口径：
- 长时间运行（> 5 分钟）不会因节点增长导致明显卡顿
- 速度为 0 时相机停止推进

---

### P1：SwiftUI 组合与会话闭环

#### Task 9: RunnerGameFeature（Home → Running → Stop）

**Files:**
- Create: `VibeSports/Features/RunnerGame/RunnerGameHomeView.swift`
- Create: `VibeSports/Features/RunnerGame/RunnerGameSessionView.swift`
- Create: `VibeSports/Features/RunnerGame/RunnerGameViewModel.swift`
- Create: `VibeSports/Features/RunnerGame/RunnerGameSession.swift`

**Step 1: 以状态机驱动 UI（显式状态、显式依赖）**

**Step 2: 集成 CameraSession + PoseDetector + RunningMetrics + RunnerSceneRenderer**

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`

Expected: PASS（运行时手动验收 Acceptance 1~5）

---

## P2（增强）：可观测性与对标细节

### Task 10: Debug Overlay（骨骼线条/关键点）

**Files:**
- Create: `VibeSports/UI/Camera/PoseOverlayView.swift`
- Modify: `VibeSports/Features/RunnerGame/RunnerGameSessionView.swift`

验收口径：可开关显示骨骼叠加，不影响核心性能。

### Task 11: 场景装饰物池化（树木/标识等）

**Files:**
- Modify: `VibeSports/Renderer/RunnerScene/RunnerSceneRenderer.swift`

验收口径：装饰物数量上限固定，回收复用。

---

## P3（下一阶段）：Phase C（AI 陪跑）占位清单（不在本计划执行）

- AI 文案策略（鼓励/调侃/科普/挑战）
- 依据 speed/steps/calories/movementQuality 的实时反馈
- 可配置频率与风格（类似 cam-run-master 的设置面板）

---

## 不确定项（执行前需要最终确认）

1. “完全复刻”的视觉边界：是否需要人物阴影/轮廓渲染（cam-run 的 shadowCanvas 风格）？
2. 速度单位与映射：UI 显示 km/h 还是 m/s？上限/加速度是否要严格对齐 cam-run 的 config？
3. 近距离模式阈值：用“肩宽像素占比”还是“关键点置信度组合”判断？

