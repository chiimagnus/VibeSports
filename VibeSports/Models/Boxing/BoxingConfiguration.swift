import Foundation

struct BoxingConfiguration: Sendable, Equatable {
    var minJointConfidence: Double = 0.20

    /// Prevents double-counting when the fist jitters around the peak.
    var minPunchInterval: TimeInterval = 0.18

    /// The fist must move at least this far from neutral (normalized by shoulder distance) to count.
    var minNormalizedDistanceToArm: Double = 0.18

    /// When the fist returns within this normalized distance, the punch is considered ended.
    var returnNormalizedDistance: Double = 0.10

    /// If abs(dx) dominates abs(dy) and exceeds this threshold, classify as hook.
    var hookNormalizedDxThreshold: Double = 0.20

    /// If dy exceeds this threshold, classify as uppercut.
    var uppercutNormalizedDyThreshold: Double = 0.18

    /// If -dy exceeds this threshold, classify as overhand.
    var overhandNormalizedDyThreshold: Double = 0.18
}

