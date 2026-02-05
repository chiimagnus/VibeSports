import Combine
import Foundation

@MainActor
final class RunnerGameSession: ObservableObject {
    let dependencies: AppDependencies
    let cameraSession: CameraSession
    let sceneRenderer: RunnerSceneRenderer

    @Published var userWeightKg: Double
    @Published private(set) var metrics: RunningMetricsSnapshot
    @Published private(set) var latestPose: Pose?

    private var runningMetrics = RunningMetrics()

    init(dependencies: AppDependencies, userWeightKg: Double) {
        self.dependencies = dependencies
        self.userWeightKg = userWeightKg
        self.cameraSession = CameraSession()
        self.sceneRenderer = RunnerSceneRenderer()
        self.metrics = RunningMetricsSnapshot(
            movementQualityPercent: 0,
            speedMetersPerSecond: 0,
            speedKilometersPerHour: 0,
            steps: 0,
            calories: 0,
            isCloseUpMode: false,
            debugText: "尚未开始"
        )

        cameraSession.onPose = { [weak self] pose in
            guard let self else { return }
            self.handlePose(pose)
        }
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

    private func handlePose(_ pose: Pose?) {
        latestPose = pose
        let snapshot = runningMetrics.ingest(
            pose: pose,
            now: dependencies.clock.now,
            userWeightKg: userWeightKg
        )
        metrics = snapshot
        sceneRenderer.setSpeedMetersPerSecond(snapshot.speedMetersPerSecond)
    }
}
