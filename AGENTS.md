# 仓库指南

## 项目概览

VibeSports 是一个 macOS 原生的「摄像头运动游戏」：用户开始会话后，摄像头采集视频帧 → Apple Vision 视觉估计（Running：面部关键点；Boxing：人体姿态）→ 计算步数/步频/热量/出拳事件 → 驱动 SceneKit 无限场景渲染（Running）或 Debug 预览（Boxing）。UI 使用 SwiftUI；业务与状态按 MVVM 组织；事件流/异步用 Combine；设置持久化用 SwiftData。会话通常围绕 `Idle/Calibrating/Running` 状态切换（Calibrating 仅 Boxing），结束会话需停止检测并释放摄像头资源。当前工程配置为 **macOS 14+ / Swift 6**。

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
- Home 窗口根视图：`VibeSports/Views/Home/HomeView.swift`
- Exercise 窗口根视图：`VibeSports/Views/ExerciseWindow/ExerciseWindowView.swift`
- 依赖装配：`VibeSports/Services/AppDependencies.swift`（集中创建 Service，并注入到 ViewModel）

保持依赖“自上而下”流动：View 创建/持有 ViewModel；ViewModel 只依赖协议（或最小必要类型）；Service 不反向依赖 UI 层。

## 数据与状态（SwiftData / Combine）

- 设置持久化集中在 `VibeSports/Services/Settings/`；View 不直接读写 SwiftData
- Combine 订阅在 ViewModel/Service 内部管理，使用 `AnyCancellable` 并 `store(in:)`，避免泄漏与重复订阅

## 常见修改点

- 姿态检测：`VibeSports/Services/PoseDetector.swift` 与 `VibeSports/Models/Pose/`
- Running 头部检测：`VibeSports/Services/Running/RunningHeadDetector.swift` 与 `VibeSports/Models/Running/`
- 摄像头采集：`VibeSports/Services/CameraSession.swift`
- 3D 渲染：`VibeSports/Services/Renderer/` 与 `VibeSports/Views/Running/RunnerSceneView.swift`
- 运动指标：`VibeSports/Models/Running/` 与 `VibeSports/ViewModels/Running/RunningSessionViewModel.swift`

## 代码风格与命名规范

- 遵循 Swift API Design Guidelines；类型/文件用 `PascalCase`，方法/变量用 `camelCase`
- 文件名与主要类型同名；按功能放入对应目录（例如 `RunnerGame/`）
- 组合优于继承：依赖通过构造器或 Environment 注入；禁止 `static let shared` 单例
- MVVM 边界：View 不做业务计算；Model 不持有副作用；副作用集中在 Service（相机、Vision、渲染、存储）

## 提交与 Pull Request 规范

- 单个 PR 聚焦一个主题；在描述中写清“动机 + 验证方式”（测试输出、截图/录屏）
- 涉及算法/计算逻辑变更时，优先补齐 `VibeSportsTests/` 对应测试用例


## 核心技术栈

- **架构模式**：MVVM (Model-View-ViewModel)
- **编程范式**：Protocol-Oriented Programming (面向协议编程)
- **UI 框架**：SwiftUI、SceneKit
- **响应式/状态管理**：`ObservableObject` + `@Published`（SwiftUI 绑定）+ Combine（Publisher 管道）；少量使用 Swift Concurrency（按需）
- **数据持久化**：SwiftData
- **语言版本**：Swift 6.0+
- **支持平台**：macOS 14.0+
- **测试框架**：XCTest
- **调试日志**：使用 `os.Logger`，设置清晰的 subsystem 和 category，便于过滤和定位问题


---

## 设计原则

### 核心原则

- **组合优于继承** — 使用依赖注入
- **接口优于单例** — 支持测试和灵活性
- **显式优于隐式** — 清晰的数据流和依赖关系
- **协议驱动** — 面向协议而非实现，消除 switch 语句

### 简洁原则

- **KISS** — 保持简单，能用简单方案就不用复杂方案
- **YAGNI** — 不为"将来可能需要"的功能写代码
- **DRY + WET** — 避免重复，但也别过早抽象（重复 2-3 次再考虑）

### 职责分离

- **SRP（单一职责）** — 一个类/函数只做一件事
- **DIP（依赖倒置）** — 依赖抽象而非具体实现
- **SoC（关注点分离）** — 不同功能的代码分开放

---

## MVVM 架构规范

### 职责划分

**Model** — 纯数据结构，不含业务逻辑（禁止引用 SwiftUI / Observation / Combine）

**ViewModel** — 业务逻辑、状态管理、数据转换（禁止操作 UI、使用单例）

**View** — 纯 UI 展示、用户交互响应（禁止处理业务逻辑、直接访问数据库）

**Service** — 网络请求、数据存储等基础设施

### ViewModel 规范

**当前项目以 `ObservableObject` + `@Published` 为主（配合 Combine）。**

> 若未来计划迁移到 `@Observable` / `@Bindable`，请在一个模块内保持单一状态范式，避免同一状态被重复持有（例如同时存在 `@Published` 与 `@Observable` 的两套源）。

**实例化策略：**

- ✅ ViewModel 由 View 持有：`@StateObject`
- ✅ 观察外部注入的对象：`@ObservedObject`
- ✅ 跨多层共享的全局状态：`.environmentObject()` + `@EnvironmentObject`
- ✅ 轻量值类型状态：`@State`
- ✅ 依赖注入：构造器注入 / `.environmentObject()`（按需）
- ❌ 禁止单例：`static let shared`

---

## 协议驱动开发

### 原则

1. **面向协议而非实现** — 优先定义协议，再实现具体类型
2. **消除 switch 语句** — 用协议替代类型判断
3. **可扩展性** — 添加新类型只需实现协议，不改现有代码

### 示例

```swift
// ✅ 正确：协议定义统一接口
protocol DataSourceProvider {
    var displayName: String { get }
    var filterNotification: Notification.Name { get }
}

// ✅ 正确：通过协议统一处理
func process(_ provider: DataSourceProvider) {
    let name = provider.displayName  // 无需 switch
}

// ❌ 错误：switch 根据类型判断
switch source {
		case .typeA: // ...
		case .typeB: // ...  // 每加新类型都要改
}
```
