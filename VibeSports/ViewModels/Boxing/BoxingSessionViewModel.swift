import Combine
import Foundation

@MainActor
final class BoxingSessionViewModel: ObservableObject {
    enum State: Equatable {
        case calibrating(progress: Double, message: String)
        case running(baseline: BoxingCalibrationBaseline)
    }

    @Published private(set) var state: State
    @Published private(set) var lastEvent: BoxingPunchEvent?
    @Published private(set) var counts: [BoxingPunchKind: Int] = [:]

    var configuration = BoxingConfiguration()

    private let clock: any Clock
    private var calibration = UpperBodyCalibration(configuration: .init(mode: .boxingGuard))
    private var detector = BoxingPunchDetector()

    init(clock: any Clock) {
        self.clock = clock
        self.state = .calibrating(progress: 0, message: UpperBodyCalibration.Issue.noPose.message)
    }

    func reset() {
        calibration = UpperBodyCalibration(configuration: .init(mode: .boxingGuard))
        detector = BoxingPunchDetector()
        detector.configuration = configuration
        lastEvent = nil
        counts = [:]
        state = .calibrating(progress: 0, message: UpperBodyCalibration.Issue.noPose.message)
    }

    func ingest(pose: Pose?) {
        let now = clock.now

        detector.configuration = configuration

        switch state {
        case .calibrating:
            let output = calibration.ingest(pose: pose, now: now)
            if let baseline = output.baseline {
                let boxingBaseline = BoxingCalibrationBaseline(upperBodyBaseline: baseline)
                state = .running(baseline: boxingBaseline)
                return
            }

            let message = output.issue?.message ?? "Calibrating…"
            state = .calibrating(progress: output.progress, message: message)

        case .running(let baseline):
            if let event = detector.ingest(pose: pose, baseline: baseline, now: now) {
                lastEvent = event
                counts[event.kind, default: 0] += 1
            }
        }
    }
}
