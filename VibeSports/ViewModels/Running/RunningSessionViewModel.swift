import Combine
import Foundation

@MainActor
final class RunningSessionViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case calibrating(progress: Double, message: String)
        case running
    }

    let sceneRenderer: RunnerSceneRenderer

    @Published private(set) var state: State = .idle
    @Published private(set) var metrics: RunningMetricsSnapshot

    @Published private(set) var showWorldAxes: Bool = false
    @Published private(set) var showRunnerAxes: Bool = false
    @Published private(set) var controlMode: RunnerControlComposer.Mode = .mixed

    private let clock: any Clock

    private var runningMetrics = RunningMetrics()

    private var latestHeadObservation: RunningHeadObservation?

    private var headSteeringSignal = RunningHeadSteeringSignal()
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

    func start() {
        runningMetrics.reset()
        keyboardDebugInputState.reset()
        latestHeadObservation = nil

        state = .running

        sceneRenderer.reset()
        sceneRenderer.setMotion(.zero)
    }

    func stop() {
        state = .idle
        sceneRenderer.reset()
        runningMetrics.reset()
        keyboardDebugInputState.reset()
        latestHeadObservation = nil

        metrics = RunningMetricsSnapshot(
            poseDetected: false,
            movementQualityPercent: 0,
            cadenceStepsPerSecond: 0,
            cadenceStepsPerMinute: 0,
            speedMetersPerSecond: 0,
            steps: 0,
            isCloseUpMode: false,
            shoulderDistance: nil
        )
    }

    func ingest(headObservation: RunningHeadObservation?) {
        latestHeadObservation = headObservation
        let now = clock.now

        switch state {
        case .idle:
            return

        case .calibrating:
            state = .running
            return

        case .running:
            let snapshot = runningMetrics.ingest(observation: headObservation, now: now)
            metrics = snapshot
            sceneRenderer.setMotion(makeMotion(from: snapshot, headObservation: headObservation))
        }
    }

    func pushCurrentControlMotion() {
        guard case .running = state else {
            sceneRenderer.setMotion(.zero)
            return
        }

        let motion = makeMotion(from: metrics, headObservation: latestHeadObservation)
        sceneRenderer.setMotion(motion)
    }

    private func makeMotion(from snapshot: RunningMetricsSnapshot, headObservation: RunningHeadObservation?) -> RunnerMotion {
        let cameraInput = RunnerControlInput(
            turnInput: headSteeringSignal.turnInput(from: headObservation),
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
