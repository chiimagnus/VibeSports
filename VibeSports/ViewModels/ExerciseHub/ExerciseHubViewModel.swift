import Combine
import Foundation

@MainActor
final class ExerciseHubViewModel: ObservableObject {
    let cameraSession: CameraSession
    let sceneRenderer: RunnerSceneRenderer

    @Published private(set) var sessionState: ExerciseSessionState = .idle(selectedKind: .running)
    @Published private(set) var metrics: RunningMetricsSnapshot
    @Published private(set) var latestPose: Pose?

    @Published private(set) var showPoseOverlay: Bool = false
    @Published private(set) var mirrorCamera: Bool = true
    @Published private(set) var poseStabilizationEnabled: Bool = true
    @Published private(set) var showPoseArmDebugOverlay: Bool = false
    @Published private(set) var stabilizedPose: Pose?

    @Published private(set) var showWorldAxes: Bool = false
    @Published private(set) var showRunnerAxes: Bool = false
    @Published private(set) var controlMode: RunnerControlComposer.Mode = .mixed

    private let clock: any Clock
    private let settingsRepository: any SettingsRepository

    private var runningMetrics = RunningMetrics()
    private var poseStabilizer = PoseStabilizer()
    private var headSteeringSignal = HeadSteeringSignal()
    private var keyboardDebugInputState = KeyboardDebugInputState()
    private var controlComposer = RunnerControlComposer(mode: .mixed)

    private var cancellables: Set<AnyCancellable> = []

    var selectedExerciseKind: ExerciseKind {
        sessionState.kind
    }

    init(dependencies: AppDependencies) {
        self.clock = dependencies.clock
        self.settingsRepository = dependencies.settingsRepository
        self.cameraSession = dependencies.makeCameraSession()
        self.sceneRenderer = dependencies.makeRunnerSceneRenderer()
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

        let cadence = sceneRenderer.tuning.cadence
        updateStrideLengthMetersPerStep(cadence.strideLengthMetersPerStep)

        poseStabilizer.configuration = poseStabilizer.configuration.withUpperBodyArmOverrides()
        headSteeringSignal.configuration.minConfidence = 0.20

        cameraSession.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        cameraSession.posePublisher
            .sink { [weak self] pose in
                self?.handlePose(pose)
            }
            .store(in: &cancellables)

        loadSettings()
    }

    func updateSelectedExerciseKind(_ kind: ExerciseKind) {
        guard sessionState.isIdle else { return }
        sessionState = .idle(selectedKind: kind)
    }

    func startTapped() {
        guard sessionState.isIdle else { return }
        let kind = sessionState.kind

        switch kind {
        case .running:
            sessionState = .running(kind: kind)
        case .boxing:
            // Placeholder: P1 will implement Boxing calibration + full-screen UI.
            sessionState = .calibrating(kind: kind)
        }

        Task { [weak self] in
            guard let self else { return }
            await cameraSession.start()
        }
    }

    func stopTapped() {
        guard !sessionState.isIdle else { return }
        let selectedKind = sessionState.kind
        stop()
        sessionState = .idle(selectedKind: selectedKind)
    }

    func stopIfNeeded() {
        guard !sessionState.isIdle else { return }
        let selectedKind = sessionState.kind
        stop()
        sessionState = .idle(selectedKind: selectedKind)
    }

    private func stop() {
        cameraSession.stop()
        sceneRenderer.reset()
        runningMetrics.reset()
        keyboardDebugInputState.reset()
        latestPose = nil
        stabilizedPose = nil
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

    private func loadSettings() {
        do {
            let settings = try settingsRepository.load()
            showPoseOverlay = settings.showPoseOverlay
            mirrorCamera = settings.mirrorPoseOverlay
            poseStabilizationEnabled = settings.poseStabilizationEnabled
            showPoseArmDebugOverlay = settings.showPoseArmDebugOverlay
        } catch {
            showPoseOverlay = false
            mirrorCamera = true
            poseStabilizationEnabled = true
            showPoseArmDebugOverlay = false
        }
    }

    func updateShowPoseOverlay(_ isEnabled: Bool) {
        showPoseOverlay = isEnabled
        do {
            try settingsRepository.updateShowPoseOverlay(isEnabled)
        } catch {}
    }

    func updateMirrorCamera(_ isEnabled: Bool) {
        mirrorCamera = isEnabled
        do {
            try settingsRepository.updateMirrorPoseOverlay(isEnabled)
        } catch {}
    }

    func updatePoseStabilizationEnabled(_ isEnabled: Bool) {
        poseStabilizationEnabled = isEnabled
        poseStabilizer.reset()
        stabilizedPose = nil
        pushCurrentControlMotion()
        do {
            try settingsRepository.updatePoseStabilizationEnabled(isEnabled)
        } catch {}
    }

    func updateShowPoseArmDebugOverlay(_ isEnabled: Bool) {
        showPoseArmDebugOverlay = isEnabled
        do {
            try settingsRepository.updateShowPoseArmDebugOverlay(isEnabled)
        } catch {}
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

    private func handlePose(_ pose: Pose?) {
        latestPose = pose

        if poseStabilizationEnabled {
            stabilizedPose = poseStabilizer.ingest(pose: pose, now: clock.now)
        } else {
            stabilizedPose = pose
        }

        let poseForControl = poseStabilizationEnabled ? stabilizedPose : pose

        guard !sessionState.isIdle else { return }
        guard sessionState.kind == .running else {
            // Avoid driving the running scene during Boxing placeholder flow.
            sceneRenderer.setMotion(.zero)
            return
        }

        let snapshot = runningMetrics.ingest(pose: pose, now: clock.now)
        metrics = snapshot
        sceneRenderer.setMotion(makeMotion(from: snapshot, pose: poseForControl))
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

    private func pushCurrentControlMotion() {
        guard sessionState.kind == .running else {
            sceneRenderer.setMotion(.zero)
            return
        }

        let poseForControl = poseStabilizationEnabled ? stabilizedPose : latestPose
        let motion = makeMotion(from: metrics, pose: poseForControl)
        sceneRenderer.setMotion(motion)
    }
}
