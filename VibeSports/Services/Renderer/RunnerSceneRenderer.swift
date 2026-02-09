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
        }

        struct Cadence: Sendable, Equatable {
            var strideLengthMetersPerStep: Double
            var stepsPerLoop: Double
        }

        var runner: Runner
        var cadence: Cadence
        var blender: RunnerAnimationBlender.Configuration
        var speedSmoothingAlpha: Double

        static let `default` = Tuning(
            runner: Runner(scale: 0.01),
            cadence: Cadence(
                strideLengthMetersPerStep: 1.0,
                stepsPerLoop: 2.0
            ),
            blender: RunnerAnimationBlender.Configuration(),
            speedSmoothingAlpha: 0.20
        )
    }

    struct Configuration: Sendable, Equatable {
        var chunkSize: Double = 12
        var activeChunkRadius: Int = 2
        var treesPerChunk: Int = 30
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

    func setShowWorldAxes(_ isShown: Bool) {
        animator.setShowWorldAxes(isShown)
    }

    func setShowRunnerAxes(_ isShown: Bool) {
        animator.setShowRunnerAxes(isShown)
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
    private var chunkCoordinator: ForestChunkCoordinator
    private let chunkFactory: ForestChunkNodeFactory

    private let logger = Logger(subsystem: "com.chiimagnus.VibeSports", category: "RunnerSceneAnimator")

    private let lock = OSAllocatedUnfairLock(initialState: MotionState())
    private let tuningLock = OSAllocatedUnfairLock(initialState: TuningState())
    private let debugAxesLock = OSAllocatedUnfairLock(initialState: DebugAxesState())

    private struct MotionState {
        var motion: RunnerMotion = .zero
    }

    private struct TuningState {
        var tuning: RunnerSceneRenderer.Tuning = .default
    }

    private struct DebugAxesState: Equatable {
        var showWorldAxes: Bool = false
        var showRunnerAxes: Bool = false
    }

    private enum Defaults {
        static let cameraFieldOfViewDegrees: Double = 70
        static let cameraHeightY: Double = 2.2
        static let cameraBackOffsetZ: Double = 5.0
        static let cameraLookAtHeightY: Double = 1.4
        static let cameraSideOffsetX: Double = 0.18

        static let cameraBobMaxAmplitude: Double = 0.10
        static let cameraBobSpeedToAmplitudeGain: Double = 0.018
        static let cameraBobFrequency: Double = 6.0

        static let cameraSwayMaxAmplitude: Double = 0.06
        static let cameraSwaySpeedToAmplitudeGain: Double = 0.012
        static let cameraSwayFrequency: Double = 3.5

        static let cadenceSmoothingAlpha: Double = 0.3
        static let keyboardDebugForwardSpeedMetersPerSecond: Double = 3.0
        static let minimumForwardSpeedMetersPerSecond: Double = 0.8
        static let maximumBackwardSpeedMetersPerSecond: Double = 2.4
        static let maxYawSpeedRadiansPerSecond: Double = .pi * 0.95
    }

    private var lastTime: TimeInterval?
    private var navigationState = RunnerNavigationState.zero
    private var navigationIntegrator = RunnerNavigationIntegrator()

    private weak var sceneRootNode: SCNNode?
    private var activeChunkNodes: [ForestChunkCoordinate: SCNNode] = [:]

    private let yawPivotNode = SCNNode()
    private let cameraBoomNode = SCNNode()
    private let cameraLookTargetNode = SCNNode()
    private let cameraNode = SCNNode()
    private let camera = SCNCamera()

    private var runnerNode: SCNNode?
    private var runnerSkinnedNode: SCNNode?
    private var runnerSkeletonNode: SCNNode?

    private var worldAxesNode: SCNNode?
    private var runnerAxesNode: SCNNode?
    private var lastAppliedDebugAxes: DebugAxesState?

    private var animationBlender = RunnerAnimationBlender()
    private var idlePlayer: SCNAnimationPlayer?
    private var slowRunPlayer: SCNAnimationPlayer?
    private var fastRunPlayer: SCNAnimationPlayer?

    private var displayedCadenceStepsPerSecond: Double = 0
    private var displayedSpeedMetersPerSecond: Double = 0
    private var lastAppliedTuning: RunnerSceneRenderer.Tuning?

    init(configuration: RunnerSceneRenderer.Configuration) {
        self.configuration = configuration
        self.chunkCoordinator = ForestChunkCoordinator(
            configuration: .init(
                chunkSize: max(1, configuration.chunkSize),
                activeRadius: max(1, configuration.activeChunkRadius)
            )
        )
        self.chunkFactory = ForestChunkNodeFactory(
            configuration: .init(
                chunkSize: max(1, configuration.chunkSize),
                treesPerChunk: max(1, configuration.treesPerChunk),
                treeInset: 0.8
            )
        )
        navigationIntegrator.configuration.maxYawSpeedRadiansPerSecond = Defaults.maxYawSpeedRadiansPerSecond
        navigationIntegrator.configuration.maxForwardSpeedMetersPerSecond = Defaults.keyboardDebugForwardSpeedMetersPerSecond
        navigationIntegrator.configuration.maxBackwardSpeedMetersPerSecond = Defaults.maximumBackwardSpeedMetersPerSecond
        super.init()
    }

    func install(into scene: SCNScene) {
        sceneRootNode = scene.rootNode
        scene.rootNode.addChildNode(makeAmbientLight())
        scene.rootNode.addChildNode(makeDirectionalLight())

        setupCameraRig(into: scene)

        let worldAxes = SceneDebugAxes.makeAxesNode(length: 1.8, thickness: 0.02)
        worldAxes.name = "debugWorldAxes"
        worldAxes.position = SCNVector3(0, 0.001, 0)
        worldAxesNode = worldAxes
        scene.rootNode.addChildNode(worldAxes)

        installRunner(into: scene)

        let tuning = tuningLock.withLock { $0.tuning }
        if let runnerNode {
            let runnerAxes = SceneDebugAxes.makeAxesNode(length: 1.2, thickness: 0.02)
            runnerAxes.name = "debugRunnerAxes"
            runnerAxesNode = runnerAxes
            runnerAxes.position = SCNVector3(0, 0, 0)
            runnerAxes.isHidden = true
            runnerNode.addChildNode(runnerAxes)
            applyRunnerAxesScale(tuning: tuning)
        }

        applyDebugAxesVisibilityIfNeeded(tuning: tuning, force: true)
        syncWorldChunks(around: navigationState)
    }

    func reset() {
        lastTime = nil
        lock.withLock { $0.motion = .zero }

        displayedCadenceStepsPerSecond = 0
        displayedSpeedMetersPerSecond = 0
        navigationState = .zero
        lastAppliedTuning = nil

        let tuning = tuningLock.withLock { $0.tuning }
        applyRunnerAxesScale(tuning: tuning)
        applyDebugAxesVisibilityIfNeeded(tuning: tuning, force: true)

        idlePlayer?.blendFactor = 1
        slowRunPlayer?.blendFactor = 0
        fastRunPlayer?.blendFactor = 0
        idlePlayer?.speed = 1
        slowRunPlayer?.speed = 1
        fastRunPlayer?.speed = 1

        applyCameraRig(from: navigationState, time: 0, speedMetersPerSecond: 0)
        syncWorldChunks(around: navigationState)
    }

    func setMotion(_ motion: RunnerMotion) {
        lock.withLock {
            $0.motion = RunnerMotion(
                speedMetersPerSecond: max(0, motion.speedMetersPerSecond),
                cadenceStepsPerSecond: max(0, motion.cadenceStepsPerSecond),
                cadenceStepsPerMinute: max(0, motion.cadenceStepsPerMinute),
                forwardInput: min(1, max(-1, motion.forwardInput)),
                turnInput: min(1, max(-1, motion.turnInput)),
                headingYaw: motion.headingYaw
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
        let speedSmoothingAlpha = min(max(tuning.speedSmoothingAlpha, 0), 1)

        displayedCadenceStepsPerSecond +=
            (motion.cadenceStepsPerSecond - displayedCadenceStepsPerSecond) * Defaults.cadenceSmoothingAlpha

        let strideLength = max(0, tuning.cadence.strideLengthMetersPerStep)
        let cadenceDerivedSpeed = displayedCadenceStepsPerSecond * strideLength
        let keyboardDerivedSpeed = abs(motion.forwardInput) * Defaults.keyboardDebugForwardSpeedMetersPerSecond
        let targetSpeedMetersPerSecond = max(cadenceDerivedSpeed, keyboardDerivedSpeed)

        displayedSpeedMetersPerSecond +=
            (targetSpeedMetersPerSecond - displayedSpeedMetersPerSecond) * speedSmoothingAlpha

        if lastAppliedTuning != tuning {
            applyTuning(tuning)
            lastAppliedTuning = tuning
        }
        applyDebugAxesVisibilityIfNeeded(tuning: tuning, force: false)

        let synthesizedCadence = strideLength > 0.0001
            ? displayedSpeedMetersPerSecond / strideLength
            : displayedCadenceStepsPerSecond
        updateRunnerAnimation(
            speedMetersPerSecond: displayedSpeedMetersPerSecond,
            cadenceStepsPerSecond: max(displayedCadenceStepsPerSecond, synthesizedCadence)
        )

        navigationIntegrator.configuration.maxYawSpeedRadiansPerSecond = Defaults.maxYawSpeedRadiansPerSecond
        navigationIntegrator.configuration.maxForwardSpeedMetersPerSecond =
            max(Defaults.minimumForwardSpeedMetersPerSecond, displayedSpeedMetersPerSecond)
        navigationIntegrator.configuration.maxBackwardSpeedMetersPerSecond =
            max(
                Defaults.minimumForwardSpeedMetersPerSecond * 0.7,
                min(displayedSpeedMetersPerSecond * 0.7, Defaults.maximumBackwardSpeedMetersPerSecond)
            )

        navigationIntegrator.step(
            state: &navigationState,
            controlInput: RunnerControlInput(
                turnInput: motion.turnInput,
                forwardInput: motion.forwardInput
            ),
            deltaTime: dt
        )

        applyCameraRig(
            from: navigationState,
            time: time,
            speedMetersPerSecond: displayedSpeedMetersPerSecond
        )
        syncWorldChunks(around: navigationState)
    }

    private func setupCameraRig(into scene: SCNScene) {
        cameraNode.camera = camera
        camera.fieldOfView = CGFloat(Defaults.cameraFieldOfViewDegrees)

        cameraLookTargetNode.position = SCNVector3(0, CGFloat(Defaults.cameraLookAtHeightY), 0)

        cameraBoomNode.addChildNode(cameraNode)
        yawPivotNode.addChildNode(cameraLookTargetNode)
        yawPivotNode.addChildNode(cameraBoomNode)
        scene.rootNode.addChildNode(yawPivotNode)

        let lookAt = SCNLookAtConstraint(target: cameraLookTargetNode)
        lookAt.isGimbalLockEnabled = true
        cameraNode.constraints = [lookAt]

        applyCameraRig(from: navigationState, time: 0, speedMetersPerSecond: 0)
    }

    private func applyCameraRig(
        from navigation: RunnerNavigationState,
        time: TimeInterval,
        speedMetersPerSecond: Double
    ) {
        yawPivotNode.position = SCNVector3(
            CGFloat(navigation.positionX),
            0,
            CGFloat(navigation.positionZ)
        )
        yawPivotNode.eulerAngles.y = CGFloat(navigation.headingYaw)

        let bobAmplitude = min(
            Defaults.cameraBobMaxAmplitude,
            speedMetersPerSecond * Defaults.cameraBobSpeedToAmplitudeGain
        )
        let swayAmplitude = min(
            Defaults.cameraSwayMaxAmplitude,
            speedMetersPerSecond * Defaults.cameraSwaySpeedToAmplitudeGain
        )
        let bob = sin(time * Defaults.cameraBobFrequency) * bobAmplitude
        let sway = cos(time * Defaults.cameraSwayFrequency) * swayAmplitude

        cameraBoomNode.position = SCNVector3(
            CGFloat(Defaults.cameraSideOffsetX + sway),
            CGFloat(Defaults.cameraHeightY + bob),
            CGFloat(-Defaults.cameraBackOffsetZ)
        )
    }

    private func syncWorldChunks(around navigation: RunnerNavigationState) {
        guard let rootNode = sceneRootNode else { return }
        let active = chunkCoordinator.activeChunks(
            aroundX: navigation.positionX,
            z: navigation.positionZ
        )
        let activeSet = Set(active)

        for (coordinate, node) in activeChunkNodes where !activeSet.contains(coordinate) {
            node.removeFromParentNode()
            activeChunkNodes.removeValue(forKey: coordinate)
        }

        for coordinate in active where activeChunkNodes[coordinate] == nil {
            let center = chunkCoordinator.center(of: coordinate)
            let chunkNode = chunkFactory.makeChunkNode(
                coordinate: coordinate,
                centerX: center.x,
                centerZ: center.z
            )
            activeChunkNodes[coordinate] = chunkNode
            rootNode.addChildNode(chunkNode)
        }
    }

    private func makeAmbientLight() -> SCNNode {
        let light = SCNLight()
        light.type = .ambient
        light.intensity = 600
        light.color = NSColor(white: 0.82, alpha: 1)
        let node = SCNNode()
        node.light = light
        return node
    }

    private func makeDirectionalLight() -> SCNNode {
        let light = SCNLight()
        light.type = .directional
        light.intensity = 1050
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
        clonedRoot.eulerAngles.y = 0

        runnerSkinnedNode = Self.findFirstSkinnedNode(in: clonedRoot)
        runnerSkeletonNode = clonedRoot.childNode(withName: "Skeleton", recursively: true)

        if runnerSkinnedNode == nil {
            logger.error("Runner.usdz loaded, but no skinned node found (skinner == nil everywhere).")
        }
        if runnerSkeletonNode == nil {
            logger.error("Runner.usdz loaded, but no node named \"Skeleton\" found.")
        }

        clonedRoot.position = SCNVector3(0, 0, 0)

        if let runnerSkinnedNode {
            let minY = Double(runnerSkinnedNode.boundingBox.min.y)
            let groundOffset = (-minY * scale)
            clonedRoot.position.y = CGFloat(groundOffset)
        }

        yawPivotNode.addChildNode(clonedRoot)
        runnerNode = clonedRoot
        installRunnerAnimationPlayers()
    }

    private func installRunnerAnimationPlayers() {
        guard let runnerSkeletonNode else { return }

        func key(containing token: String) -> String? {
            runnerSkeletonNode.animationKeys.first { key in
                key.localizedCaseInsensitiveContains(token)
            }
        }

        guard
            let idleKey = key(containing: "Idle"),
            let slowKey = key(containing: "SlowRun"),
            let fastKey = key(containing: "FastRun")
        else {
            logger.error(
                "Runner Skeleton animationKeys are missing expected clips (Idle/SlowRun/FastRun). Keys: \(runnerSkeletonNode.animationKeys, privacy: .public)"
            )
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

    var tuning: RunnerSceneRenderer.Tuning {
        tuningLock.withLock { $0.tuning }
    }

    func setTuning(_ tuning: RunnerSceneRenderer.Tuning) {
        tuningLock.withLock { $0.tuning = tuning }
    }

    func setShowWorldAxes(_ isShown: Bool) {
        debugAxesLock.withLock { $0.showWorldAxes = isShown }
    }

    func setShowRunnerAxes(_ isShown: Bool) {
        debugAxesLock.withLock { $0.showRunnerAxes = isShown }
    }

    private func applyTuning(_ tuning: RunnerSceneRenderer.Tuning) {
        guard let runnerNode else { return }

        runnerNode.scale = SCNVector3(
            CGFloat(tuning.runner.scale),
            CGFloat(tuning.runner.scale),
            CGFloat(tuning.runner.scale)
        )
        runnerNode.eulerAngles.y = 0

        if let runnerSkinnedNode {
            let minY = Double(runnerSkinnedNode.boundingBox.min.y)
            let groundOffset = (-minY * tuning.runner.scale)
            runnerNode.position.y = CGFloat(groundOffset)
        }

        applyRunnerAxesScale(tuning: tuning)
    }

    private func applyRunnerAxesScale(tuning: RunnerSceneRenderer.Tuning) {
        guard let runnerAxesNode else { return }
        let scale = max(0.0001, tuning.runner.scale)
        let inv = 1.0 / scale
        runnerAxesNode.scale = SCNVector3(CGFloat(inv), CGFloat(inv), CGFloat(inv))
    }

    private func applyDebugAxesVisibilityIfNeeded(
        tuning: RunnerSceneRenderer.Tuning,
        force: Bool
    ) {
        let state = debugAxesLock.withLock { $0 }
        guard force || state != lastAppliedDebugAxes else { return }

        worldAxesNode?.isHidden = !state.showWorldAxes
        runnerAxesNode?.isHidden = !state.showRunnerAxes

        if state.showRunnerAxes {
            applyRunnerAxesScale(tuning: tuning)
        }

        lastAppliedDebugAxes = state
    }

    private static func findFirstSkinnedNode(in node: SCNNode) -> SCNNode? {
        if node.skinner != nil { return node }
        for child in node.childNodes {
            if let found = findFirstSkinnedNode(in: child) {
                return found
            }
        }
        return nil
    }
}
