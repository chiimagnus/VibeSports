import Foundation

struct SettingsSnapshot: Sendable, Equatable {
    var userWeightKg: Double
    var showPoseOverlay: Bool
    var mirrorPoseOverlay: Bool
}

@MainActor
protocol SettingsRepository: AnyObject {
    func load() throws -> SettingsSnapshot
    func updateUserWeightKg(_ weightKg: Double) throws
    func updateShowPoseOverlay(_ isEnabled: Bool) throws
    func updateMirrorPoseOverlay(_ isEnabled: Bool) throws
}

