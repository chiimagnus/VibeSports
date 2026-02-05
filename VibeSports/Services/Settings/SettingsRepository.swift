import Foundation

struct SettingsSnapshot: Sendable, Equatable {
    var showPoseOverlay: Bool
    var mirrorPoseOverlay: Bool
    var poseStabilizationEnabled: Bool
}

@MainActor
protocol SettingsRepository: AnyObject {
    func load() throws -> SettingsSnapshot
    func updateShowPoseOverlay(_ isEnabled: Bool) throws
    func updateMirrorPoseOverlay(_ isEnabled: Bool) throws
    func updatePoseStabilizationEnabled(_ isEnabled: Bool) throws
}
