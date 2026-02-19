# VibeSports 🏃🥊

VibeSports is a macOS-native “camera exercise game” prototype (Running + Boxing):
choose an exercise → calibrate → capture camera frames → estimate body pose with Apple Vision →
compute movement signals / speed / steps / punches →
drive a third-person SceneKit forest world (Running) or a full-screen camera debug UI (Boxing).

## Why

I want an app that nudges me to move while I’m working.
The best time to do that is during “waiting moments” in AI-assisted development
(e.g. when Codex / Claude Code / Cursor / GitHub Copilot is generating or applying changes).
When a reminder triggers, the app should pop up, turn on the camera, and track a short exercise set
like jumping jacks or squats—similar to fitness-tracking apps on phones, but optimized for the desktop workflow.

## Requirements

- macOS 14+
- Xcode (Swift 6 toolchain)
- A Mac with a camera

## How It Works (High-level)

- UI: SwiftUI
- State & orchestration: MVVM
- Async/event flow: Combine
- Pose estimation: Vision
- Rendering: SceneKit (third-person forest chunks + heading-based navigation)
- Control input: camera head sway / keyboard `WASD` / mixed
- Settings persistence: SwiftData
- Calibration (required):
  - Running: user selects `Upper Body` / `Full Body`, then must pass calibration to start
  - Boxing: must pass upper-body guard calibration to start punch detection
- Debug (optional): pose overlay + arm joint confidence overlay

More details: [business-logic.md](.github/docs/business-logic.md).

## Roadmap

See `.github/plans`.

## Contributing

Keep changes consistent with the repo layering rules in [AGENTS.md](AGENTS.md):
Views ↔ ViewModels ↔ Models ↔ Services, with dependencies flowing top-down.

## License

This project is licensed under the [AGPL-3.0 License](https://github.com/chiimagnus/chiimagnus.github.io/blob/main/LICENSE).
