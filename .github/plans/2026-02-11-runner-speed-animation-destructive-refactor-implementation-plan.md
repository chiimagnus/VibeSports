# 跑步动画与世界速度一致性（破坏性重构）实施计划

> 执行方式：建议使用 `executing-plans` 按批次实现与验收。  
> 实施风格：**破坏性重构**（不做向后兼容，删除旧路径与旧参数）。

**Goal（目标）:**  
让“世界前进速度”和“角色跑步动画”由同一套规则驱动，并满足以下口径：`slow@1x = 4 km/h`、`fast@1x = 9 km/h`、4~9 线性过渡、低于 4 仍 slow、高于 9 不再更快。

**Non-goals（非目标）:**  
- 不保留旧版基于 `idleThreshold/minRun/maxRun/minRate/maxRate` 的混合与调速行为；  
- 不保留“单一 strideLength 驱动所有档位”的模型；  
- 不做资产重制（继续使用现有 `Runner.usdz`）。

**Approach（方案）:**  
- 用“速度锚点 + 线性插值”统一生成世界速度与 slow/fast 权重；  
- slow/fast 两个 clip 播放速率固定为 `1.0`（原速），不再按 cadence 动态拉伸 clip 速度；  
- 删除 `RunnerAnimationBlender` 旧配置字段与相关 UI，避免混杂两套模型；  
- 在模型层新增单一 `LocomotionMapper`，由它输出：`worldSpeed`、`slowWeight`、`fastWeight`、`clampedInputSpeed`。

**Acceptance（验收）:**  
- 运行时 `slowRunPlayer.speed == 1.0`、`fastRunPlayer.speed == 1.0`；  
- 输入速度 `<= 4 km/h`：`slowWeight = 1`，世界速度为 `4 km/h`；  
- 输入速度 `>= 9 km/h`：`fastWeight = 1`，世界速度为 `9 km/h`；  
- 输入速度 `6.5 km/h`：`slowWeight ≈ 0.5`、`fastWeight ≈ 0.5`；  
- 旧参数/旧逻辑/旧测试已删除，项目无死代码引用。

---

## Plan A（主方案）

### P1（最高优先级）：删除旧速率体系，建立新映射模型

### Task 1：移除旧 `RunnerAnimationBlender` 与相关测试，替换为新映射模型

**Files:**
- Delete: `VibeSports/Models/Runner/RunnerAnimationBlender.swift`
- Delete: `VibeSportsTests/RunnerAnimationBlenderTests.swift`
- Create: `VibeSports/Models/Runner/RunnerLocomotionMapper.swift`
- Create: `VibeSportsTests/RunnerLocomotionMapperTests.swift`

**Step 1: 实现新模型**
1. 新增 `RunnerLocomotionMapper`，输入 `inputSpeedMetersPerSecond`，输出：
   - `clampedSpeedMetersPerSecond`（夹紧到 `4...9 km/h`）
   - `slowRunWeight` / `fastRunWeight`（线性过渡）
   - `targetWorldSpeedMetersPerSecond`（与 `clampedSpeed` 相同来源）
2. 将 `4 km/h` 与 `9 km/h` 常量写入模型配置（m/s 存储，km/h 仅展示）。

**Step 2: 验证**
Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`  
Expected: `BUILD SUCCEEDED`

**Step 3: 补测试（必须）**
1. `<=4 km/h` 输出 slow 全权重；  
2. `>=9 km/h` 输出 fast 全权重；  
3. 中点 `6.5 km/h` slow/fast 为 0.5/0.5；  
4. 权重和恒等于 1。

Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test -only-testing:VibeSportsTests/RunnerLocomotionMapperTests`  
Expected: `TEST SUCCEEDED`

---

### Task 2：破坏性清理 Tuning 数据结构与调参 UI（删旧字段）

**Files:**
- Modify: `VibeSports/Services/Renderer/RunnerSceneRenderer.swift`（`Tuning` 结构）
- Modify: `VibeSports/Views/Debug/RunnerTuningDebugView.swift`
- Modify: `VibeSports/Services/DebugToolsStore.swift`
- Modify: `VibeSports/Views/RunnerGame/RunnerGameView.swift`
- Modify: `VibeSports/ViewModels/RunnerGameViewModel.swift`

**Step 1: 删旧参数**
1. 删除旧字段：
   - `blender.idleThresholdMetersPerSecond`
   - `blender.minRunSpeedMetersPerSecond`
   - `blender.maxRunSpeedMetersPerSecond`
   - `blender.baseSpeedMetersPerSecond`
   - `blender.minPlaybackRate`
   - `blender.maxPlaybackRate`
2. 删除“单一步长”参数链路：
   - `cadence.strideLengthMetersPerStep`
   - `updateStrideLengthMetersPerStep(...)` 及调用点。

**Step 2: 更新 UI**
1. `RunnerTuningDebugView` 仅保留与新模型相关项（如 slow/fast 参考速度开关或只读展示）；  
2. 移除旧 Blend 文案，避免误导。

**Step 3: 验证**
Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`  
Expected: `BUILD SUCCEEDED`，且无已删除字段引用报错。

---

### P2：渲染主循环重构（动画 1x + 世界速度同源）

### Task 3：重写 `updateRunnerAnimation`，固定 slow/fast 为 1x

**Files:**
- Modify: `VibeSports/Services/Renderer/RunnerSceneRenderer.swift`

**Step 1: 动画权重改为新映射输出**
1. 移除旧的 `cadenceRate * duration` 速率计算；  
2. 改为：
   - `slowRunPlayer.blendFactor = mapper.slowRunWeight`
   - `fastRunPlayer.blendFactor = mapper.fastRunWeight`
   - `slowRunPlayer.speed = 1`
   - `fastRunPlayer.speed = 1`
3. 运行态不再进入 Idle 混合（仅 slow/fast）。

**Step 2: 验证**
1. 手测：在游戏中观察 slow/fast 切换过程无突跳；  
2. 手测：速度低于 slow 锚点时仍保持 slow 动画，而非 idle；  
3. 可选临时日志：打印 player speed，确认恒为 1.0（完成后删除日志）。

---

### Task 4：世界前进速度改为与动画同源速度（线性过渡 + 上下限夹紧）

**Files:**
- Modify: `VibeSports/Services/Renderer/RunnerSceneRenderer.swift`
- Optional Modify: `VibeSports/Models/Runner/RunnerNavigationIntegrator.swift`（仅当接口需最小调整）

**Step 1: 统一速度来源**
1. 每帧先得到输入速度（来自 `RunnerMotion.speedMetersPerSecond`）；  
2. 交给 `RunnerLocomotionMapper` 得到 `targetWorldSpeedMetersPerSecond`；  
3. 导航积分使用该 `targetWorldSpeed` 作为前进速度上限；  
4. 移除旧的“基于 cadence 合成速度 + keyboard fallback 纠缠”逻辑分支（不做兼容保留）。

**Step 2: 验证**
1. 手测：当 UI 速度跨越 4→9 区间时，画面前进速度与 slow/fast 混合同步变化；  
2. 手测：>9 不继续变快，<4 不进入 idle；  
3. 观察无明显脚滑感（以当前资源为准）。

---

### P3：回归、清理与文档同步

### Task 5：删除死代码并完成回归

**Files:**
- Modify: `VibeSports/Views/Settings/RunnerSettingsView.swift`（如需更新文案）
- Modify: `.github/docs/business-logic.md`（补充速度映射新规则）
- Modify: 其它受影响调用点（编译器报错驱动修复）

**Step 1: 清理**
1. 删除所有与旧 blend/rate/stride 单模型相关的注释、文案、未使用属性；  
2. 确保不存在 `RunnerAnimationBlender` 类型与旧字段引用。

**Step 2: 全量验证**
Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' build`  
Run: `xcodebuild -project VibeSports.xcodeproj -scheme VibeSports -destination 'platform=macOS' test`  
Expected: `BUILD SUCCEEDED` + `TEST SUCCEEDED`

---

## 执行顺序（建议）

1. Task 1（先立新模型并补测试）。  
2. Task 2（删旧字段与 UI，编译打通）。  
3. Task 3 + Task 4（渲染主循环重构，形成行为闭环）。  
4. Task 5（死代码清理 + 全量回归）。

## 边界与风险提示

1. 当前资源仅 slow/fast 两个跑步 clip，低速仍 slow 会有“跑姿偏积极”的视觉取舍，这是已确认需求。  
2. 动画 1x 固定后，体感主要由权重变化驱动；若后续需要更细腻低速表现，应新增 walk/idle 资产而不是恢复旧调速逻辑。  
3. 本计划是破坏性重构，执行时若出现依赖旧字段的外部脚本/文档，应一并删除或改写。
