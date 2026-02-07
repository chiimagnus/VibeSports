import Combine
import Foundation

@MainActor
final class RunnerGameViewModel: ObservableObject {
    enum Mode: Equatable {
        case idle
        case running
    }

    let cameraSession: CameraSession
    let sceneRenderer: RunnerSceneRenderer

    @Published private(set) var mode: Mode = .idle
    @Published private(set) var metrics: RunningMetricsSnapshot
    @Published private(set) var latestPose: Pose?

    @Published private(set) var showPoseOverlay: Bool = false
    @Published private(set) var mirrorCamera: Bool = true
    @Published private(set) var poseStabilizationEnabled: Bool = true
    @Published private(set) var stabilizedPose: Pose?

    private let clock: any Clock
    private let settingsRepository: any SettingsRepository

    private var runningMetrics = RunningMetrics()
    private var poseStabilizer = PoseStabilizer()

    private var cancellables: Set<AnyCancellable> = []

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
        updateCadenceMotionConfiguration(
            strideLengthMetersPerStep: cadence.strideLengthMetersPerStep,
            cadenceSmoothingAlpha: cadence.smoothingAlpha,
            cadenceTimeoutToZero: cadence.timeoutToZero
        )

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

    func startTapped() {
        guard mode != .running else { return }
        mode = .running

        Task { [weak self] in
            guard let self else { return }
            await cameraSession.start()
        }
    }

    func stopTapped() {
        guard mode != .idle else { return }
        stop()
        mode = .idle
    }

    func stopIfNeeded() {
        guard mode == .running else { return }
        stop()
        mode = .idle
    }

    private func stop() {
        cameraSession.stop()
        sceneRenderer.reset()
        runningMetrics.reset()
        latestPose = nil
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
        } catch {
            showPoseOverlay = false
            mirrorCamera = true
            poseStabilizationEnabled = true
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

    func updateCadenceMotionConfiguration(
        strideLengthMetersPerStep: Double,
        cadenceSmoothingAlpha: Double,
        cadenceTimeoutToZero: Double
    ) {
        runningMetrics.configuration.strideLengthMetersPerStep = max(0, strideLengthMetersPerStep)
        runningMetrics.configuration.cadenceConfiguration.smoothingAlpha = min(max(cadenceSmoothingAlpha, 0), 1)
        runningMetrics.configuration.cadenceConfiguration.timeoutToZero = max(0.1, cadenceTimeoutToZero)
    }

    private func handlePose(_ pose: Pose?) {
        latestPose = pose

        if poseStabilizationEnabled {
            stabilizedPose = poseStabilizer.ingest(pose: pose, now: clock.now)
        } else {
            stabilizedPose = pose
        }

        let snapshot = runningMetrics.ingest(
            pose: pose,
            now: clock.now
        )
        metrics = snapshot
        sceneRenderer.setMotion(snapshot.motion)
    }
}
