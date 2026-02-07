import AppKit
import SceneKit

enum SceneDebugAxes {
    static func makeAxesNode(
        length: CGFloat = 1.5,
        thickness: CGFloat = 0.02,
        opacity: CGFloat = 0.9
    ) -> SCNNode {
        let root = SCNNode()
        root.name = "debugAxes"

        func makeMaterial(color: NSColor) -> SCNMaterial {
            let material = SCNMaterial()
            material.diffuse.contents = color.withAlphaComponent(opacity)
            material.emission.contents = color.withAlphaComponent(opacity * 0.35)
            material.lightingModel = .blinn
            material.isDoubleSided = true
            return material
        }

        let xMaterial = makeMaterial(color: .systemRed)
        let yMaterial = makeMaterial(color: .systemGreen)
        let zMaterial = makeMaterial(color: .systemBlue)

        let x = SCNBox(width: length, height: thickness, length: thickness, chamferRadius: 0)
        x.materials = [xMaterial]
        let xNode = SCNNode(geometry: x)
        xNode.name = "x"
        xNode.position = SCNVector3(length / 2, 0, 0)

        let y = SCNBox(width: thickness, height: length, length: thickness, chamferRadius: 0)
        y.materials = [yMaterial]
        let yNode = SCNNode(geometry: y)
        yNode.name = "y"
        yNode.position = SCNVector3(0, length / 2, 0)

        let z = SCNBox(width: thickness, height: thickness, length: length, chamferRadius: 0)
        z.materials = [zMaterial]
        let zNode = SCNNode(geometry: z)
        zNode.name = "z"
        zNode.position = SCNVector3(0, 0, length / 2)

        root.addChildNode(xNode)
        root.addChildNode(yNode)
        root.addChildNode(zNode)
        return root
    }
}

