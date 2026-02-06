# VibeSports 业务逻辑说明（macOS）

本文面向本仓库当前实现：**macOS 14+ / Swift 6 / SwiftUI + Combine + Vision + SceneKit + SwiftData**。

## 1. 产品目标（当前版本）

VibeSports 是一个「摄像头跑步游戏」的极简实现：

- 主界面：SceneKit **3D 无限跑道**为主画面
- 右上角：**摄像头小窗**
- 角色：SceneKit 中的 **3D runner 角色**（`Runner.usdz`），动画随速度变化（Idle/SlowRun/FastRun 连续混合）
- 姿态：Apple Vision 人体姿态关键点（肩/肘/腕/髋/膝/踝）用于估计“原地跑步”的运动质量与速度
- Debug：可打开 **Pose Overlay**，并可启用 **Pose Stabilization**（减少末端关节闪烁）

> 已移除：体重/热量相关逻辑（不再计算 calories，也不再持久化 weight）。

## 2. 架构分层（约束）

仓库遵循四层归属：

- `VibeSports/Views/`：SwiftUI 展示与交互（不做业务计算）
- `VibeSports/ViewModels/`：状态机与业务编排（订阅、转换、会话开始/结束）
- `VibeSports/Models/`：纯算法/模型（禁止依赖 SwiftUI / Combine）
- `VibeSports/Services/`：副作用/基础设施（Camera、Vision、Renderer、Settings）

依赖方向：`View → ViewModel → (protocol)Service → System`。

## 3. 关键业务：RunnerGame（单屏会话）

### 3.1 UI 入口与布局

- App 入口：`VibeSports/Views/VibeSportsApp.swift`
- 根视图：`RunnerGameView`（当前版本直接作为 WindowGroup 的根）
- 运行页：`VibeSports/Views/RunnerGame/RunnerGameView.swift`

RunnerGameView 的核心布局：

- 背景：`RunnerSceneView`（SceneKit 渲染）
- 右上角：`CameraPreviewView`（AVCaptureSession 预览）
- 摄像头 overlay：`PoseOverlayView`（Debug 开关控制）
- 3D 角色与相机：由 `RunnerSceneRenderer` 负责加载 `Runner.usdz`、驱动第三人称相机跟随与动画混合

### 3.2 会话状态机（ViewModel）

`RunnerGameViewModel` 负责：

- `mode`: `.idle` / `.running`
- 摄像头会话启停：`startTapped()` / `stopTapped()`
- Combine 订阅 `CameraSession.posePublisher` 获取 pose 并更新 `metrics`
- 将 `metrics.speedMetersPerSecond` 转成 3D 场景速度：`sceneRenderer.setSpeedMetersPerSecond(_:)`

相关文件：

- ViewModel：`VibeSports/ViewModels/RunnerGame/RunnerGameViewModel.swift`
- 摄像头：`VibeSports/Services/Camera/CameraSession.swift`
- 3D 渲染：`VibeSports/Services/Renderer/RunnerSceneRenderer.swift`
- 运动指标：`VibeSports/Models/Running/RunningMetrics.swift`

### 3.3 数据流（从摄像头到 3D）

1. `CameraSession` 启动 `AVCaptureSession` 并用 `AVCaptureVideoDataOutput` 输出帧
2. `OutputHandler` 每 ~20Hz 取 `CVPixelBuffer`，调用 `PoseDetecting.detect(in:)`
3. `PoseDetector` 使用 `VNDetectHumanBodyPoseRequest` 生成 `Pose`
4. `RunnerGameViewModel` 接收 `Pose?`：
   - 更新 `latestPose`
   - 计算 `RunningMetricsSnapshot`（质量、速度、步数、close-up 模式等）
   - 推进 `RunnerSceneRenderer`（以速度驱动相机前进/抖动）

## 4. 姿态（Vision）与调试骨骼

### 4.1 Vision 姿态检测

- `PoseDetector`：`VibeSports/Services/Pose/PoseDetector.swift`
  - `recognizedPoints(.all)` 读取关节
  - 目前映射 12 个关节：肩/肘/腕/髋/膝/踝（左右）

### 4.2 骨骼叠加（Debug）

- 叠加渲染：`VibeSports/Views/Shared/Camera/PoseOverlayView.swift`
- 开关入口：App 菜单 `Debug`（见下文 Command Menu）

### 4.3 Pose Stabilization（减少闪烁）

末端关节（手腕/肘）在 close-up + 遮挡/快动时置信度会抖动，直接按阈值画会造成“闪烁/断线”。

当前实现引入 `PoseStabilizer`（仅用于骨骼叠加，不影响 RunningMetrics）：

- 滞回阈值（on/off 两个阈值，避免边缘抖动）
- 短时保留（短暂丢帧/掉点时仍显示上一帧位置）
- EMA 平滑（低通滤波）

实现与测试：

- 稳定器：`VibeSports/Models/Pose/PoseStabilizer.swift`
- 单测：`VibeSportsTests/PoseStabilizerTests.swift`

## 5. 3D 无限场景（SceneKit）

`RunnerSceneRenderer` 负责构建并驱动 SceneKit 场景：

- 使用固定数量 terrain segment（`TerrainSegmentPool`）循环复用，避免节点无限增长
- 相机位移由 `speedMetersPerSecond` 推进，叠加轻微 bob/sway 模拟奔跑
- 3D runner 角色来自 `VibeSports/Resources/Runner.usdz`，并在 `Skeleton` 节点上同时播放三段动画（loop）
- 动画权重按速度实时计算（Idle↔SlowRun↔FastRun 连续混合），并同步调整步频（playback rate）
- 即使 speed=0，也保持相机朝向正确（避免“黑屏/看不到场景”）

文件：

- `VibeSports/Services/Renderer/RunnerSceneRenderer.swift`
- `VibeSports/Services/Renderer/TerrainSegmentPool.swift`

## 6. Debug Command Menu（命令菜单）

实现文件：

- `VibeSports/Views/Commands/DebugFocusedValues.swift`
- `VibeSports/Views/Commands/DebugCommands.swift`
- `VibeSports/Views/VibeSportsApp.swift`（注册 `.commands { DebugCommands() }`）

当前提供：

- `Debug → Pose Overlay`（⌘⇧P）
- `Debug → Mirror Camera`（⌘⇧M）
- `Debug → Pose Stabilization`（⌘⇧S）
- `Debug → Runner Animations…`（列出 `Runner.usdz` 内的动画 keys，支持 Play/Solo/Blend/Rate）
- `Debug → Runner Tuning…`（实时调 runner/camera/blend 参数，用于校准大小/朝向/镜头距离等）

这些开关通过 `FocusedValues` 绑定到当前窗口的 `RunnerGameView`（`focusedSceneValue`）。

更多关于 `Runner.usdz` 的构建/验证与参数含义：见 `.github/plans/1.md`。

## 7. Settings（SwiftData 持久化）

设置项集中在 `VibeSports/Services/Settings/`：

- Model：`AppSettings`（SwiftData `@Model`）
- Repo：`SwiftDataSettingsRepository`（load/update）

当前持久化字段：

- `showPoseOverlay`
- `mirrorPoseOverlay`
- `poseStabilizationEnabled`

单测：

- `VibeSportsTests/SwiftDataSettingsRepositoryTests.swift`

> 注意：曾做过一次 settings store 的重建/版本隔离（避免字段变更导致启动失败），实现见 `VibeSports/Views/VibeSportsApp.swift`。

## 8. 构建与测试

- Build：`xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- Test：`xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`
