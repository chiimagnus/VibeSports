import Foundation

struct BoxingPunchEvent: Sendable, Equatable {
    struct Debug: Sendable, Equatable {
        var normalizedDx: Double
        var normalizedDy: Double
        var normalizedSpeed: Double
        var classifiedAs: BoxingPunchKind
    }

    var kind: BoxingPunchKind
    var timestamp: Date
    var debug: Debug?
}

