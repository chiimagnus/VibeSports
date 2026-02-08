# DrumGo 技术文档

> 本文档基于仓库当前代码与资源状态编写（Swift 源码位于 `DrumGo/`，Reality Composer Pro 资源位于 `Packages/RealityKitContent/`）。

## 1. 项目概览

**DrumGo** 是一个面向 **visionOS（Apple Vision Pro）** 的沉浸式交互项目：在 `ImmersiveSpace` 中加载 3D 架子鼓场景，通过 **手部追踪（ARKit Hand Tracking）** 驱动鼓棒实体，与鼓/镲的碰撞触发 **音效播放** 与 **Reality Composer Pro 行为动画**；同时包含多个 SwiftUI 窗口用于选择/展示内容（含体积窗口展示 IP 模型）。

关键特性：

- **多窗口**：`ContentView` → `SelectView` → 打开 `ImmersiveSpace`，以及体积窗口 `IPModelView`
- **沉浸空间**：`ImmersiveSpace(id: "DrumImmersive")` 加载 `ImmersiveView`
- **手部追踪**：`ARKitSession + HandTrackingProvider`，将鼓棒实体绑定到手部关节姿态
- **碰撞驱动**：鼓棒末端 `StickSphere` 与鼓面/镲实体发生 `CollisionEvents.Began`，触发音效 + 行为动画
- **谱面驱动生成物**：读取 `DrumGo/Soundjson/Missing U.json`（Beatmap/Stage），按时间调度生成 `CircleAnimation`（作为“节奏提示/可击打物”）
- **Reality Composer Pro 行为触发**：通过 `NotificationCenter` 发布 `"RealityKit.NotificationTrigger"` 通知，驱动 `IntactDrumScene.usda` 内的 `OnNotification*` 行为播放 Timeline

## 2. 技术栈与平台

- 语言/框架：Swift / SwiftUI / RealityKit / ARKit
- 资源系统：Reality Composer Pro（`.rkassets` / `.usda` / `.usdz`）
- 音频：
  - 歌曲：`AVAudioPlayer` 播放 `DrumGo/Missing U.mp3`
  - 鼓点音效：`AudioFileResource`（RealityKit）播放 `DrumGo/Sound/*.MP3`
- 项目平台（由 `DrumGo.xcodeproj/project.pbxproj` 定义）：
  - `SDKROOT = xros`
  - `SUPPORTED_PLATFORMS = "xros xrsimulator"`
  - `XROS_DEPLOYMENT_TARGET = 2.4`
  - `TARGETED_DEVICE_FAMILY = 7`（Vision）

## 3. 仓库结构

```
DrumGo.xcodeproj/                 Xcode 工程
DrumGo/                           App 主 Target 源码与资源（文件夹同步到 Target）
  DrumGoApp.swift                 App 入口：WindowGroup + ImmersiveSpace
  Info.plist                      权限与沉浸空间配置
  View/                           SwiftUI 窗口 UI
    ContentView.swift
    SelectView.swift
    GameView.swift                目前为占位
  GameManage/                     业务/交互逻辑（游戏管理、沉浸视图等）
    AppModel.swift                全局状态（ImmersiveSpaceState）
    ImmersiveView.swift           RealityView 容器，接入 GameManager
    ManageGame.swift              GameManager：手追踪、碰撞、音频、谱面调度
    Song.swift                    歌曲 + 谱面（json）加载
    Stage.swift                   谱面数据模型与坐标映射
    GameScene.swift               主题枚举（目前未接入）
    IPDetailView.swift            体积窗口中展示 Model3D
  Sound/                          鼓点音效 MP3（供 AudioFileResource 加载）
  Soundjson/                      谱面 json（Stage/Note）
  Assets.xcassets/                UI 图片资源（专辑封面、鼓/场景缩略图等）

Packages/
  RealityKitContent/              Swift Package：Reality Composer Pro 资产 bundle

DrumGoTests/                      测试 Target（Testing 框架）
```

## 4. SwiftUI 应用结构与场景管理

### 4.1 App 入口与 Scene

入口：`DrumGo/DrumGoApp.swift`

- `@State private var appModel = AppModel()`，通过 `.environment(appModel)` 注入（Observation）
- 创建 3 个窗口组：
  - `WindowGroup(id: "ContentView")` → `ContentView`
  - `WindowGroup(id: "SelectView")` → `SelectView`
  - `WindowGroup(id:"IPModelView", for: String.self)` → `IPDetailView(modelName:)`
    - `.windowStyle(.volumetric)`：体积窗口（3D）
- 创建沉浸空间：
  - `ImmersiveSpace(id: "DrumImmersive")` → `ImmersiveView`
  - 在 `onAppear/onDisappear` 更新 `appModel.immersiveSpaceState`

### 4.2 全局状态（ImmersiveSpace 状态机）

文件：`DrumGo/GameManage/AppModel.swift`

- `AppModel.ImmersiveSpaceState`：`closed` / `inTransition` / `open`
- `immersiveSpaceID = "DrumImmersive"` 与 `DrumGoApp` 中一致

`SelectView` 使用该状态机做“开关沉浸空间”的按钮：

- `openImmersiveSpace(id:)` 成功后由 `ImmersiveSpace` 的 `onAppear` 将状态置为 `.open`
- `dismissImmersiveSpace()` 后由 `onDisappear` 将状态置为 `.closed`

## 5. UI 层（窗口）

### 5.1 ContentView（首页/入口）

文件：`DrumGo/View/ContentView.swift`

- 展示横向滚动的“专辑封面”图片（`Album1...Album10`）
- 主要按钮：
  - 点击后 `dismissWindow(id: "ContentView")`
  - `openWindow(id: "SelectView")` 打开选择页

### 5.2 SelectView（选择鼓/场景 + 打开沉浸空间 + 打开 IP 模型）

文件：`DrumGo/View/SelectView.swift`

- 分段选择：
  - `selectedTab == 0`：鼓缩略图（`Drum1...Drum6`）
  - `selectedTab == 1`：场景缩略图（`Scene 1...Scene 6`）
- “IP 模型”：
  - `openWindow(id: "IPModelView", value: "IP1")`
  - `openWindow(id: "IPModelView", value: "IP2")`
- “Go!/Quilt”按钮：驱动 `ImmersiveSpace` 打开/关闭（基于 `appModel.immersiveSpaceState`）

> 注意：目前 UI 的“选择鼓/场景”仅在本页保存 `selectedIndex`，未与 `GameManager` 或 RealityKit 场景联动。

### 5.3 IPDetailView（体积窗口 Model3D）

文件：`DrumGo/GameManage/IPDetailView.swift`

- `Model3D(named: modelName, bundle: realityKitContentBundle)`
- `modelName` 由 `SelectView` 传入（`"IP1"` / `"IP2"`）

`RealityKitContent` 内的 IP 资源（示例）：

- `Packages/RealityKitContent/.../IP1.usda`
- `Packages/RealityKitContent/.../IP2.usda`

其中 `IP2.usda` 自带 `OnTap` / `OnAddedToScene` 行为（Timeline 动画），在体积窗口内可直接交互触发。

## 6. 沉浸空间与 RealityKit 运行时

### 6.1 ImmersiveView（RealityView 容器）

文件：`DrumGo/GameManage/ImmersiveView.swift`

- `RealityView` 加载：
  - `Entity(named: "IntactDrumScene", in: realityKitContentBundle)`（主鼓场景）
  - `content.add(gameManager.root)`：将 `GameManager.root` 插入场景（用于承载手部鼓棒、生成的 Circle 等）
- 启动：
  - `.onAppear { gameManager.start() }`
- 手势：
  - `SpatialTapGesture().targetedToAnyEntity()`：对任意实体点击，尝试按名称逻辑触发对应 `handle*Punch`

碰撞订阅（在 `RealityView` builder 内调用）：

- `gameManager.handleCrashCymbal1Collision(content:)`
- `gameManager.handleCrashCymbal2Collision(content:)`
- `gameManager.handleRideCymbalCollision(content:)`
- `gameManager.handleTom1Collision(content:)`
- `gameManager.handleTom2Collision(content:)`
- `gameManager.handleSnareCollision(content:)`
- `gameManager.handleFloorTomCollision(content:)`
- `gameManager.handleCircleCollision(content:)`

> 重要：当前 `GameManager` 仅用一个 `colisionSubs: EventSubscription?` 保存订阅句柄，连续调用多个 `handle*Collision` 会覆盖前一个订阅，可能导致只有最后一次订阅能持续生效（详见“已知问题”）。

### 6.2 GameManager（核心：手追踪 + 音频 + 谱面 + 碰撞）

文件：`DrumGo/GameManage/ManageGame.swift`

核心成员：

- 单例：`static let shared`
- `let root = Entity()`：作为运行时根节点，挂载到 `RealityViewContent`
- 手追踪：
  - `private let session = ARKitSession()`
  - `private let handTracking = HandTrackingProvider()`
  - `leftHand/rightHand`：分别加载 `DrumStickLeft` / `DrumStick`
- 音频资源：
  - 鼓点：`AudioFileResource(named: "...")`（如 `MilitaryDrum.MP3`、`CrashCymbal.MP3`）
  - 歌曲：`Song.player`（`AVAudioPlayer`，来自 `Song.swift`）
- 谱面调度：
  - `Stage`（从 `Soundjson/*.json` 解码）
  - `scheduleTasks(notes:startTime:)`：按 note 时间调度 `spawnBox(note:)`
  - `boxTemplate`：`Entity.load(named: "CircleAnimation", in: realityKitContentBundle)`

生命周期：`start()`

1. 重置并播放歌曲：`selectedSong.player.play()`
2. 调度生成 Circle：`scheduleTasks(notes: selectedSong.stage.notes, startTime: .now())`
3. 启动手追踪：`session.run([handTracking])` 并 `processHandUpdates()`

#### 6.2.1 手追踪实体绑定

`processHandUpdates()`：

- 监听 `handTracking.anchorUpdates`
- 取 `.middleFingerKnuckle` 关节（骨骼 joint），将 `leftHand/rightHand` 的 transform 设为该关节变换
- 若实体尚未加入场景：`root.addChild(entity)`

碰撞检测依赖鼓棒末端球体实体名后缀：

- `DRUMSTICK_ENTITY_NAME_SUFFIX = "StickSphere"`
- 对应资产：`Packages/RealityKitContent/.../DrumStick.usda` 中包含子节点 `StickSphere`（带 `Collider`）

#### 6.2.2 鼓/镲实体命名约定（与资产强绑定）

代码内用于判定“被击打的鼓/镲”的名称常量：

- `SNAREDRUM_ENTITY_NAME = "Group"`
- `TOM1_ENTITY_NAME = "Group_1"`
- `TOM2_ENTITY_NAME = "Group_2"`
- `FLOORTOM_ENTITY_NAME = "Group_3"`
- `CRASHCYMBAL1_ENTITY_NAME = "cha1"`
- `CRASHCYMBAL2_ENTITY_NAME = "cha2"`
- `RIDECYMBAL_ENTITY_NAME = "cha3"`
- `CIRCLE_ENTITY_NAME = "Circle"`

这些名称来自 `IntactDrumScene.usda`（鼓场景）与 `CircleAnimation.usda`（节奏圈模板）中的实体命名。若在 RCP 中重命名，会导致碰撞判定失效。

#### 6.2.3 碰撞 → 音频 → 行为动画通知

每个 `handle*Collision(content:)`：

- 订阅 `CollisionEvents.Began`
- 检测 A/B 两个实体：
  - 鼓棒：`name.hasSuffix("StickSphere")`
  - 目标：`name == 常量实体名`
- 命中后调用对应 `handle*Punch(drum:)`

每个 `handle*Punch(drum:)` 的共通结构：

1. `parent.stopAllAnimations()`
2. 在 `parent` 下查找音频实体名（例如 `"Tom1"`、`"Snare"`、`"RideCymbal"`），调用 `playAudio(audioResource)`
3. 通过 `NotificationCenter.default.post(name: "RealityKit.NotificationTrigger", userInfo: ...)` 发布通知

通知的 `Identifier` 与 `IntactDrumScene.usda` 内 `OnNotification*` 行为触发器对齐，例如：

- `"Tom1Collision"` / `"Tom2Collision"` / `"SnareCollision"` / `"FloorTomCollision"`
- `"CrashCymbal1Collision"` / `"CrashCymbal2Collision"` / `"RideCymbalCollision"`
- 同时也会发送 `"HeartAnimation"` / `"Heart1Animation"` / `"Heart2Animation"` / `"LightShowAnimation"`（用于场景特效）

资产侧映射示例（位于 `Packages/RealityKitContent/.../IntactDrumScene.usda`）：

- `OnNotification`：identifier = `"Tom2Collision"` → PlayTimeline `/Root/Tom2Animation`
- `OnNotification4`：identifier = `"SnareCollision"` → PlayTimeline `/Root/SnareAnimation`
- `OnNotification11`：identifier = `"LightShowAnimation"` → PlayTimeline `/Root/LightShow`

#### 6.2.4 谱面（Stage/Note）与 Circle 生成

谱面模型：`DrumGo/GameManage/Stage.swift`

- `Stage` 对应 json 顶层：`_version` / `_events` / `_notes` / `_obstacles`
- `Note`：`_time`、`_lineIndex`、`_lineLayer` 等（类 Beat Saber 风格）

`generateStart(note:)` 将 `(lineLayer, lineIndex)` 映射到一个 3D 坐标（单位以米为主，直接返回 `Point3D`）。

生成逻辑：`GameManager.spawnBox(note:)`

- `boxTemplate`（`CircleAnimation`）clone 一份
- 通过 `generateStart(note:)` 计算目标点，并向 `z` 额外偏移 `-2`
- 播放 `generateBoxMovementAnimation(start:)` 生成的 Transform FromTo 动画
- 将 box（实际是 CircleAnimation 的 Root）加入 `root`

调度逻辑：`scheduleTasks(notes:startTime:)`

- 对每个 note，`DispatchQueue.main.asyncAfter(deadline:)` 触发生成
- 销毁：`BoxSpawnParameters.lifeTime`（默认 3 秒）后移除

> 注意：调度使用 `startTime + note.time * 0.5 - lifeTime/2`，这里的 `0.5` 目前像是经验系数/对齐参数，未在文档或代码中解释。

#### 6.2.5 Circle 可击打物（ParticleEmitter burst）

Circle 模板资产：`Packages/RealityKitContent/.../CircleAnimation.usda`

- 子节点：
  - `Circle`（带 `Collider` 与 `InputTarget`）
  - `ParticleEmitter`（VFXEmitter，默认 `isEmitting = 0`）

命中后：`handleCirclePunch(drum:)`

- 在 `parent` 查找 `"ParticleEmitter"`，调用 `burst()`
- 移除 `Circle` 本体，0.5 秒后移除 parent（整个模板实例）

## 7. 音频系统

### 7.1 歌曲播放（AVAudioPlayer）

文件：`DrumGo/GameManage/Song.swift`

- `AVAudioPlayer(contentsOf: Bundle.main.url(forResource: name, withExtension: "mp3")!)`
- 谱面 json：`Bundle.main.url(forResource: name, withExtension: "json")!`

当前仅内置一首：

- `Song(name: "Missing U", defaultGameScene: .painting)`

对应资源：

- `DrumGo/Missing U.mp3`
- `DrumGo/Soundjson/Missing U.json`

### 7.2 鼓点音效（AudioFileResource）

在 `GameManager.init()` 异步加载：

- `MilitaryDrum.MP3`（Snare）
- `SoundDrum.MP3`（Tom1）
- `BassDrum.MP3`（Tom2 / FloorTom）
- `HiHat.MP3`、`CrashCymbal.MP3`、`RideCymbal.MP3`

资源位于 `DrumGo/Sound/`，确保文件名大小写与扩展名完全匹配。

## 8. 权限与 Info.plist

文件：`DrumGo/Info.plist`

- `NSWorldSensingUsageDescription`：环境感知说明
- `NSHandsTrackingUsageDescription`：手部追踪说明
- `UIApplicationSceneManifest`：
  - `UISceneSessionRoleImmersiveSpaceApplication`
  - `UISceneInitialImmersionStyle = UIImmersionStyleFull`

## 9. RealityKitContent 包（资产与 bundle）

Swift Package：`Packages/RealityKitContent/Package.swift`

- `platforms`：`visionOS(.v2)`, `macOS(.v15)`, `iOS(.v18)`（用于构建该资源包）
- `public let realityKitContentBundle = Bundle.module`：`Packages/RealityKitContent/Sources/RealityKitContent/RealityKitContent.swift`

核心资产（部分）：

- `IntactDrumScene.usda`：主鼓场景（鼓、镲、灯光、心形特效、行为触发器）
- `DrumStick.usda` / `DrumStickLeft.usda`：鼓棒（含 `StickSphere` collider）
- `CircleAnimation.usda`：节奏圈（含 `ParticleEmitter`）
- `IP1.usda` / `IP2.usda`：体积窗口展示模型（部分含交互/动画）

## 10. 构建、运行与测试

### 10.1 通过 Xcode

1. 打开 `DrumGo.xcodeproj`
2. 选择 scheme：`DrumGo`
3. 选择运行目标：Vision Pro Simulator 或真机
4. Run

### 10.2 CLI（可选）

在支持 xcodebuild 的环境下可使用（destination 需按本机可用设备调整）：

```bash
xcodebuild -project DrumGo.xcodeproj -scheme DrumGo -configuration Debug build
```

### 10.3 测试

测试 Target：`DrumGoTests/DrumGoTests.swift`（使用 Swift `Testing` 框架）

当前为示例占位，尚未覆盖任何逻辑。

## 11. 扩展指南（如何加内容）

### 11.1 添加新歌曲/谱面

1. 增加资源：
   - `DrumGo/<SongName>.mp3`
   - `DrumGo/Soundjson/<SongName>.json`
2. 更新 `GameManager`：
   - 在 `DrumGo/GameManage/ManageGame.swift` 的 `songs = [...]` 中追加 `Song(name: "<SongName>", defaultGameScene: ...)`
3. （建议）在 `ContentView` 的图片列表与 UI 上加入对应入口，并把选择结果写入 `GameManager.selectedSong`

### 11.2 修改谱面到 3D 空间的映射

编辑 `DrumGo/GameManage/Stage.swift`：

- `generateStart(note:)`：控制每个 `(lineIndex, lineLayer)` 对应的 3D 坐标
- `BoxSpawnParameters`：控制生成提前量/寿命/偏移等参数

### 11.3 新增/替换鼓模型与命名

如果在 Reality Composer Pro 中替换鼓或改名：

1. 确保鼓/镲实体的 `name` 与 `ManageGame.swift` 中常量一致，或同步更新常量：
   - 例如 `TOM1_ENTITY_NAME = "Group_1"`
2. 确保每个鼓/镲的音频实体名匹配 `handle*Punch` 中 `findEntity(named:)`：
   - 例如 `findEntity(named: "Tom1")`
3. 若希望碰撞触发 RCP 动画：
   - `ManageGame` 发送的 `"RealityKit.NotificationTrigger.Identifier"` 必须与 `IntactDrumScene.usda` 中 `OnNotification*` 的 `identifier` 一致

### 11.4 新增 IP 模型（体积窗口）

1. 将模型放入 `Packages/RealityKitContent/.../RealityKitContent.rkassets/`（RCP 或手动）
2. 确保资源名（例如 `"IP3"`）可被 `Model3D(named:)` 解析
3. 在 `SelectView` 中追加按钮：`openWindow(id: "IPModelView", value: "IP3")`

## 12. 已知问题与技术债（强烈建议优先处理）

1. **碰撞订阅句柄被覆盖**
   - `GameManager` 只有一个 `colisionSubs: EventSubscription?`
   - `ImmersiveView` 依次调用多个 `handle*Collision`，每个方法都会 `colisionSubs = content.subscribe(...)` 覆盖前一个订阅
   - 结果可能是：只有最后一次订阅（例如 `handleCircleCollision`）能长期有效
2. **ImmersiveView 内存在未使用的 ARKitSession/HandTrackingProvider 状态**
   - `ImmersiveView` 自己声明了 `session/handTracking` 等，但实际手追踪在 `GameManager` 内完成
3. **谱面调度时间系数缺少解释**
   - `note.time * 0.5` 可能导致节奏与歌曲不同步，需要明确 BPM/时间基准
4. **选择页未与实际内容联动**
   - `SelectView` 的鼓/场景选择没有写入任何模型状态，也未影响沉浸场景
5. **重复/未使用代码**
   - `Stage.swift` 与 `ManageGame.swift` 均有 `generateBoxMovementAnimation`（后者未必需要）
   - `View/GameView.swift` 当前为占位
6. **测试缺失**
   - `DrumGoTests` 仅有空示例，关键逻辑（谱面解码/调度、映射函数、状态机）无覆盖

---

## 附录 A：关键标识符速查

**ImmersiveSpace**

- `AppModel.immersiveSpaceID`：`"DrumImmersive"`
- `DrumGoApp`：`ImmersiveSpace(id: "DrumImmersive")`

**通知（Reality Composer Pro 行为触发）**

- 通知名：`"RealityKit.NotificationTrigger"`
- userInfo keys：
  - `"RealityKit.NotificationTrigger.Scene"`（`Scene`）
  - `"RealityKit.NotificationTrigger.Identifier"`（字符串 identifier）

**实体命名（碰撞判定）**

- 鼓棒末端：`StickSphere`（后缀匹配）
- 鼓/镲：`Group` / `Group_1` / `Group_2` / `Group_3` / `cha1` / `cha2` / `cha3`
- 节奏圈：`Circle`

