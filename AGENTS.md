# 仓库指南

## 项目概览

VibeSports 是一个 macOS 原生的「摄像头跑步游戏」：用户开始会话后，摄像头采集视频帧 → Apple Vision 姿态估计 → 计算速度/步数/热量 → 驱动 SceneKit 无限场景渲染。UI 使用 SwiftUI；业务与状态按 MVVM 组织；事件流/异步用 Combine；设置持久化用 SwiftData。会话通常围绕 `Idle/Running/Stopped` 状态切换，结束会话需停止检测并释放摄像头资源。当前工程配置为 **macOS 14+ / Swift 6**。

## 项目结构与模块组织

- `VibeSports/Views/`：SwiftUI 视图与组件（按功能分组）
- `VibeSports/ViewModels/`：ViewModel（业务逻辑、状态管理、数据转换）
- `VibeSports/Models/`：纯模型与算法（禁止依赖 SwiftUI / Combine）
- `VibeSports/Services/`：基础设施（Camera / Vision / Renderer / Settings / Dependencies）
- `VibeSportsTests/`：单元测试

新增功能时优先保持“同一业务在 Views/ViewModels/Models/Services 四层均有归属”，避免把逻辑堆到 View 内。

示例（新增 `FeatureX`）：

```text
VibeSports/Views/FeatureX/
VibeSports/ViewModels/FeatureX/
VibeSports/Models/FeatureX/
VibeSports/Services/FeatureX/
```

## 构建、测试和开发命令

- 打开工程：`open VibeSports.xcodeproj`
- 构建（macOS）：`xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`
- 运行测试：`xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`
- 运行单个测试类（示例）：`xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/RunningMetricsTests`

## 入口与依赖注入

- App 入口：`VibeSports/Views/VibeSportsApp.swift`
- 根视图：`VibeSports/Views/RunnerGame/RunnerGameView.swift`
- 依赖装配：`VibeSports/Services/AppDependencies.swift`（集中创建 Service，并注入到 ViewModel）

保持依赖“自上而下”流动：View 创建/持有 ViewModel；ViewModel 只依赖协议（或最小必要类型）；Service 不反向依赖 UI 层。

## 数据与状态（SwiftData / Combine）

- 设置持久化集中在 `VibeSports/Services/Settings/`；View 不直接读写 SwiftData
- Combine 订阅在 ViewModel/Service 内部管理，使用 `AnyCancellable` 并 `store(in:)`，避免泄漏与重复订阅

## 常见修改点

- 姿态检测：`VibeSports/Services/PoseDetector.swift` 与 `VibeSports/Models/Pose/`
- 摄像头采集：`VibeSports/Services/CameraSession.swift`
- 3D 渲染：`VibeSports/Services/Renderer/` 与 `VibeSports/Views/RunnerGame/RunnerSceneView.swift`
- 运动指标：`VibeSports/Models/Running/` 与 `VibeSports/ViewModels/RunnerGameViewModel.swift`

## 代码风格与命名规范

- 遵循 Swift API Design Guidelines；类型/文件用 `PascalCase`，方法/变量用 `camelCase`
- 文件名与主要类型同名；按功能放入对应目录（例如 `RunnerGame/`）
- 组合优于继承：依赖通过构造器或 Environment 注入；禁止 `static let shared` 单例
- MVVM 边界：View 不做业务计算；Model 不持有副作用；副作用集中在 Service（相机、Vision、渲染、存储）

## 提交与 Pull Request 规范

- 单个 PR 聚焦一个主题；在描述中写清“动机 + 验证方式”（测试输出、截图/录屏）
- 涉及算法/计算逻辑变更时，优先补齐 `VibeSportsTests/` 对应测试用例
