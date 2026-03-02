import Combine
import Foundation

@MainActor
final class ExerciseHubViewModel: ObservableObject {
    let cameraSession: CameraSession
    let runningSession: RunningSessionViewModel

    @Published private(set) var sessionState: ExerciseSessionState = .idle(selectedKind: .running)
    @Published private(set) var latestPose: Pose?
    @Published private(set) var boxingSession: BoxingSessionViewModel?

    @Published private(set) var showPoseOverlay: Bool = false
    @Published private(set) var mirrorCamera: Bool = true
    @Published private(set) var poseStabilizationEnabled: Bool = true
    @Published private(set) var showPoseArmDebugOverlay: Bool = false
    @Published private(set) var stabilizedPose: Pose?

    private let clock: any Clock
    private let settingsRepository: any SettingsRepository
    private var poseStabilizer = PoseStabilizer()

    private var cancellables: Set<AnyCancellable> = []

    var selectedExerciseKind: ExerciseKind {
        sessionState.kind
    }

    init(dependencies: AppDependencies) {
        self.clock = dependencies.clock
        self.settingsRepository = dependencies.settingsRepository
        self.cameraSession = dependencies.makeCameraSession()
        self.runningSession = dependencies.makeRunningSessionViewModel()

        let cadence = runningSession.sceneRenderer.tuning.cadence
        updateStrideLengthMetersPerStep(cadence.strideLengthMetersPerStep)

        poseStabilizer.configuration = poseStabilizer.configuration.withUpperBodyArmOverrides()

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

        cameraSession.runningHeadPublisher
            .sink { [weak self] observation in
                self?.handleRunningHead(observation)
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
            boxingSession = nil
            cameraSession.setAnalysisMode(.runningHeadOnly)
            runningSession.start()
            sessionState = .running(kind: .running)
        case .boxing:
            boxingSession = BoxingSessionViewModel(clock: clock)
            cameraSession.setAnalysisMode(.boxingPose)
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
        runningSession.stop()
        boxingSession = nil
        latestPose = nil
        stabilizedPose = nil
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

    func handleKeyDown(_ key: KeyboardDebugInputState.Key) {
        runningSession.handleKeyDown(key)
    }

    func handleKeyUp(_ key: KeyboardDebugInputState.Key) {
        runningSession.handleKeyUp(key)
    }

    func handleBoostModifierChanged(_ isPressed: Bool) {
        runningSession.handleBoostModifierChanged(isPressed)
    }

    func resetKeyboardInput() {
        runningSession.resetKeyboardInput()
    }

    func updateStrideLengthMetersPerStep(_ strideLengthMetersPerStep: Double) {
        runningSession.updateStrideLengthMetersPerStep(strideLengthMetersPerStep)
    }

    private func handlePose(_ pose: Pose?) {
        latestPose = pose

        if sessionState.kind == .boxing, !sessionState.isIdle {
            if poseStabilizationEnabled {
                stabilizedPose = poseStabilizer.ingest(pose: pose, now: clock.now)
            } else {
                stabilizedPose = pose
            }

            let poseForControl = poseStabilizationEnabled ? stabilizedPose : pose
            boxingSession?.ingest(pose: poseForControl)
            runningSession.sceneRenderer.setMotion(.zero)
        } else {
            stabilizedPose = nil
        }
    }

    private func handleRunningHead(_ observation: RunningHeadObservation?) {
        guard !sessionState.isIdle, sessionState.kind == .running else { return }
        runningSession.ingest(headObservation: observation)
    }
}
