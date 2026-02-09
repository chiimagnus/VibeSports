import AppKit
import SceneKit

struct ForestChunkNodeFactory {
    struct Configuration: Sendable, Equatable {
        var chunkSize: Double = 12
        var treesPerChunk: Int = 30
        var treeInset: Double = 0.8
    }

    var configuration = Configuration()

    private let assets = ForestDecorationAssets()

    func makeChunkNode(
        coordinate: ForestChunkCoordinate,
        centerX: Double,
        centerZ: Double
    ) -> SCNNode {
        let node = SCNNode()
        node.name = chunkNodeName(for: coordinate)
        node.position = SCNVector3(CGFloat(centerX), 0, CGFloat(centerZ))

        let chunkSize = max(1, configuration.chunkSize)
        let halfSize = chunkSize / 2

        let ground = SCNBox(
            width: chunkSize,
            height: 0.16,
            length: chunkSize,
            chamferRadius: 0
        )
        ground.materials = [assets.groundMaterial]

        let groundNode = SCNNode(geometry: ground)
        groundNode.position = SCNVector3(0, -0.08, 0)
        groundNode.physicsBody = .static()
        node.addChildNode(groundNode)

        let decorationsNode = SCNNode()
        decorationsNode.name = "chunkDecorations"
        node.addChildNode(decorationsNode)

        let inset = min(max(0, configuration.treeInset), halfSize - 0.1)
        let minOffset = -(halfSize - inset)
        let maxOffset = halfSize - inset
        let treeCount = max(0, configuration.treesPerChunk)

        for index in 0..<treeCount {
            let treeNode = assets.makeTreeNode()
            let xSeed = seed(for: coordinate, index: index, salt: 11)
            let zSeed = seed(for: coordinate, index: index, salt: 23)
            let rSeed = seed(for: coordinate, index: index, salt: 37)
            let sSeed = seed(for: coordinate, index: index, salt: 53)

            let localX = lerp(minOffset, maxOffset, randomUnit(seed: xSeed))
            let localZ = lerp(minOffset, maxOffset, randomUnit(seed: zSeed))
            let yaw = lerp(0, 2 * Double.pi, randomUnit(seed: rSeed))
            let scale = lerp(0.75, 1.35, randomUnit(seed: sSeed))

            treeNode.position = SCNVector3(CGFloat(localX), 0, CGFloat(localZ))
            treeNode.eulerAngles.y = CGFloat(yaw)
            treeNode.scale = SCNVector3(CGFloat(scale), CGFloat(scale), CGFloat(scale))
            decorationsNode.addChildNode(treeNode)
        }

        return node
    }

    func chunkNodeName(for coordinate: ForestChunkCoordinate) -> String {
        "forestChunk_\(coordinate.x)_\(coordinate.z)"
    }

    private func seed(
        for coordinate: ForestChunkCoordinate,
        index: Int,
        salt: UInt64
    ) -> UInt64 {
        var value = UInt64(bitPattern: Int64(coordinate.x))
        value &*= 0x9E37_79B9_7F4A_7C15
        value ^= UInt64(bitPattern: Int64(coordinate.z)) &* 0xBF58_476D_1CE4_E5B9
        value ^= UInt64(bitPattern: Int64(index)) &* 0x94D0_49BB_1331_11EB
        value ^= salt &* 0xD2B7_4407_B1CE_6E93
        return value
    }

    private func randomUnit(seed: UInt64) -> Double {
        var x = seed &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x = x ^ (x >> 31)
        let maxValue = Double(UInt64.max)
        return Double(x) / maxValue
    }

    private func lerp(_ minValue: Double, _ maxValue: Double, _ t: Double) -> Double {
        minValue + (maxValue - minValue) * t
    }
}

private final class ForestDecorationAssets {
    let groundMaterial: SCNMaterial

    private let trunkGeometry: SCNCylinder
    private let crownGeometry: SCNCone
    private let trunkMaterial: SCNMaterial
    private let crownMaterial: SCNMaterial

    init() {
        trunkGeometry = SCNCylinder(radius: 0.06, height: 0.5)
        crownGeometry = SCNCone(topRadius: 0, bottomRadius: 0.22, height: 0.55)

        trunkMaterial = SCNMaterial()
        trunkMaterial.diffuse.contents = NSColor(calibratedRed: 0.32, green: 0.23, blue: 0.16, alpha: 1)
        trunkMaterial.roughness.contents = 1.0
        trunkMaterial.metalness.contents = 0.0

        crownMaterial = SCNMaterial()
        crownMaterial.diffuse.contents = NSColor(calibratedRed: 0.14, green: 0.54, blue: 0.22, alpha: 1)
        crownMaterial.roughness.contents = 0.95
        crownMaterial.metalness.contents = 0.0

        groundMaterial = SCNMaterial()
        groundMaterial.diffuse.contents = NSColor(calibratedRed: 0.20, green: 0.34, blue: 0.18, alpha: 1)
        groundMaterial.roughness.contents = 1.0
        groundMaterial.metalness.contents = 0.0

        trunkGeometry.materials = [trunkMaterial]
        crownGeometry.materials = [crownMaterial]
    }

    func makeTreeNode() -> SCNNode {
        let trunkNode = SCNNode(geometry: trunkGeometry)
        trunkNode.position = SCNVector3(0, 0.25, 0)

        let crownNode = SCNNode(geometry: crownGeometry)
        crownNode.position = SCNVector3(0, 0.78, 0)

        let node = SCNNode()
        node.addChildNode(trunkNode)
        node.addChildNode(crownNode)
        return node
    }
}
