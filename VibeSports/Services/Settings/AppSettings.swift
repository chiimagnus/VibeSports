import Foundation
import SwiftData

@Model
final class AppSettings {
    var showPoseOverlay: Bool
    var mirrorPoseOverlay: Bool
    var poseStabilizationEnabled: Bool

    init(
        showPoseOverlay: Bool = false,
        mirrorPoseOverlay: Bool = false,
        poseStabilizationEnabled: Bool = true
    ) {
        self.showPoseOverlay = showPoseOverlay
        self.mirrorPoseOverlay = mirrorPoseOverlay
        self.poseStabilizationEnabled = poseStabilizationEnabled
    }
}
