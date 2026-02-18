import Foundation
import SwiftData

@Model
final class AppSettings {
    var showPoseOverlay: Bool
    var mirrorPoseOverlay: Bool
    var poseStabilizationEnabled: Bool
    var showPoseArmDebugOverlay: Bool

    init(
        showPoseOverlay: Bool = false,
        mirrorPoseOverlay: Bool = false,
        poseStabilizationEnabled: Bool = true,
        showPoseArmDebugOverlay: Bool = false
    ) {
        self.showPoseOverlay = showPoseOverlay
        self.mirrorPoseOverlay = mirrorPoseOverlay
        self.poseStabilizationEnabled = poseStabilizationEnabled
        self.showPoseArmDebugOverlay = showPoseArmDebugOverlay
    }
}
