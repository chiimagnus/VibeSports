import Foundation
import SwiftData

@Model
final class AppSettings {
    var userWeightKg: Double
    var showPoseOverlay: Bool
    var mirrorPoseOverlay: Bool

    init(
        userWeightKg: Double = 60,
        showPoseOverlay: Bool = false,
        mirrorPoseOverlay: Bool = false
    ) {
        self.userWeightKg = userWeightKg
        self.showPoseOverlay = showPoseOverlay
        self.mirrorPoseOverlay = mirrorPoseOverlay
    }
}

