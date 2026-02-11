import AppKit
import Combine
import SceneKit
import SwiftUI

@MainActor
final class RunnerAnimationDebugViewModel: ObservableObject {
    struct ClipState: Identifiable, Equatable {
        let id: String
        var isPlaying: Bool
        var blendFactor: CGFloat
        var playbackRate: CGFloat
    }

    @Published private(set) var scene: SCNScene?
    @Published private(set) var statusMessage: String = "Loading…"
    @Published var clips: [ClipState] = []

    @Published var selectedClipID: String?

    private var skeletonNode: SCNNode?
    private var startedClipIDs: Set<String> = []

    func reloadFromBundle() {
        statusMessage = "Loading…"
        clips = []
        selectedClipID = nil
        skeletonNode = nil
        startedClipIDs = []

        guard let url = Bundle.main.url(forResource: "Runner", withExtension: "usdz") else {
            scene = nil
            statusMessage = "Missing Runner.usdz in app bundle. Add it to Copy Bundle Resources."
            return
        }

        do {
            let loadedScene = try SCNScene(url: url, options: nil)
            scene = loadedScene

            let skeleton = loadedScene.rootNode.childNode(withName: "Skeleton", recursively: true)
            skeletonNode = skeleton

            guard let skeleton else {
                statusMessage = "Loaded Runner.usdz, but no node named \"Skeleton\" found."
                return
            }

            let keys = skeleton.animationKeys
            if keys.isEmpty {
                statusMessage = "Loaded Runner.usdz, but Skeleton has no animationKeys."
                return
            }

            clips = keys.map { key in
                ClipState(
                    id: key,
                    isPlaying: false,
                    blendFactor: 0,
                    playbackRate: 1
                )
            }

            if let idleKey = keys.first(where: { $0.localizedCaseInsensitiveContains("Idle") }) {
                selectedClipID = idleKey
            } else {
                selectedClipID = keys.first
            }

            for index in clips.indices {
                clips[index].blendFactor = (clips[index].id == selectedClipID) ? 1 : 0
            }

            applyClipStates()
            statusMessage = "Loaded \(keys.count) clips on Skeleton."
        } catch {
            scene = nil
            statusMessage = "Failed to load Runner.usdz: \(error.localizedDescription)"
        }
    }

    func togglePlay(clipID: String) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return }
        clips[index].isPlaying.toggle()
        applyClipStates()
    }

    func stopAll() {
        for index in clips.indices {
            clips[index].isPlaying = false
        }
        applyClipStates()
    }

    func playAll() {
        for index in clips.indices {
            clips[index].isPlaying = true
        }
        applyClipStates()
    }

    func solo(clipID: String) {
        selectedClipID = clipID
        for index in clips.indices {
            clips[index].blendFactor = (clips[index].id == clipID) ? 1 : 0
        }
        applyClipStates()
    }

    func updateBlend(clipID: String, blendFactor: CGFloat) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return }
        clips[index].blendFactor = blendFactor
        applyClipStates()
    }

    func updatePlaybackRate(clipID: String, playbackRate: CGFloat) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return }
        clips[index].playbackRate = playbackRate
        applyClipStates()
    }

    private func applyClipStates() {
        guard let skeletonNode else { return }

        for clip in clips {
            guard let player = skeletonNode.animationPlayer(forKey: clip.id) else { continue }
            player.blendFactor = clip.blendFactor
            player.speed = clip.playbackRate

            if clip.isPlaying {
                if player.animation.repeatCount != .greatestFiniteMagnitude {
                    player.animation.repeatCount = .greatestFiniteMagnitude
                }
                if !startedClipIDs.contains(clip.id) {
                    player.play()
                    startedClipIDs.insert(clip.id)
                } else {
                    player.paused = false
                }
            } else {
                player.paused = true
            }
        }
    }
}

struct RunnerAnimationDebugView: View {
    @StateObject private var viewModel = RunnerAnimationDebugViewModel()

    var body: some View {
        HStack(spacing: 0) {
            RunnerUSDZPreviewSceneView(scene: viewModel.scene)
                .frame(minWidth: 520, idealWidth: 720, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            inspector
                .frame(width: 420)
        }
        .navigationTitle("Runner Animations")
        .onAppear {
            viewModel.reloadFromBundle()
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Reload") { viewModel.reloadFromBundle() }
                Spacer()
                Button("Play All") { viewModel.playAll() }
                Button("Stop All") { viewModel.stopAll() }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.clips) { clip in
                        ClipRow(
                            clip: clip,
                            isSelected: clip.id == viewModel.selectedClipID,
                            onSelect: { viewModel.selectedClipID = clip.id },
                            onSolo: { viewModel.solo(clipID: clip.id) },
                            onTogglePlay: { viewModel.togglePlay(clipID: clip.id) },
                            onBlendChange: { viewModel.updateBlend(clipID: clip.id, blendFactor: $0) },
                            onPlaybackRateChange: { viewModel.updatePlaybackRate(clipID: clip.id, playbackRate: $0) }
                        )
                        Divider()
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
    }
}

private struct ClipRow: View {
    let clip: RunnerAnimationDebugViewModel.ClipState
    let isSelected: Bool
    let onSelect: () -> Void
    let onSolo: () -> Void
    let onTogglePlay: () -> Void
    let onBlendChange: (CGFloat) -> Void
    let onPlaybackRateChange: (CGFloat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    onSelect()
                } label: {
                    Text(clipLabel)
                        .font(.headline)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(clip.isPlaying ? "Pause" : "Play") {
                    onTogglePlay()
                }

                Button("Solo") {
                    onSolo()
                }
            }

            HStack {
                Text("Blend")
                    .frame(width: 60, alignment: .leading)
                Slider(value: Binding(get: {
                    Double(clip.blendFactor)
                }, set: { newValue in
                    onBlendChange(CGFloat(newValue))
                }), in: 0...1)
                Text(String(format: "%.2f", Double(clip.blendFactor)))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }

            HStack {
                Text("Rate")
                    .frame(width: 60, alignment: .leading)
                Slider(value: Binding(get: {
                    Double(clip.playbackRate)
                }, set: { newValue in
                    onPlaybackRateChange(CGFloat(newValue))
                }), in: 0.1...3.0)
                Text(String(format: "%.2f", Double(clip.playbackRate)))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }

            Text(clip.id)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private var clipLabel: String {
        if clip.id.localizedCaseInsensitiveContains("Idle") { return "Idle" }
        if clip.id.localizedCaseInsensitiveContains("Slow") { return "SlowRun" }
        if clip.id.localizedCaseInsensitiveContains("Fast") { return "FastRun" }
        return clip.id
    }
}

private struct RunnerUSDZPreviewSceneView: NSViewRepresentable {
    let scene: SCNScene?

    final class Coordinator {
        var lastSceneID: ObjectIdentifier?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = NSColor(white: 0.06, alpha: 1)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.rendersContinuously = true
        view.defaultCameraController.inertiaEnabled = false
        view.scene = scene
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        let sceneChanged: Bool
        if let scene {
            let sceneID = ObjectIdentifier(scene)
            sceneChanged = context.coordinator.lastSceneID != sceneID
            context.coordinator.lastSceneID = sceneID
        } else {
            sceneChanged = context.coordinator.lastSceneID != nil
            context.coordinator.lastSceneID = nil
        }

        if nsView.scene !== scene {
            nsView.scene = scene
        }
        ensureCamera(in: nsView, shouldRefit: sceneChanged)
    }

    private func ensureCamera(in view: SCNView, shouldRefit: Bool) {
        guard let scene = view.scene else { return }

        let cameraNode = ensurePreviewCamera(in: scene)
        if shouldRefit || view.pointOfView !== cameraNode {
            fit(cameraNode: cameraNode, to: scene)
        }
        view.pointOfView = cameraNode
    }

    private func ensurePreviewCamera(in scene: SCNScene) -> SCNNode {
        let cameraName = "__runnerPreviewCamera"
        if let existing = scene.rootNode.childNode(withName: cameraName, recursively: false) {
            return existing
        }

        let camera = SCNCamera()
        camera.fieldOfView = 50
        camera.zNear = 0.01
        camera.zFar = 250

        let cameraNode = SCNNode()
        cameraNode.name = cameraName
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        return cameraNode
    }

    private func fit(cameraNode: SCNNode, to scene: SCNScene) {
        guard let bounds = contentBounds(in: scene) else {
            cameraNode.position = SCNVector3(0, 1.5, 3.2)
            cameraNode.look(at: SCNVector3(0, 1.2, 0))
            return
        }

        let center = SCNVector3(
            (bounds.min.x + bounds.max.x) * 0.5,
            (bounds.min.y + bounds.max.y) * 0.5,
            (bounds.min.z + bounds.max.z) * 0.5
        )
        let size = SCNVector3(
            bounds.max.x - bounds.min.x,
            bounds.max.y - bounds.min.y,
            bounds.max.z - bounds.min.z
        )

        let radius = max(
            0.3,
            sqrt(Double(size.x * size.x + size.y * size.y + size.z * size.z)) * 0.5
        )
        let fovDegrees = max(20.0, min(80.0, Double(cameraNode.camera?.fieldOfView ?? 50)))
        let fovRadians = fovDegrees * .pi / 180
        let distance = max(radius * 1.25, radius / tan(fovRadians * 0.5) * 1.35)
        let lookAt = SCNVector3(center.x, center.y + size.y * 0.08, center.z)

        cameraNode.position = SCNVector3(lookAt.x, lookAt.y, lookAt.z + CGFloat(distance))
        cameraNode.look(at: lookAt)

        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.camera?.zNear = max(0.01, distance - radius * 2.8)
        cameraNode.camera?.zFar = max(120, distance + radius * 8)
    }

    private func contentBounds(in scene: SCNScene) -> (min: SCNVector3, max: SCNVector3)? {
        var hasBounds = false
        var minBounds = SCNVector3Zero
        var maxBounds = SCNVector3Zero

        scene.rootNode.enumerateChildNodes { node, _ in
            guard node.camera == nil, node.light == nil else { return }
            guard node.geometry != nil || node.skinner != nil else { return }

            let (localMin, localMax) = node.boundingBox
            guard localMin.x <= localMax.x else { return }

            for corner in corners(min: localMin, max: localMax) {
                let worldCorner = node.convertPosition(corner, to: scene.rootNode)

                if !hasBounds {
                    minBounds = worldCorner
                    maxBounds = worldCorner
                    hasBounds = true
                    continue
                }

                minBounds.x = min(minBounds.x, worldCorner.x)
                minBounds.y = min(minBounds.y, worldCorner.y)
                minBounds.z = min(minBounds.z, worldCorner.z)

                maxBounds.x = max(maxBounds.x, worldCorner.x)
                maxBounds.y = max(maxBounds.y, worldCorner.y)
                maxBounds.z = max(maxBounds.z, worldCorner.z)
            }
        }

        return hasBounds ? (minBounds, maxBounds) : nil
    }

    private func corners(min: SCNVector3, max: SCNVector3) -> [SCNVector3] {
        [
            SCNVector3(min.x, min.y, min.z),
            SCNVector3(min.x, min.y, max.z),
            SCNVector3(min.x, max.y, min.z),
            SCNVector3(min.x, max.y, max.z),
            SCNVector3(max.x, min.y, min.z),
            SCNVector3(max.x, min.y, max.z),
            SCNVector3(max.x, max.y, min.z),
            SCNVector3(max.x, max.y, max.z),
        ]
    }
}

#Preview {
    RunnerAnimationDebugView()
        .frame(width: 1100, height: 720)
}
