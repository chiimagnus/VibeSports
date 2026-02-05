## VibeSports
我想开发一个提醒我、监测我运动的app，什么时候提醒我运动呢？那就是在我开发使用AI IDE开发软件的时候啦！比如我在等待codex、Claude code、cursor ide、GitHub copilot等AI IDE输出内容和修改代码的时候，这个app需要跳出来告诉我该运动一下了！然后调出摄像头检测我的锻炼——类似于手机上的记录开合跳、深蹲等运动的app那样。

### 核心目标

开发一个 macOS app，在你等待 AI IDE 输出时提醒你运动，并用摄像头检测动作、自动计数。

### 触发机制

- **条件**：白名单 app 在前台 + 空闲超过 N 秒（用户自定义）
- **白名单**：预设常见 IDE（Cursor、VS Code、Xcode、Terminal 等），用户可删减、新增。

### 运动检测

- **技术**：Apple Vision Framework（原生，无第三方依赖）
- **动作 1**：手臂上举 → 手腕从低于肩膀升到高于肩膀再回来 = 1 次
- **动作 2**：深蹲 → 人从画面消失再出现 = 1 次

### 结束条件（优先级从高到低）

1. **智能检测**：Accessibility API 监测窗口内容停止变化（AI 输出完成）
2. **固定次数**：默认 25 次，用户可改
3. **固定时长**：用户可选
4. **手动结束**：用户可选

### UI 与交互

- **提醒形式**：悬浮小窗（默认）或全屏覆盖，用户可选
- **不可跳过**：提醒弹出后必须完成运动才能继续工作
- **显示内容**：摄像头画面 + 动作计数

### Non-goals（MVP 不做）

- Apple Watch 集成
- 多端同步
- 运动历史统计（可后续加）

### 参考项目
- https://developer.apple.com/documentation/CreateMLComponents/counting-human-body-action-repetitions-in-a-live-video-feed

- 深蹲项目：https://github.com/philippgehrke/SquatCounter

- 跑步项目：https://github.com/Jamesun921/cam-run/blob/master/README.cn.md