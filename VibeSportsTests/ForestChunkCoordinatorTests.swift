import XCTest
@testable import VibeSports

final class ForestChunkCoordinatorTests: XCTestCase {
    func test_activeChunksReturnsSquareGridCount() {
        let coordinator = ForestChunkCoordinator(
            configuration: .init(chunkSize: 10, activeRadius: 2)
        )

        let active = coordinator.activeChunks(aroundX: 0, z: 0)

        XCTAssertEqual(active.count, 25)
    }

    func test_chunkCoordinateChangesWhenCrossingBoundary() {
        let coordinator = ForestChunkCoordinator(
            configuration: .init(chunkSize: 10, activeRadius: 1)
        )

        let c0 = coordinator.chunkCoordinate(atX: 9.99, z: 0)
        let c1 = coordinator.chunkCoordinate(atX: 10.01, z: 0)

        XCTAssertEqual(c0, ForestChunkCoordinate(x: 0, z: 0))
        XCTAssertEqual(c1, ForestChunkCoordinate(x: 1, z: 0))
    }

    func test_activeChunksAreStableAndSorted() {
        let coordinator = ForestChunkCoordinator(
            configuration: .init(chunkSize: 8, activeRadius: 1)
        )

        let first = coordinator.activeChunks(aroundX: 3, z: 5)
        let second = coordinator.activeChunks(aroundX: 3, z: 5)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.first, ForestChunkCoordinate(x: -1, z: -1))
        XCTAssertEqual(first.last, ForestChunkCoordinate(x: 1, z: 1))
    }

    func test_centerReturnsHalfChunkOffset() {
        let coordinator = ForestChunkCoordinator(
            configuration: .init(chunkSize: 12, activeRadius: 1)
        )
        let center = coordinator.center(of: ForestChunkCoordinate(x: 2, z: -3))

        XCTAssertEqual(center.x, 30, accuracy: 0.0001)
        XCTAssertEqual(center.z, -30, accuracy: 0.0001)
    }
}
