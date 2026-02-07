import Combine
import os
import SceneKit

@MainActor
protocol RunnerSceneRendering: AnyObject {
    func attach(to view: SCNView)
    func setMotion(_ motion: RunnerMotion)
    func reset()
}

@MainActor
final class RunnerSceneRenderer: ObservableObject {
    struct Tuning: Sendable, Equatable {
        struct Runner: Sendable, Equatable {
            var scale: Double
            var yawRadians: Double
            var aheadOffsetZ: Double
            var additionalGroundOffsetY: Double
            var x: Double
        }

        struct Camera: Sendable, Equatable {
            var fieldOfViewDegrees: Double
            var heightY: Double
            var backOffsetZ: Double
            var lookAtHeightY: Double

            var bobMaxAmplitude: Double
            var bobSpeedToAmplitudeGain: Double
            var bobFrequency: Double

            var swayMaxAmplitude: Double
            var swaySpeedToAmplitudeGain: Double
            var swayFrequency: Double
            var baseX: Double
        }

        struct Cadence: Sendable, Equatable {
            var strideLengthMetersPerStep: Double
            var stepsPerLoop: Double
            var smoothingAlpha: Double
        }

        var runner: Runner
        var camera: Camera
        var cadence: Cadence
        var blender: RunnerAnimationBlender.Configuration
        var speedSmoothingAlpha: Double

        static let `default` = Tuning(
            runner: Runner(
                scale: 0.01,
                yawRadians: 0,
                aheadOffsetZ: 6.0,
                additionalGroundOffsetY: 0,
                x: 0
            ),
            camera: Camera(
                fieldOfViewDegrees: 70,
                heightY: 2.2,
                backOffsetZ: 5.0,
                lookAtHeightY: 1.4,
                bobMaxAmplitude: 0.12,
                bobSpeedToAmplitudeGain: 0.02,
                bobFrequency: 6.0,
                swayMaxAmplitude: 0.08,
                swaySpeedToAmplitudeGain: 0.015,
                swayFrequency: 3.5,
                baseX: 0
            ),
            cadence: Cadence(
                strideLengthMetersPerStep: 1.0,
                stepsPerLoop: 2.0,
                smoothingAlpha: 0.3
            ),
            blender: RunnerAnimationBlender.Configuration(),
            speedSmoothingAlpha: 0.20
        )
    }

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

    var tuning: Tuning {
        get { animator.tuning }
        set { animator.setTuning(newValue) }
    }

    func attach(to view: SCNView) {
        view.scene = scene
        view.delegate = animator
        view.isPlaying = true
    }

    func setMotion(_ motion: RunnerMotion) {
        animator.setMotion(motion)
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

    private let lock = OSAllocatedUnfairLock(initialState: MotionState())
    private let tuningLock = OSAllocatedUnfairLock(initialState: TuningState())

    private struct MotionState {
        var motion: RunnerMotion = .zero
    }

    private struct TuningState {
        var tuning: RunnerSceneRenderer.Tuning = .default
    }

    private var lastTime: TimeInterval?

    private let cameraNode = SCNNode()
    private let camera = SCNCamera()
    private var segmentNodes: [SCNNode] = []
    private let decorationAssets = DecorationAssets()

    private var runnerNode: SCNNode?
    private var runnerSkinnedNode: SCNNode?
    private var runnerSkeletonNode: SCNNode?

    private var animationBlender = RunnerAnimationBlender()
    private var idlePlayer: SCNAnimationPlayer?
    private var slowRunPlayer: SCNAnimationPlayer?
    private var fastRunPlayer: SCNAnimationPlayer?

    private var displayedCadenceStepsPerSecond: Double = 0
    private var displayedSpeedMetersPerSecond: Double = 0
    private var travelZ: Double = 0
    private var lastAppliedTuning: RunnerSceneRenderer.Tuning?

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

        let tuning = tuningLock.withLock { $0.tuning }

        cameraNode.camera = camera
        camera.fieldOfView = CGFloat(tuning.camera.fieldOfViewDegrees)
        travelZ = 0
        cameraNode.position = SCNVector3(
            0,
            CGFloat(tuning.camera.heightY),
            CGFloat(initialCameraZ(tuning: tuning))
        )
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
        lock.withLock { $0.motion = .zero }
        displayedCadenceStepsPerSecond = 0
        displayedSpeedMetersPerSecond = 0
        travelZ = 0
        lastAppliedTuning = nil

        pool = TerrainSegmentPool(activeSegments: configuration.activeSegments, segmentLength: configuration.segmentLength)

        let tuning = tuningLock.withLock { $0.tuning }
        camera.fieldOfView = CGFloat(tuning.camera.fieldOfViewDegrees)
        cameraNode.position = SCNVector3(
            0,
            CGFloat(tuning.camera.heightY),
            CGFloat(initialCameraZ(tuning: tuning))
        )

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

    func setMotion(_ motion: RunnerMotion) {
        lock.withLock {
            $0.motion = RunnerMotion(
                speedMetersPerSecond: max(0, motion.speedMetersPerSecond),
                cadenceStepsPerSecond: max(0, motion.cadenceStepsPerSecond),
                cadenceStepsPerMinute: max(0, motion.cadenceStepsPerMinute)
            )
        }
    }

    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let tuning = tuningLock.withLock { $0.tuning }

        let dt: TimeInterval
        if let lastTime {
            dt = max(0, time - lastTime)
        } else {
            dt = 1.0 / 60.0
        }
        lastTime = time

        let motion = lock.withLock { $0.motion }
        let cadenceSmoothingAlpha = min(max(tuning.cadence.smoothingAlpha, 0), 1)
        let speedSmoothingAlpha = min(max(tuning.speedSmoothingAlpha, 0), 1)
        displayedCadenceStepsPerSecond += (motion.cadenceStepsPerSecond - displayedCadenceStepsPerSecond) * cadenceSmoothingAlpha

        let targetSpeedMetersPerSecond = displayedCadenceStepsPerSecond * max(0, tuning.cadence.strideLengthMetersPerStep)
        displayedSpeedMetersPerSecond += (targetSpeedMetersPerSecond - displayedSpeedMetersPerSecond) * speedSmoothingAlpha

        if lastAppliedTuning != tuning {
            applyTuning(tuning)
            lastAppliedTuning = tuning
        }

        updateRunnerAnimation(
            speedMetersPerSecond: displayedSpeedMetersPerSecond,
            cadenceStepsPerSecond: displayedCadenceStepsPerSecond
        )

        travelZ += displayedSpeedMetersPerSecond * dt

        let baseY = tuning.camera.heightY
        let bobAmplitude = min(tuning.camera.bobMaxAmplitude, displayedSpeedMetersPerSecond * tuning.camera.bobSpeedToAmplitudeGain)
        let swayAmplitude = min(tuning.camera.swayMaxAmplitude, displayedSpeedMetersPerSecond * tuning.camera.swaySpeedToAmplitudeGain)
        let bob = sin(time * tuning.camera.bobFrequency) * bobAmplitude
        let sway = cos(time * tuning.camera.swayFrequency) * swayAmplitude

        if let runnerNode {
            runnerNode.position = runnerPosition(travelZ: travelZ)

            cameraNode.position.x = CGFloat(tuning.camera.baseX + sway)
            cameraNode.position.y = CGFloat(baseY + bob)
            cameraNode.position.z = runnerNode.position.z - CGFloat(tuning.camera.backOffsetZ)

            let lookAt = SCNVector3(
                runnerNode.position.x,
                CGFloat(tuning.camera.lookAtHeightY),
                runnerNode.position.z
            )
            cameraNode.look(at: lookAt)
        }

        let progressZ = travelZ + tuning.runner.aheadOffsetZ
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

        let tuning = tuningLock.withLock { $0.tuning }

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

        let scale = tuning.runner.scale
        clonedRoot.scale = SCNVector3(CGFloat(scale), CGFloat(scale), CGFloat(scale))
        clonedRoot.eulerAngles.y = CGFloat(tuning.runner.yawRadians)

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
            let groundOffset = (-minY * scale) + tuning.runner.additionalGroundOffsetY
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

    private func updateRunnerAnimation(
        speedMetersPerSecond: Double,
        cadenceStepsPerSecond: Double
    ) {
        guard let idlePlayer, let slowRunPlayer, let fastRunPlayer else { return }

        let tuning = tuningLock.withLock { $0.tuning }
        animationBlender.configuration = tuning.blender

        let blend = animationBlender.blend(speedMetersPerSecond: speedMetersPerSecond)
        idlePlayer.blendFactor = blend.idleWeight
        slowRunPlayer.blendFactor = blend.slowRunWeight
        fastRunPlayer.blendFactor = blend.fastRunWeight

        let stepsPerLoop = max(0.1, tuning.cadence.stepsPerLoop)
        let cadenceRate = cadenceStepsPerSecond / stepsPerLoop

        func rate(for player: SCNAnimationPlayer) -> Double {
            guard cadenceRate > 0 else { return 1 }
            let duration = max(0.0001, player.animation.duration)
            let raw = cadenceRate * duration
            return min(tuning.blender.maxPlaybackRate, max(tuning.blender.minPlaybackRate, raw))
        }

        slowRunPlayer.speed = rate(for: slowRunPlayer)
        fastRunPlayer.speed = rate(for: fastRunPlayer)
    }

    private func runnerPosition(travelZ: Double) -> SCNVector3 {
        let tuning = tuningLock.withLock { $0.tuning }
        return SCNVector3(
            CGFloat(tuning.runner.x),
            runnerNode?.position.y ?? 0,
            CGFloat(travelZ + tuning.runner.aheadOffsetZ)
        )
    }

    private func initialCameraZ(tuning: RunnerSceneRenderer.Tuning) -> Double {
        (travelZ + tuning.runner.aheadOffsetZ) - tuning.camera.backOffsetZ
    }

    var tuning: RunnerSceneRenderer.Tuning {
        tuningLock.withLock { $0.tuning }
    }

    func setTuning(_ tuning: RunnerSceneRenderer.Tuning) {
        tuningLock.withLock { $0.tuning = tuning }
    }

    private func applyTuning(_ tuning: RunnerSceneRenderer.Tuning) {
        guard let runnerNode else { return }

        camera.fieldOfView = CGFloat(tuning.camera.fieldOfViewDegrees)

        runnerNode.scale = SCNVector3(
            CGFloat(tuning.runner.scale),
            CGFloat(tuning.runner.scale),
            CGFloat(tuning.runner.scale)
        )
        runnerNode.eulerAngles.y = CGFloat(tuning.runner.yawRadians)

        if let runnerSkinnedNode {
            let minY = Double(runnerSkinnedNode.boundingBox.min.y)
            let groundOffset = (-minY * tuning.runner.scale) + tuning.runner.additionalGroundOffsetY
            runnerNode.position.y = CGFloat(groundOffset)
        }
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
