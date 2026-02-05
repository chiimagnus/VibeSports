import CoreVideo
import Vision

protocol PoseDetecting {
    func detect(in pixelBuffer: CVPixelBuffer) throws -> Pose?
}

final class PoseDetector {
    private let request: VNDetectHumanBodyPoseRequest
    private let handler = VNSequenceRequestHandler()

    init() {
        self.request = VNDetectHumanBodyPoseRequest()
    }

    func detect(in pixelBuffer: CVPixelBuffer) throws -> Pose? {
        try handler.perform([request], on: pixelBuffer)
        guard let observation = request.results?.first else { return nil }
        return try PoseDetector.makePose(from: observation)
    }

    private static func makePose(from observation: VNHumanBodyPoseObservation) throws -> Pose {
        let points = try observation.recognizedPoints(.all)

        var joints: [PoseJointName: PoseJoint] = [:]
        joints.reserveCapacity(PoseJointName.allCases.count)

        func assign(_ vnName: VNHumanBodyPoseObservation.JointName, _ name: PoseJointName) {
            guard let point = points[vnName], point.confidence > 0 else { return }
            joints[name] = PoseJoint(
                location: CGPoint(x: point.x, y: point.y),
                confidence: Double(point.confidence)
            )
        }

        assign(.leftShoulder, .leftShoulder)
        assign(.rightShoulder, .rightShoulder)
        assign(.leftElbow, .leftElbow)
        assign(.rightElbow, .rightElbow)
        assign(.leftWrist, .leftWrist)
        assign(.rightWrist, .rightWrist)
        assign(.leftHip, .leftHip)
        assign(.rightHip, .rightHip)
        assign(.leftKnee, .leftKnee)
        assign(.rightKnee, .rightKnee)
        assign(.leftAnkle, .leftAnkle)
        assign(.rightAnkle, .rightAnkle)

        return Pose(joints: joints)
    }
}

extension PoseDetector: PoseDetecting {}
