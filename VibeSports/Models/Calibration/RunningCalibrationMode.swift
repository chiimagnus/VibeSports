enum RunningCalibrationMode: String, Sendable, CaseIterable, Equatable {
    case upperBody
    case fullBody

    var title: String {
        switch self {
        case .upperBody:
            return "Upper Body"
        case .fullBody:
            return "Full Body"
        }
    }
}

