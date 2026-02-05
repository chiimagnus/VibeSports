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

    private let clock: any Clock
    private let settingsRepository: any SettingsRepository

    private var runningMetrics = RunningMetrics()
    private var userWeightKg: Double = 60

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

    func startTapped() {
        guard mode != .running else { return }
        mode = .running
        metrics.debugText = "正在准备摄像头"

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
            movementQualityPercent: 0,
            speedMetersPerSecond: 0,
            speedKilometersPerHour: 0,
            steps: 0,
            calories: 0,
            isCloseUpMode: false,
            debugText: "已结束"
        )
    }

    private func loadSettings() {
        do {
            let settings = try settingsRepository.load()
            userWeightKg = settings.userWeightKg
            showPoseOverlay = settings.showPoseOverlay
            mirrorCamera = settings.mirrorPoseOverlay
        } catch {
            userWeightKg = 60
            showPoseOverlay = false
            mirrorCamera = true
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
