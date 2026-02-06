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

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = NSColor(white: 0.06, alpha: 1)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.rendersContinuously = true
        view.scene = scene
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        if nsView.scene !== scene {
            nsView.scene = scene
        }
        ensureCameraAndLights(in: nsView)
    }

    private func ensureCameraAndLights(in view: SCNView) {
        guard let scene = view.scene else { return }

        let hasCamera = scene.rootNode.childNodes.contains(where: { $0.camera != nil })
        if !hasCamera {
            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(0, 1.5, 3.2)
            cameraNode.look(at: SCNVector3(0, 1.2, 0))
            scene.rootNode.addChildNode(cameraNode)
            view.pointOfView = cameraNode
        }
    }
}

#Preview {
    RunnerAnimationDebugView()
        .frame(width: 1100, height: 720)
}
