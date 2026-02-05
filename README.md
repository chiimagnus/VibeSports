# VibeSports 🏃

VibeSports is a macOS-native “camera running game” prototype:
start a session → capture camera frames → estimate body pose with Apple Vision →
compute movement quality / speed / steps → drive an infinite SceneKit runner scene.

## Requirements

- macOS 14+
- Xcode (Swift 6 toolchain)
- A Mac with a camera

## How It Works (High-level)

- UI: SwiftUI
- State & orchestration: MVVM
- Async/event flow: Combine
- Pose estimation: Vision
- Rendering: SceneKit (infinite track + camera motion)
- Settings persistence: SwiftData

More details: [business-logic.md](.github/docs/business-logic.md).

## Roadmap

See `.github/plans`.

## Contributing

Keep changes consistent with the repo layering rules in [AGENTS.md](AGENTS.md):
Views ↔ ViewModels ↔ Models ↔ Services, with dependencies flowing top-down.
