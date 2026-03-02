import CoreVideo
import Vision

protocol RunningHeadDetecting {
    func detect(in pixelBuffer: CVPixelBuffer) throws -> RunningHeadObservation?
}

final class RunningHeadDetector: RunningHeadDetecting {
    private let handler = VNSequenceRequestHandler()
    private let faceRectanglesRequest = VNDetectFaceRectanglesRequest()

    func detect(in pixelBuffer: CVPixelBuffer) throws -> RunningHeadObservation? {
        try handler.perform([faceRectanglesRequest], on: pixelBuffer)

        guard
            let faces = faceRectanglesRequest.results,
            let face = faces.max(by: { lhs, rhs in
                (lhs.boundingBox.width * lhs.boundingBox.height) < (rhs.boundingBox.width * rhs.boundingBox.height)
            })
        else {
            return nil
        }

        let landmarksRequest = VNDetectFaceLandmarksRequest()
        landmarksRequest.inputFaceObservations = [face]
        try handler.perform([landmarksRequest], on: pixelBuffer)

        guard
            let observation = landmarksRequest.results?.first,
            let landmarks = observation.landmarks
        else {
            return nil
        }

        guard let noseRegion = landmarks.nose ?? landmarks.noseCrest else {
            return nil
        }

        let points = noseRegion.normalizedPoints
        guard !points.isEmpty else {
            return nil
        }

        var sumX: Double = 0
        var sumY: Double = 0
        for point in points {
            sumX += Double(point.x)
            sumY += Double(point.y)
        }
        let avgX = sumX / Double(points.count)
        let avgY = sumY / Double(points.count)

        let box = observation.boundingBox
        let noseX = Double(box.origin.x) + avgX * Double(box.size.width)
        let noseY = Double(box.origin.y) + avgY * Double(box.size.height)

        return RunningHeadObservation(
            noseX: noseX,
            noseY: noseY,
            faceWidth: Double(box.size.width),
            faceHeight: Double(box.size.height),
            confidence: Double(observation.confidence),
            isDetected: true
        )
    }
}

