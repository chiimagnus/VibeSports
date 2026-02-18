import Combine
import Foundation

@MainActor
final class RunnerCommandCenter: ObservableObject {
    struct Snapshot: Equatable {
        var showPoseOverlay: Bool
        var mirrorCamera: Bool
        var poseStabilizationEnabled: Bool
        var showPoseArmDebugOverlay: Bool
        var showWorldAxes: Bool
        var showRunnerAxes: Bool
        var controlMode: RunnerControlComposer.Mode
    }

    struct Handlers {
        var updateShowPoseOverlay: (Bool) -> Void
        var updateMirrorCamera: (Bool) -> Void
        var updatePoseStabilizationEnabled: (Bool) -> Void
        var updateShowPoseArmDebugOverlay: (Bool) -> Void
        var updateShowWorldAxes: (Bool) -> Void
        var updateShowRunnerAxes: (Bool) -> Void
        var updateControlMode: (RunnerControlComposer.Mode) -> Void
    }

    @Published private(set) var isRunnerAttached = false
    @Published private(set) var showPoseOverlay = false
    @Published private(set) var mirrorCamera = true
    @Published private(set) var poseStabilizationEnabled = true
    @Published private(set) var showPoseArmDebugOverlay = false
    @Published private(set) var showWorldAxes = false
    @Published private(set) var showRunnerAxes = false
    @Published private(set) var controlMode: RunnerControlComposer.Mode = .mixed

    private var handlers: Handlers?

    func attach(snapshot: Snapshot, handlers: Handlers) {
        self.handlers = handlers
        apply(snapshot: snapshot)
        isRunnerAttached = true
    }

    func detach() {
        handlers = nil
        isRunnerAttached = false
    }

    func apply(snapshot: Snapshot) {
        showPoseOverlay = snapshot.showPoseOverlay
        mirrorCamera = snapshot.mirrorCamera
        poseStabilizationEnabled = snapshot.poseStabilizationEnabled
        showPoseArmDebugOverlay = snapshot.showPoseArmDebugOverlay
        showWorldAxes = snapshot.showWorldAxes
        showRunnerAxes = snapshot.showRunnerAxes
        controlMode = snapshot.controlMode
    }

    func setShowPoseOverlay(_ isEnabled: Bool) {
        showPoseOverlay = isEnabled
        handlers?.updateShowPoseOverlay(isEnabled)
    }

    func setMirrorCamera(_ isEnabled: Bool) {
        mirrorCamera = isEnabled
        handlers?.updateMirrorCamera(isEnabled)
    }

    func setPoseStabilizationEnabled(_ isEnabled: Bool) {
        poseStabilizationEnabled = isEnabled
        handlers?.updatePoseStabilizationEnabled(isEnabled)
    }

    func setShowPoseArmDebugOverlay(_ isEnabled: Bool) {
        showPoseArmDebugOverlay = isEnabled
        handlers?.updateShowPoseArmDebugOverlay(isEnabled)
    }

    func setShowWorldAxes(_ isEnabled: Bool) {
        showWorldAxes = isEnabled
        handlers?.updateShowWorldAxes(isEnabled)
    }

    func setShowRunnerAxes(_ isEnabled: Bool) {
        showRunnerAxes = isEnabled
        handlers?.updateShowRunnerAxes(isEnabled)
    }

    func setControlMode(_ mode: RunnerControlComposer.Mode) {
        controlMode = mode
        handlers?.updateControlMode(mode)
    }
}
