import Combine
import os
import SceneKit

@MainActor
protocol RunnerSceneRendering: AnyObject {
    func attach(to view: SCNView)
    func setSpeedMetersPerSecond(_ speed: Double)
    func reset()
}

@MainActor
final class RunnerSceneRenderer: ObservableObject {
    struct Configuration: Sendable, Equatable {
        var segmentLength: Double = 10
        var segmentWidth: Double = 8
        var activeSegments: Int = 12
        var decorationsPerSegment: Int = 30
    }

    let configuration: Configuration
    let scene: SCNScene

    private let animator: RunnerSceneAnimator

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
        self.scene = SCNScene()
        self.animator = RunnerSceneAnimator(configuration: configuration)

        setupScene()
    }

    func attach(to view: SCNView) {
        view.scene = scene
        view.delegate = animator
        view.isPlaying = true
    }

    func setSpeedMetersPerSecond(_ speed: Double) {
        animator.setSpeedMetersPerSecond(speed)
    }

    func reset() {
        animator.reset()
    }

    private func setupScene() {
        animator.install(into: scene)
    }
}

extension RunnerSceneRenderer: RunnerSceneRendering {}

private final class RunnerSceneAnimator: NSObject, SCNSceneRendererDelegate {
    private let configuration: RunnerSceneRenderer.Configuration
    private var pool: TerrainSegmentPool

    private let logger = Logger(subsystem: "com.chiimagnus.VibeSports", category: "RunnerSceneAnimator")

    private let lock = OSAllocatedUnfairLock(initialState: SpeedState())

    private struct SpeedState {
        var speedMetersPerSecond: Double = 0
    }

    private var lastTime: TimeInterval?

    private let cameraNode = SCNNode()
    private let camera = SCNCamera()
    private var segmentNodes: [SCNNode] = []
    private let decorationAssets = DecorationAssets()

    private var runnerNode: SCNNode?
    private var runnerSkinnedNode: SCNNode?
    private var runnerSkeletonNode: SCNNode?

    private let animationBlender = RunnerAnimationBlender()
    private var idlePlayer: SCNAnimationPlayer?
    private var slowRunPlayer: SCNAnimationPlayer?
    private var fastRunPlayer: SCNAnimationPlayer?

    private var displayedSpeedMetersPerSecond: Double = 0
    private var travelZ: Double = 0

    private struct RunnerConfiguration: Sendable, Equatable {
        var scale: Double = 0.01
        var yawRadians: Double = 0
        var aheadOffsetZ: Double = 6.0
        var additionalGroundOffsetY: Double = 0.0
        var x: Double = 0.0

        var cameraHeightY: Double = 2.2
        var cameraBackOffsetZ: Double = 5.0
        var cameraLookAtHeightY: Double = 1.4
        var cameraBobFrequency: Double = 6.0
        var cameraSwayFrequency: Double = 3.5
    }

    private var runnerConfiguration = RunnerConfiguration()

    init(configuration: RunnerSceneRenderer.Configuration) {
        self.configuration = configuration
        self.pool = TerrainSegmentPool(
            activeSegments: configuration.activeSegments,
            segmentLength: configuration.segmentLength
        )
        super.init()
    }

    func install(into scene: SCNScene) {
        scene.rootNode.addChildNode(makeAmbientLight())
        scene.rootNode.addChildNode(makeDirectionalLight())

        cameraNode.camera = camera
        camera.fieldOfView = 70
        travelZ = 0
        cameraNode.position = SCNVector3(0, CGFloat(runnerConfiguration.cameraHeightY), CGFloat(initialCameraZ()))
        scene.rootNode.addChildNode(cameraNode)

        installRunner(into: scene)

        segmentNodes = pool.segments.map { segment in
            makeSegmentNode(startZ: segment.startZ)
        }

        for node in segmentNodes {
            scene.rootNode.addChildNode(node)
        }
    }

    func reset() {
        lastTime = nil
        lock.withLock { $0.speedMetersPerSecond = 0 }
        displayedSpeedMetersPerSecond = 0
        travelZ = 0

        pool = TerrainSegmentPool(activeSegments: configuration.activeSegments, segmentLength: configuration.segmentLength)

        cameraNode.position = SCNVector3(0, CGFloat(runnerConfiguration.cameraHeightY), CGFloat(initialCameraZ()))

        if let runnerNode {
            runnerNode.position = runnerPosition(travelZ: travelZ)
        }

        idlePlayer?.blendFactor = 1
        slowRunPlayer?.blendFactor = 0
        fastRunPlayer?.blendFactor = 0
        idlePlayer?.speed = 1
        slowRunPlayer?.speed = 1
        fastRunPlayer?.speed = 1

        for (index, segment) in pool.segments.enumerated() where index < segmentNodes.count {
            updateSegmentNode(segmentNodes[index], startZ: segment.startZ)
        }
    }

    func setSpeedMetersPerSecond(_ speed: Double) {
        lock.withLock { state in
            state.speedMetersPerSecond = max(0, speed)
        }
    }

    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt: TimeInterval
        if let lastTime {
            dt = max(0, time - lastTime)
        } else {
            dt = 1.0 / 60.0
        }
        lastTime = time

        let speed = lock.withLock { $0.speedMetersPerSecond }
        displayedSpeedMetersPerSecond += (speed - displayedSpeedMetersPerSecond) * 0.20

        updateRunnerAnimation(speedMetersPerSecond: displayedSpeedMetersPerSecond)

        travelZ += speed * dt

        let baseY = runnerConfiguration.cameraHeightY
        let bob = sin(time * runnerConfiguration.cameraBobFrequency) * min(0.12, speed * 0.02)
        let sway = cos(time * runnerConfiguration.cameraSwayFrequency) * min(0.08, speed * 0.015)

        if let runnerNode {
            runnerNode.position = runnerPosition(travelZ: travelZ)

            cameraNode.position.x = CGFloat(sway)
            cameraNode.position.y = CGFloat(baseY + bob)
            cameraNode.position.z = runnerNode.position.z - CGFloat(runnerConfiguration.cameraBackOffsetZ)

            let lookAt = SCNVector3(
                runnerNode.position.x,
                CGFloat(runnerConfiguration.cameraLookAtHeightY),
                runnerNode.position.z
            )
            cameraNode.look(at: lookAt)
        }

        let progressZ = travelZ + runnerConfiguration.aheadOffsetZ
        let recycled = pool.recycleIfNeeded(cameraZ: progressZ)
        for newStartZ in recycled {
            guard let node = segmentNodes.first else { continue }
            segmentNodes.removeFirst()
            updateSegmentNode(node, startZ: newStartZ)
            segmentNodes.append(node)
        }
    }

    private func makeAmbientLight() -> SCNNode {
        let light = SCNLight()
        light.type = .ambient
        light.intensity = 600
        light.color = NSColor(white: 0.8, alpha: 1)
        let node = SCNNode()
        node.light = light
        return node
    }

    private func makeDirectionalLight() -> SCNNode {
        let light = SCNLight()
        light.type = .directional
        light.intensity = 1100
        light.castsShadow = true
        light.shadowMode = .deferred
        light.shadowRadius = 10
        light.shadowColor = NSColor(white: 0, alpha: 0.35)

        let node = SCNNode()
        node.light = light
        node.eulerAngles = SCNVector3(-.pi / 3.5, .pi / 4, 0)
        node.position = SCNVector3(0, 10, 0)
        return node
    }

    private func makeSegmentNode(startZ: Double) -> SCNNode {
        let node = SCNNode()
        node.name = "segment"

        let ground = SCNBox(
            width: configuration.segmentWidth,
            height: 0.12,
            length: configuration.segmentLength,
            chamferRadius: 0
        )

        let material = SCNMaterial()
        material.diffuse.contents = NSColor(white: 0.12, alpha: 1)
        material.roughness.contents = 0.9
        material.metalness.contents = 0.0
        ground.materials = [material]

        let groundNode = SCNNode(geometry: ground)
        groundNode.name = "ground"
        groundNode.position = SCNVector3(0, -0.06, 0)
        groundNode.physicsBody = .static()
        node.addChildNode(groundNode)

        let decorationsNode = SCNNode()
        decorationsNode.name = "decorations"
        node.addChildNode(decorationsNode)

        for _ in 0..<configuration.decorationsPerSegment {
            decorationsNode.addChildNode(makeDecorationNode())
        }

        updateSegmentNode(node, startZ: startZ)
        return node
    }

    private func updateSegmentNode(_ node: SCNNode, startZ: Double) {
        node.position = SCNVector3(0, 0, CGFloat(startZ + configuration.segmentLength / 2))

        guard let decorations = node.childNode(withName: "decorations", recursively: false) else { return }
        for child in decorations.childNodes {
            let side: Double = Bool.random() ? 1 : -1
            let edgeInset = 0.6
            let x = side * Double.random(in: (configuration.segmentWidth / 2 - edgeInset)...(configuration.segmentWidth / 2 + 2.2))
            let z = Double.random(in: -(configuration.segmentLength / 2)...(configuration.segmentLength / 2))
            child.position = SCNVector3(CGFloat(x), 0, CGFloat(z))
            child.eulerAngles.y = CGFloat(Double.random(in: 0...(2 * .pi)))
        }
    }

    private func makeDecorationNode() -> SCNNode {
        if Int.random(in: 0...9) == 0 {
            return decorationAssets.makeMarkerNode()
        } else {
            return decorationAssets.makeTreeNode()
        }
    }

    private func installRunner(into scene: SCNScene) {
        guard runnerNode == nil else { return }

        let runnerScene: SCNScene?
        if let loaded = SCNScene(named: "Runner.usdz") {
            runnerScene = loaded
        } else if let url = Bundle.main.url(forResource: "Runner", withExtension: "usdz") {
            runnerScene = try? SCNScene(url: url, options: nil)
        } else {
            runnerScene = nil
        }

        guard let runnerScene else {
            logger.error("Runner.usdz not found in bundle. Add it to Copy Bundle Resources.")
            return
        }

        let clonedRoot = runnerScene.rootNode.clone()
        clonedRoot.name = "runner"

        let scale = runnerConfiguration.scale
        clonedRoot.scale = SCNVector3(CGFloat(scale), CGFloat(scale), CGFloat(scale))
        clonedRoot.eulerAngles.y = CGFloat(runnerConfiguration.yawRadians)

        runnerSkinnedNode = Self.findFirstSkinnedNode(in: clonedRoot)
        runnerSkeletonNode = clonedRoot.childNode(withName: "Skeleton", recursively: true)

        if runnerSkinnedNode == nil {
            logger.error("Runner.usdz loaded, but no skinned node found (skinner == nil everywhere).")
        }
        if runnerSkeletonNode == nil {
            logger.error("Runner.usdz loaded, but no node named \"Skeleton\" found.")
        }

        clonedRoot.position = runnerPosition(travelZ: travelZ)

        if let runnerSkinnedNode {
            let minY = Double(runnerSkinnedNode.boundingBox.min.y)
            let groundOffset = (-minY * scale) + runnerConfiguration.additionalGroundOffsetY
            clonedRoot.position.y = CGFloat(groundOffset)
        }

        scene.rootNode.addChildNode(clonedRoot)
        runnerNode = clonedRoot

        installRunnerAnimationPlayers()
    }

    private func installRunnerAnimationPlayers() {
        guard let runnerSkeletonNode else { return }

        func key(containing token: String) -> String? {
            runnerSkeletonNode.animationKeys.first(where: { $0.localizedCaseInsensitiveContains(token) })
        }

        guard
            let idleKey = key(containing: "Idle"),
            let slowKey = key(containing: "SlowRun"),
            let fastKey = key(containing: "FastRun")
        else {
            logger.error("Runner Skeleton animationKeys are missing expected clips (Idle/SlowRun/FastRun). Keys: \(runnerSkeletonNode.animationKeys, privacy: .public)")
            return
        }

        idlePlayer = runnerSkeletonNode.animationPlayer(forKey: idleKey)
        slowRunPlayer = runnerSkeletonNode.animationPlayer(forKey: slowKey)
        fastRunPlayer = runnerSkeletonNode.animationPlayer(forKey: fastKey)

        guard let idlePlayer, let slowRunPlayer, let fastRunPlayer else {
            logger.error("Failed to create SCNAnimationPlayer(s) for Runner clips.")
            return
        }

        for player in [idlePlayer, slowRunPlayer, fastRunPlayer] {
            player.animation.repeatCount = .greatestFiniteMagnitude
            player.play()
        }

        idlePlayer.blendFactor = 1
        slowRunPlayer.blendFactor = 0
        fastRunPlayer.blendFactor = 0
    }

    private func updateRunnerAnimation(speedMetersPerSecond: Double) {
        guard let idlePlayer, let slowRunPlayer, let fastRunPlayer else { return }

        let blend = animationBlender.blend(speedMetersPerSecond: speedMetersPerSecond)
        idlePlayer.blendFactor = blend.idleWeight
        slowRunPlayer.blendFactor = blend.slowRunWeight
        fastRunPlayer.blendFactor = blend.fastRunWeight

        slowRunPlayer.speed = blend.playbackRate
        fastRunPlayer.speed = blend.playbackRate
    }

    private func runnerPosition(travelZ: Double) -> SCNVector3 {
        SCNVector3(
            CGFloat(runnerConfiguration.x),
            runnerNode?.position.y ?? 0,
            CGFloat(travelZ + runnerConfiguration.aheadOffsetZ)
        )
    }

    private func initialCameraZ() -> Double {
        (travelZ + runnerConfiguration.aheadOffsetZ) - runnerConfiguration.cameraBackOffsetZ
    }

    private static func findFirstSkinnedNode(in node: SCNNode) -> SCNNode? {
        if node.skinner != nil { return node }
        for child in node.childNodes {
            if let found = findFirstSkinnedNode(in: child) { return found }
        }
        return nil
    }
}

private final class DecorationAssets {
    private let trunkGeometry: SCNCylinder
    private let crownGeometry: SCNCone
    private let markerGeometry: SCNBox

    private let trunkMaterial: SCNMaterial
    private let crownMaterial: SCNMaterial
    private let markerMaterial: SCNMaterial

    init() {
        trunkGeometry = SCNCylinder(radius: 0.06, height: 0.5)
        crownGeometry = SCNCone(topRadius: 0, bottomRadius: 0.22, height: 0.55)
        markerGeometry = SCNBox(width: 0.18, height: 0.8, length: 0.04, chamferRadius: 0.02)

        trunkMaterial = SCNMaterial()
        trunkMaterial.diffuse.contents = NSColor(white: 0.3, alpha: 1)
        trunkMaterial.roughness.contents = 1.0
        trunkMaterial.metalness.contents = 0.0

        crownMaterial = SCNMaterial()
        crownMaterial.diffuse.contents = NSColor(calibratedRed: 0.15, green: 0.55, blue: 0.22, alpha: 1)
        crownMaterial.roughness.contents = 0.95
        crownMaterial.metalness.contents = 0.0

        markerMaterial = SCNMaterial()
        markerMaterial.diffuse.contents = NSColor(calibratedRed: 0.95, green: 0.25, blue: 0.2, alpha: 1)
        markerMaterial.roughness.contents = 0.85
        markerMaterial.metalness.contents = 0.0

        trunkGeometry.materials = [trunkMaterial]
        crownGeometry.materials = [crownMaterial]
        markerGeometry.materials = [markerMaterial]
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

    func makeMarkerNode() -> SCNNode {
        let markerNode = SCNNode(geometry: markerGeometry)
        markerNode.position = SCNVector3(0, 0.4, 0)

        let node = SCNNode()
        node.addChildNode(markerNode)
        return node
    }
}
