enum ExerciseSessionState: Sendable, Equatable {
    case idle(selectedKind: ExerciseKind)
    case calibrating(kind: ExerciseKind)
    case running(kind: ExerciseKind)

    var kind: ExerciseKind {
        switch self {
        case .idle(let selectedKind):
            return selectedKind
        case .calibrating(let kind), .running(let kind):
            return kind
        }
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}

