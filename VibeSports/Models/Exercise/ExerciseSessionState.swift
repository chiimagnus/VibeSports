enum ExerciseSessionState: Sendable, Equatable {
    case idle(selectedKind: ExerciseKind, runningCalibrationMode: RunningCalibrationMode?)
    case calibrating(kind: ExerciseKind, runningCalibrationMode: RunningCalibrationMode?)
    case running(kind: ExerciseKind, runningCalibrationMode: RunningCalibrationMode?)

    var kind: ExerciseKind {
        switch self {
        case .idle(let selectedKind, _):
            return selectedKind
        case .calibrating(let kind, _), .running(let kind, _):
            return kind
        }
    }

    var runningCalibrationMode: RunningCalibrationMode {
        switch self {
        case .idle(_, let mode):
            return mode ?? .upperBody
        case .calibrating(_, let mode):
            return mode ?? .upperBody
        case .running(_, let mode):
            return mode ?? .upperBody
        }
    }

    var rawRunningCalibrationMode: RunningCalibrationMode? {
        switch self {
        case .idle(_, let mode):
            return mode
        case .calibrating(_, let mode):
            return mode
        case .running(_, let mode):
            return mode
        }
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}
