import SwiftUI

struct PoseOverlayView: View {
    let pose: Pose
    var isMirroredHorizontally = false

    var body: some View {
        Canvas { context, size in
            let points = PoseOverlayGeometry.points(in: size, pose: pose, mirrored: isMirroredHorizontally)

            var skeletonPath = Path()
            for edge in PoseOverlayGeometry.edges {
                guard let p0 = points[edge.0], let p1 = points[edge.1] else { continue }
                skeletonPath.move(to: p0)
                skeletonPath.addLine(to: p1)
            }

            context.stroke(
                skeletonPath,
                with: .color(.cyan.opacity(0.85)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            for (_, p) in points {
                let rect = CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: rect), with: .color(.yellow.opacity(0.9)))
            }
        }
        .allowsHitTesting(false)
    }
}

private enum PoseOverlayGeometry {
    static let edges: [(PoseJointName, PoseJointName)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),

        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),
    ]

    static func points(in size: CGSize, pose: Pose, mirrored: Bool) -> [PoseJointName: CGPoint] {
        var result: [PoseJointName: CGPoint] = [:]
        result.reserveCapacity(PoseJointName.allCases.count)

        for name in PoseJointName.allCases {
            guard let joint = pose.joint(name), joint.confidence > 0.3 else { continue }
            let x = mirrored ? (1 - joint.location.x) : joint.location.x
            let y = 1 - joint.location.y
            result[name] = CGPoint(x: x * size.width, y: y * size.height)
        }
        return result
    }
}

