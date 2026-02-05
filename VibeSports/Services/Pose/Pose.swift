import CoreGraphics

enum PoseJointName: String, Sendable, CaseIterable {
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
}

struct PoseJoint: Sendable, Equatable {
    var location: CGPoint
    var confidence: Double
}

struct Pose: Sendable, Equatable {
    var joints: [PoseJointName: PoseJoint]

    func joint(_ name: PoseJointName) -> PoseJoint? {
        joints[name]
    }
}

