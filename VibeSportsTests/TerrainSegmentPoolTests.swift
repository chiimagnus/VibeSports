import XCTest
@testable import VibeSports

final class TerrainSegmentPoolTests: XCTestCase {
    func test_initialSegmentsAreContiguous() {
        let pool = TerrainSegmentPool(activeSegments: 5, segmentLength: 10)
        XCTAssertEqual(pool.segments.map(\.startZ), [0, 10, 20, 30, 40])
        XCTAssertEqual(pool.lastGeneratedZ, 50)
    }

    func test_recycleKeepsCountConstantAndIncreasesLastGeneratedZ() {
        var pool = TerrainSegmentPool(activeSegments: 5, segmentLength: 10)

        let recycled = pool.recycleIfNeeded(cameraZ: 35)

        XCTAssertEqual(pool.segments.count, 5)
        XCTAssertEqual(recycled, [50])
        XCTAssertEqual(pool.segments.map(\.startZ), [10, 20, 30, 40, 50])
        XCTAssertEqual(pool.lastGeneratedZ, 60)
    }

    func test_recycleCanRecycleMultipleSegmentsWhenCameraJumps() {
        var pool = TerrainSegmentPool(activeSegments: 3, segmentLength: 10)

        let recycled = pool.recycleIfNeeded(cameraZ: 100)

        XCTAssertEqual(pool.segments.count, 3)
        XCTAssertGreaterThanOrEqual(recycled.count, 1)
        XCTAssertEqual(pool.lastGeneratedZ, pool.segments.last!.startZ + 10)
    }
}

