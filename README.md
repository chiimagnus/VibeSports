# VibeSports 🏃🥊

VibeSports is a macOS-native “camera exercise game” prototype (Running + Boxing):
choose a mode in the Home window → click Start → open the Exercise window → capture camera frames →
estimate (Running: face landmarks; Boxing: body pose) with Apple Vision →
compute movement signals / steps / cadence / punches →
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
- Vision input:
  - Running: face landmarks (nose Y bobbing)
  - Boxing: body pose joints
- Rendering: SceneKit (third-person forest chunks + heading-based navigation)
- Control input: camera head sway / keyboard `WASD` / mixed
- Settings persistence: SwiftData
- Calibration (required): Boxing guard calibration (required for punch detection)
- Debug (optional):
  - Running: face box + nose overlay
  - Boxing: pose overlay + arm joint confidence overlay
- Ending a session: close the Exercise window (the Home window will return)

More details: [business-logic.md](.github/docs/business-logic.md).

## Roadmap

See `.github/plans`.

## Contributing

Keep changes consistent with the repo layering rules in [AGENTS.md](AGENTS.md):
Views ↔ ViewModels ↔ Models ↔ Services, with dependencies flowing top-down.

## License

This project is licensed under the [AGPL-3.0 License](LICENSE).
