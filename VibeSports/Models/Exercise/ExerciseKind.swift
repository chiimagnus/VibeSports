enum ExerciseKind: String, Sendable, CaseIterable, Equatable {
    case running
    case boxing

    var title: String {
        switch self {
        case .running:
            return "Running"
        case .boxing:
            return "Boxing"
        }
    }
}

