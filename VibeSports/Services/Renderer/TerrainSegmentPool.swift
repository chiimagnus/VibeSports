import Foundation

struct TerrainSegmentPool: Sendable, Equatable {
    struct Segment: Sendable, Equatable {
        var startZ: Double
    }

    let segmentLength: Double
    private(set) var segments: [Segment]
    private(set) var lastGeneratedZ: Double

    init(activeSegments: Int, segmentLength: Double) {
        precondition(activeSegments > 0)
        precondition(segmentLength > 0)

        self.segmentLength = segmentLength
        self.segments = (0..<activeSegments).map { Segment(startZ: Double($0) * segmentLength) }
        self.lastGeneratedZ = Double(activeSegments) * segmentLength
    }

    mutating func recycleIfNeeded(cameraZ: Double) -> [Double] {
        var recycled: [Double] = []

        while cameraZ + segmentLength > (lastGeneratedZ - segmentLength) {
            let newStartZ = lastGeneratedZ
            lastGeneratedZ += segmentLength

            _ = segments.removeFirst()
            segments.append(Segment(startZ: newStartZ))
            recycled.append(newStartZ)
        }

        return recycled
    }
}

