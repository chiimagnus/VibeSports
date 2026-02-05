import Combine
import Foundation

@MainActor
final class RunnerGameSessionViewModel: ObservableObject {
    let cameraSession: CameraSession
    let sceneRenderer: RunnerSceneRenderer

    @Published private(set) var metrics: RunningMetricsSnapshot
    @Published private(set) var latestPose: Pose?

    @Published private(set) var userWeightKg: Double = 60
    @Published private(set) var showPoseOverlay: Bool = false
    @Published private(set) var mirrorPoseOverlay: Bool = false

    private let clock: any Clock
    private let settingsRepository: any SettingsRepository

    private var runningMetrics = RunningMetrics()
    private var cancellables: Set<AnyCancellable> = []

    init(dependencies: AppDependencies) {
        self.clock = dependencies.clock
        self.settingsRepository = dependencies.settingsRepository
        self.cameraSession = dependencies.makeCameraSession()
        self.sceneRenderer = dependencies.makeRunnerSceneRenderer()
        self.metrics = RunningMetricsSnapshot(
            movementQualityPercent: 0,
            speedMetersPerSecond: 0,
            speedKilometersPerHour: 0,
            steps: 0,
            calories: 0,
            isCloseUpMode: false,
            debugText: "尚未开始"
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

    func start() async {
        await cameraSession.start()
    }

    func stop() {
        cameraSession.stop()
        sceneRenderer.reset()
        runningMetrics.reset()
        metrics = RunningMetricsSnapshot(
            movementQualityPercent: 0,
            speedMetersPerSecond: 0,
            speedKilometersPerHour: 0,
            steps: 0,
            calories: 0,
            isCloseUpMode: false,
            debugText: "已结束"
        )
    }

    func updateUserWeightKg(_ weightKg: Double) {
        let clamped = max(0, weightKg)
        userWeightKg = clamped
        do {
            try settingsRepository.updateUserWeightKg(clamped)
        } catch {}
    }

    func updateShowPoseOverlay(_ isEnabled: Bool) {
        showPoseOverlay = isEnabled
        do {
            try settingsRepository.updateShowPoseOverlay(isEnabled)
        } catch {}
    }

    func updateMirrorPoseOverlay(_ isEnabled: Bool) {
        mirrorPoseOverlay = isEnabled
        do {
            try settingsRepository.updateMirrorPoseOverlay(isEnabled)
        } catch {}
    }

    private func loadSettings() {
        do {
            let settings = try settingsRepository.load()
            userWeightKg = settings.userWeightKg
            showPoseOverlay = settings.showPoseOverlay
            mirrorPoseOverlay = settings.mirrorPoseOverlay
        } catch {
            userWeightKg = 60
            showPoseOverlay = false
            mirrorPoseOverlay = false
        }
    }

    private func handlePose(_ pose: Pose?) {
        latestPose = pose
        let snapshot = runningMetrics.ingest(
            pose: pose,
            now: clock.now,
            userWeightKg: userWeightKg
        )
        metrics = snapshot
        sceneRenderer.setSpeedMetersPerSecond(snapshot.speedMetersPerSecond)
    }
}

