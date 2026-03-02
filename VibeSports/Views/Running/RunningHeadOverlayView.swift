import SwiftUI

struct RunningHeadOverlayView: View {
    let observation: RunningHeadObservation?
    var isMirroredHorizontally = false

    var body: some View {
        Canvas { context, size in
            guard let observation, observation.isDetected else { return }

            let xNorm = isMirroredHorizontally ? (1 - observation.noseX) : observation.noseX
            let yNorm = 1 - observation.noseY
            let nose = CGPoint(x: xNorm * size.width, y: yNorm * size.height)

            let dotRect = CGRect(x: nose.x - 4, y: nose.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: dotRect), with: .color(.pink.opacity(0.9)))

            let faceHeight = max(0.0001, observation.faceHeight)
            let guide = Path { path in
                path.move(to: nose)
                path.addLine(to: CGPoint(x: nose.x, y: nose.y + faceHeight * size.height))
            }
            context.stroke(
                guide,
                with: .color(.pink.opacity(0.55)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
        }
        .allowsHitTesting(false)
    }
}
