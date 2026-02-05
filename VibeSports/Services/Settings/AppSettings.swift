import Foundation
import SwiftData

@Model
final class AppSettings {
    var showPoseOverlay: Bool
    var mirrorPoseOverlay: Bool

    init(
        showPoseOverlay: Bool = false,
        mirrorPoseOverlay: Bool = false
    ) {
        self.showPoseOverlay = showPoseOverlay
        self.mirrorPoseOverlay = mirrorPoseOverlay
    }
}
