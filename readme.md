## VibeSports

一个 macOS 原生「摄像头跑步游戏」（Webcam Runner）的复刻项目：用户主动点击开始后，App 打开摄像头，用 Apple Vision 估计人体姿态，计算“原地跑步”的速度/步数/热量，并驱动一个 3D 无限场景向前推进（类似 `cam-run-master`，但**不使用** Three.js / MediaPipe）。

## 核心目标（Phase B）

- 用户主动点击「开始运动」后，进入跑步会话
- 摄像头采集视频帧 → Vision 姿态估计 → 运动质量/速度/步数/热量计算
- 3D 无限场景（地形段循环复用、装饰物、相机抖动/高度随速度变化）
- 运动指标 UI：Speed / Steps / Calories / Weight（可编辑）
- 可随时「结束」会话并停止摄像头

## Non-goals（当前不做）

- AI 陪跑（Phase C 再做：实时建议/个性化反馈/自适应难度等）
- 任何“自动提醒/强制不可跳过”的工作流（不做前台 App 检测、不做强制覆盖）
- Apple Watch 集成、多端同步、运动历史统计
- 第三方动作识别依赖（不引入 MediaPipe）

## 关键设计要点

### 交互与状态机

- `Idle`：未开始，展示说明、体重设置、开始按钮
- `Running`：摄像头开启 + 姿态检测 + 3D 场景运行 + 指标实时刷新
- `Stopped`：会话结束，释放摄像头资源并回到 `Idle`

### 运动检测（Apple Vision）

- 使用 Vision 的人体姿态关键点（全身/上半身可见时都能工作）
- 标准模式：优先用下肢（膝/踝）节律推导步频
- 近距离模式：下肢不可见时用上肢摆臂节律推导步频（对标 `cam-run-master` 的 close-up 思路）

### 3D 场景（原生）

- 采用原生 3D 渲染（优先 SceneKit / `SCNView` 嵌入 SwiftUI，避免使用已废弃的 `SceneView`）
- 无限地形通过“固定数量地形段 + 回收复用”实现，避免无限节点增长

## 参考

- Web 版参考（目标对齐）：`cam-run-master`（Jamesun921/cam-run）
- Apple 示例（姿态/计数思路参考）：CreateMLComponents「Counting human body action repetitions in a live video feed」
