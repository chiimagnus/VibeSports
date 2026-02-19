import Combine
import Foundation

@MainActor
final class RunningSessionViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case calibrating(mode: RunningCalibrationMode, progress: Double, message: String)
        case running(mode: RunningCalibrationMode)
    }

    let sceneRenderer: RunnerSceneRenderer

    @Published private(set) var state: State = .idle
    @Published private(set) var metrics: RunningMetricsSnapshot

    @Published private(set) var showWorldAxes: Bool = false
    @Published private(set) var showRunnerAxes: Bool = false
    @Published private(set) var controlMode: RunnerControlComposer.Mode = .mixed

    private let clock: any Clock

    private var runningMetrics = RunningMetrics()
    private var upperBodyCalibration = UpperBodyCalibration(configuration: .init(mode: .generic))
    private var fullBodyCalibration = FullBodyCalibration()

    private var latestControlPose: Pose?

    private var headSteeringSignal = HeadSteeringSignal()
    private var keyboardDebugInputState = KeyboardDebugInputState()
    private var controlComposer = RunnerControlComposer(mode: .mixed)

    init(clock: any Clock, sceneRenderer: RunnerSceneRenderer) {
        self.clock = clock
        self.sceneRenderer = sceneRenderer
        self.metrics = RunningMetricsSnapshot(
            poseDetected: false,
            movementQualityPercent: 0,
            cadenceStepsPerSecond: 0,
            cadenceStepsPerMinute: 0,
            speedMetersPerSecond: 0,
            speedKilometersPerHour: 0,
            steps: 0,
            isCloseUpMode: false,
            shoulderDistance: nil
        )

        headSteeringSignal.configuration.minConfidence = 0.20
    }

    func updateShowWorldAxes(_ isEnabled: Bool) {
        showWorldAxes = isEnabled
        sceneRenderer.setShowWorldAxes(isEnabled)
    }

    func updateShowRunnerAxes(_ isEnabled: Bool) {
        showRunnerAxes = isEnabled
        sceneRenderer.setShowRunnerAxes(isEnabled)
    }

    func updateControlMode(_ mode: RunnerControlComposer.Mode) {
        controlMode = mode
        controlComposer.mode = mode
        pushCurrentControlMotion()
    }

    func handleKeyDown(_ key: KeyboardDebugInputState.Key) {
        keyboardDebugInputState.keyDown(key)
        pushCurrentControlMotion()
    }

    func handleKeyUp(_ key: KeyboardDebugInputState.Key) {
        keyboardDebugInputState.keyUp(key)
        pushCurrentControlMotion()
    }

    func handleBoostModifierChanged(_ isPressed: Bool) {
        keyboardDebugInputState.setBoostPressed(isPressed)
        pushCurrentControlMotion()
    }

    func resetKeyboardInput() {
        keyboardDebugInputState.reset()
        pushCurrentControlMotion()
    }

    func updateStrideLengthMetersPerStep(_ strideLengthMetersPerStep: Double) {
        runningMetrics.configuration.strideLengthMetersPerStep = max(0, strideLengthMetersPerStep)
    }

    func start(mode: RunningCalibrationMode) {
        runningMetrics.reset()
        keyboardDebugInputState.reset()
        latestControlPose = nil

        upperBodyCalibration.reset()
        fullBodyCalibration.reset()

        switch mode {
        case .upperBody:
            state = .calibrating(mode: mode, progress: 0, message: "Calibrating…")
        case .fullBody:
            state = .calibrating(mode: mode, progress: 0, message: "Calibrating…")
        }

        sceneRenderer.reset()
        sceneRenderer.setMotion(.zero)
    }

    func stop() {
        state = .idle
        sceneRenderer.reset()
        runningMetrics.reset()
        keyboardDebugInputState.reset()
        latestControlPose = nil

        metrics = RunningMetricsSnapshot(
            poseDetected: false,
            movementQualityPercent: 0,
            cadenceStepsPerSecond: 0,
            cadenceStepsPerMinute: 0,
            speedMetersPerSecond: 0,
            speedKilometersPerHour: 0,
            steps: 0,
            isCloseUpMode: false,
            shoulderDistance: nil
        )
    }

    func ingest(rawPose: Pose?, controlPose: Pose?) {
        latestControlPose = controlPose
        let now = clock.now

        switch state {
        case .idle:
            return

        case .calibrating(let mode, _, _):
            switch mode {
            case .upperBody:
                let out = upperBodyCalibration.ingest(pose: controlPose, now: now)
                if out.baseline != nil {
                    state = .running(mode: mode)
                    return
                }
                state = .calibrating(mode: mode, progress: out.progress, message: (out.issue?.message ?? "Calibrating…"))

            case .fullBody:
                let out = fullBodyCalibration.ingest(pose: controlPose, now: now)
                if out.baseline != nil {
                    state = .running(mode: mode)
                    return
                }
                state = .calibrating(mode: mode, progress: out.progress, message: (out.issue?.message ?? "Calibrating…"))
            }

            sceneRenderer.setMotion(.zero)
            return

        case .running:
            let snapshot = runningMetrics.ingest(pose: rawPose, now: now)
            metrics = snapshot
            sceneRenderer.setMotion(makeMotion(from: snapshot, pose: controlPose))
        }
    }

    func pushCurrentControlMotion() {
        guard case .running = state else {
            sceneRenderer.setMotion(.zero)
            return
        }

        let motion = makeMotion(from: metrics, pose: latestControlPose)
        sceneRenderer.setMotion(motion)
    }

    private func makeMotion(from snapshot: RunningMetricsSnapshot, pose: Pose?) -> RunnerMotion {
        let cameraInput = RunnerControlInput(
            turnInput: headSteeringSignal.turnInput(from: pose),
            forwardInput: snapshot.speedMetersPerSecond > 0.05 ? 1 : 0
        )
        let keyboardInput = keyboardDebugInputState.controlInput
        let controlInput = controlComposer.compose(
            cameraInput: cameraInput,
            keyboardInput: keyboardInput
        )

        return RunnerMotion(
            speedMetersPerSecond: snapshot.speedMetersPerSecond,
            cadenceStepsPerSecond: snapshot.cadenceStepsPerSecond,
            cadenceStepsPerMinute: snapshot.cadenceStepsPerMinute,
            forwardInput: controlInput.forwardInput,
            turnInput: controlInput.turnInput,
            headingYaw: 0
        )
    }
}

