import CoreGraphics

struct BoxingCalibrationBaseline: Sendable, Equatable {
    var leftNeutralWrist: CGPoint
    var rightNeutralWrist: CGPoint
    var shoulderDistance: Double

    init(leftNeutralWrist: CGPoint, rightNeutralWrist: CGPoint, shoulderDistance: Double) {
        self.leftNeutralWrist = leftNeutralWrist
        self.rightNeutralWrist = rightNeutralWrist
        self.shoulderDistance = shoulderDistance
    }

    init(upperBodyBaseline: UpperBodyCalibration.Baseline) {
        self.init(
            leftNeutralWrist: upperBodyBaseline.leftWrist,
            rightNeutralWrist: upperBodyBaseline.rightWrist,
            shoulderDistance: upperBodyBaseline.shoulderDistance
        )
    }
}

