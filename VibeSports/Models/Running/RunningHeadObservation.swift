import Foundation

struct RunningHeadObservation: Sendable, Equatable {
    var noseX: Double
    var noseY: Double

    /// Face bounding box lower-left origin (Vision normalized coordinates 0...1).
    var faceMinX: Double
    var faceMinY: Double

    var faceWidth: Double
    var faceHeight: Double

    /// Nose landmark confidence in 0...1.
    var confidence: Double

    /// True only when a valid nose landmark is present.
    var isDetected: Bool

    init(
        noseX: Double,
        noseY: Double,
        faceMinX: Double = 0,
        faceMinY: Double = 0,
        faceWidth: Double,
        faceHeight: Double,
        confidence: Double,
        isDetected: Bool
    ) {
        self.noseX = noseX
        self.noseY = noseY
        self.faceMinX = min(1, max(0, faceMinX))
        self.faceMinY = min(1, max(0, faceMinY))
        self.faceWidth = max(0.0001, faceWidth)
        self.faceHeight = max(0.0001, faceHeight)
        self.confidence = min(1, max(0, confidence))
        self.isDetected = isDetected
    }
}
