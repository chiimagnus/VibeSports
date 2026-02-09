import Foundation

struct ForestChunkCoordinate: Hashable, Sendable, Comparable {
    let x: Int
    let z: Int

    static func < (lhs: ForestChunkCoordinate, rhs: ForestChunkCoordinate) -> Bool {
        if lhs.z == rhs.z {
            return lhs.x < rhs.x
        }
        return lhs.z < rhs.z
    }
}

struct ForestChunkCoordinator: Sendable, Equatable {
    struct Configuration: Sendable, Equatable {
        var chunkSize: Double = 12
        var activeRadius: Int = 2
    }

    var configuration = Configuration()

    func chunkCoordinate(atX x: Double, z: Double) -> ForestChunkCoordinate {
        let size = max(0.0001, configuration.chunkSize)
        let cx = Int(floor(x / size))
        let cz = Int(floor(z / size))
        return ForestChunkCoordinate(x: cx, z: cz)
    }

    func activeChunks(aroundX x: Double, z: Double) -> [ForestChunkCoordinate] {
        let center = chunkCoordinate(atX: x, z: z)
        let radius = max(0, configuration.activeRadius)

        var result: [ForestChunkCoordinate] = []
        result.reserveCapacity((radius * 2 + 1) * (radius * 2 + 1))

        for dz in -radius...radius {
            for dx in -radius...radius {
                result.append(
                    ForestChunkCoordinate(
                        x: center.x + dx,
                        z: center.z + dz
                    )
                )
            }
        }
        result.sort()
        return result
    }

    func center(of coordinate: ForestChunkCoordinate) -> (x: Double, z: Double) {
        let size = max(0.0001, configuration.chunkSize)
        return (
            x: (Double(coordinate.x) + 0.5) * size,
            z: (Double(coordinate.z) + 0.5) * size
        )
    }
}
