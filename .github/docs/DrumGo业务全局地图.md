# DrumGo — Business Logic Map（业务全局地图）

> 面向「不读代码的 AI」：用最少上下文描述 DrumGo 做什么、为什么这样做、以及关键入口在哪里。  
> 代码与资源路径均为仓库相对路径，可直接定位。

## 1. 产品概述

DrumGo 是一款面向 **visionOS（Apple Vision Pro）** 的沉浸式架子鼓/节奏互动体验，面向想在沉浸空间里“用手打鼓、获得即时音效与特效反馈”的用户。核心体验是在 `ImmersiveSpace` 中看到一套 3D 鼓组，用户双手的鼓棒随手部追踪移动，击打鼓/镲会播放对应音效，并触发场景内的动画/灯光等特效。技术栈：SwiftUI + RealityKit + ARKit（Hand Tracking）+ Reality Composer Pro 资产包。

## 2. 架构分层

### 目录结构 → 职责

- `DrumGo/DrumGoApp.swift`：应用入口与 scene 定义（多窗口 + ImmersiveSpace）
- `DrumGo/View/`：**UI 层**（SwiftUI 窗口），负责入口、选择、打开沉浸空间/体积窗口
  - `DrumGo/View/ContentView.swift`
  - `DrumGo/View/SelectView.swift`
- `DrumGo/GameManage/`：**交互/业务协调层**
  - `DrumGo/GameManage/AppModel.swift`：全局状态（沉浸空间开关状态机）
  - `DrumGo/GameManage/ImmersiveView.swift`：沉浸空间容器（RealityView + 交互手势）
  - `DrumGo/GameManage/ManageGame.swift`：游戏管理器（手追踪、碰撞、音频、谱面调度）
  - `DrumGo/GameManage/Song.swift`：歌曲（mp3）+ 谱面（json）加载与绑定
  - `DrumGo/GameManage/Stage.swift`：谱面数据结构与 3D 坐标映射
  - `DrumGo/GameManage/IPDetailView.swift`：体积窗口展示 RealityKitContent 内的模型
- `Packages/RealityKitContent/`：**资源层（RCP）**
  - `Packages/RealityKitContent/Sources/RealityKitContent/RealityKitContent.rkassets/IntactDrumScene.usda`：主鼓场景与行为触发器
  - `Packages/RealityKitContent/Sources/RealityKitContent/RealityKitContent.rkassets/DrumStick*.usda`：鼓棒与碰撞球体（`StickSphere`）
  - `Packages/RealityKitContent/Sources/RealityKitContent/RealityKitContent.rkassets/CircleAnimation.usda`：节奏圈（含粒子）
  - `Packages/RealityKitContent/Sources/RealityKitContent/RealityKitContent.rkassets/IP1.usda`、`IP2.usda`：IP 模型

### 依赖方向（约束）

- `DrumGo/View/*` 只通过环境（`AppModel`）与系统环境值（`openImmersiveSpace/openWindow`）驱动导航；不直接操控 RealityKit 细节。
- `DrumGo/GameManage/*` 可以依赖 `RealityKitContent`（资源 bundle）与系统框架（RealityKit/ARKit/AVFAudio）。
- `Packages/RealityKitContent/*` 仅提供资源与 bundle 入口（`Bundle.module`），不应反向依赖 App 代码。

禁止（建议保持）：

- UI 层直接读取/修改 `.usda` 资源细节或硬编码实体名（这些应集中在 `ManageGame.swift`）。

## 3. 核心业务流程

### 流程 A：进入沉浸空间并打鼓

1. 用户打开应用，看到首页 UI：`DrumGo/View/ContentView.swift`
2. 用户点击按钮进入选择页：`openWindow(id: "SelectView")`（`DrumGo/View/ContentView.swift`）
3. 用户在选择页点击 “Go!” 打开沉浸空间：
   - UI：`DrumGo/View/SelectView.swift`
   - 状态机：`DrumGo/GameManage/AppModel.swift`（`immersiveSpaceState`）
4. 系统打开 `ImmersiveSpace(id: "DrumImmersive")`：
   - `DrumGo/DrumGoApp.swift` → `DrumGo/GameManage/ImmersiveView.swift`
5. 沉浸空间加载 3D 鼓场景并启动逻辑：
   - 加载：`Entity(named: "IntactDrumScene", in: realityKitContentBundle)`（`ImmersiveView`）
   - 启动：`GameManager.shared.start()`（`DrumGo/GameManage/ManageGame.swift`）
6. 手部追踪开始：鼓棒实体跟随手部关节移动（`ManageGame.swift: processHandUpdates()`）
7. 用户击打鼓/镲：
   - 碰撞事件：`CollisionEvents.Began`（`ManageGame.swift: handle*Collision(...)`）
   - 播放音效：`audioEntity.playAudio(AudioFileResource)`（`ManageGame.swift: handle*Punch(...)`）
   - 触发特效：发布 `"RealityKit.NotificationTrigger"` 通知（`ManageGame.swift`）
   - 资源行为响应：`IntactDrumScene.usda` 内 `OnNotification*` 根据 identifier 播放 Timeline（例如鼓面弹跳/灯光/心形特效）

### 流程 B：谱面驱动的节奏圈生成与击打

1. 启动时选择歌曲：`ManageGame.swift` 内置 `Song(name: "Missing U", ...)`
2. 读取谱面：
   - json：`DrumGo/Soundjson/Missing U.json`
   - 解码：`DrumGo/GameManage/Stage.swift`
3. 调度生成节奏圈：
   - `ManageGame.swift: scheduleTasks(...)` 根据 note 时间 `asyncAfter` 触发
   - 模板：`CircleAnimation`（`RealityKitContent` 资源）
4. 击打节奏圈：
   - 碰撞判定实体名：`"Circle"`（`ManageGame.swift` 常量）
   - 命中后 burst 粒子并移除实体：`ManageGame.swift: handleCirclePunch(drum:)`

### 流程 C：打开 IP 体积窗口并交互

1. 用户在选择页点击 IP 按钮：
   - `DrumGo/View/SelectView.swift` → `openWindow(id: "IPModelView", value: "IP1"|"IP2")`
2. 体积窗口渲染模型：
   - `DrumGo/DrumGoApp.swift` → `DrumGo/GameManage/IPDetailView.swift`
   - `Model3D(named: modelName, bundle: realityKitContentBundle)`
3. 模型交互（资产内置行为）：
   - 例如 `IP2.usda` 自带 `OnTap` Timeline，可在窗口内点击触发动画

## 4. 模块详情

### 4.1 沉浸空间状态机（AppModel）

- 做什么：统一管理沉浸空间是否打开/切换中，避免重复触发 open/dismiss。
- 关键文件：
  - `DrumGo/GameManage/AppModel.swift`
  - `DrumGo/View/SelectView.swift`（驱动打开/关闭）
  - `DrumGo/DrumGoApp.swift`（`onAppear/onDisappear` 作为状态最终写入点）

### 4.2 GameManager（交互中枢）

- 做什么：
  - 资产加载：鼓场景模板、节奏圈模板、鼓棒实体
  - 音频资源加载：鼓点音效
  - 歌曲播放：`AVAudioPlayer`
  - 谱面调度：根据 note 时间生成节奏圈
  - 手追踪：将鼓棒实体绑定到手部关节
  - 碰撞与点击：命中后播放音效并触发 RCP 行为
- 关键文件：
  - `DrumGo/GameManage/ManageGame.swift`
  - `DrumGo/GameManage/Song.swift`
  - `DrumGo/GameManage/Stage.swift`

### 4.3 RealityKitContent（资产包）

- 做什么：提供所有 Reality Composer Pro 资源（鼓场景、鼓棒、特效、IP 模型）。
- 关键文件：
  - `Packages/RealityKitContent/Sources/RealityKitContent/RealityKitContent.swift`（`Bundle.module`）
  - `Packages/RealityKitContent/Sources/RealityKitContent/RealityKitContent.rkassets/IntactDrumScene.usda`
  - `Packages/RealityKitContent/Sources/RealityKitContent/RealityKitContent.rkassets/CircleAnimation.usda`

### 4.4 权限与系统配置

- 做什么：声明手追踪/环境感知权限，配置沉浸空间初始沉浸样式。
- 关键文件：
  - `DrumGo/Info.plist`

## 5. 当前状态与待办

### 已完成

- [x] visionOS 多窗口结构（首页/选择页/体积窗口）与沉浸空间入口：`DrumGo/DrumGoApp.swift`
- [x] 加载主鼓场景 `IntactDrumScene` 并挂载运行时根实体：`DrumGo/GameManage/ImmersiveView.swift`
- [x] 手部追踪驱动鼓棒实体跟随：`DrumGo/GameManage/ManageGame.swift`
- [x] 鼓/镲碰撞触发音效播放：`DrumGo/GameManage/ManageGame.swift`
- [x] 通过 `"RealityKit.NotificationTrigger"` 触发 RCP 行为动画/灯光/特效：`ManageGame.swift` + `IntactDrumScene.usda`
- [x] 谱面 json 解码与按时间生成节奏圈：`Stage.swift` + `ManageGame.swift`
- [x] 节奏圈命中粒子 burst 与移除：`ManageGame.swift` + `CircleAnimation.usda`

### 进行中

- [ ] 选择页“鼓/场景/歌曲”与实际沉浸内容的联动（目前仅 UI 选中态，不影响 `GameManager` 或资产）

### 已知问题

- 碰撞订阅句柄覆盖：`ManageGame.swift` 只有一个 `colisionSubs`，多次订阅可能只保留最后一次（导致部分鼓不响应碰撞）。
- 沉浸视图内存在未使用的 ARKit 会话状态：`DrumGo/GameManage/ImmersiveView.swift` 中 `session/handTracking` 等未参与逻辑。
- 谱面时间基准不明确：`scheduleTasks` 中使用 `note.time * 0.5`，缺少同步依据（BPM/offset）。
- 测试缺失：`DrumGoTests/DrumGoTests.swift` 仅占位。

### 下一步计划（建议优先级）

1. 修复碰撞订阅的生命周期管理（改为数组/多订阅保存），确保所有鼓/镲都可稳定响应。
2. 把 `SelectView` 的选择结果写入可共享状态（例如扩展 `AppModel` 或新增 `GameSettings`），并让 `GameManager` 根据选择切换：
   - 不同鼓模型/不同主题场景/不同歌曲与谱面
3. 明确谱面时间与歌曲的同步策略（offset、倍速、BPM），将魔法系数参数化。
4. 补最小单测：`Stage` 解码、`generateStart(note:)` 映射、`ImmersiveSpaceState` 状态机转换。

## 6. 设计决策记录

### 决策：用 Reality Composer Pro 行为（NotificationTrigger）驱动场景动画，而不是在 Swift 中逐帧控制

- 背景：鼓面弹跳、灯光、特效等更适合在可视化工具中调参；代码只需触发事件。
- 选项：
  - A) Swift/RealityKit 代码中管理动画资源并手动播放
  - B) RCP 内定义 Timeline + 通过通知触发（当前方案）
- 决定：选择 B
- 原因：资产侧可快速迭代视觉效果；代码侧只维护 identifier 对齐与触发时机，耦合更低。

## 7. 构建与测试

- Build：用 Xcode 打开 `DrumGo.xcodeproj`，选择 scheme `DrumGo`，运行到 Vision Pro Simulator 或真机。
- Test：`DrumGoTests/DrumGoTests.swift`（Testing 框架）目前为空，需要补用例后再作为质量门槛。

