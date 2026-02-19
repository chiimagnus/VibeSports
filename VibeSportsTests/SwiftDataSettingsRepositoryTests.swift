import SwiftData
import XCTest
@testable import VibeSports

@MainActor
final class SwiftDataSettingsRepositoryTests: XCTestCase {
    func test_loadCreatesDefaultsWhenEmpty() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AppSettings.self, configurations: configuration)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let repository = SwiftDataSettingsRepository(modelContext: container.mainContext, userDefaults: defaults)

        let settings = try repository.load()

        XCTAssertFalse(settings.showPoseOverlay)
        XCTAssertFalse(settings.mirrorPoseOverlay)
        XCTAssertTrue(settings.poseStabilizationEnabled)
        XCTAssertFalse(settings.showPoseArmDebugOverlay)
    }

    func test_updatesPersist() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AppSettings.self, configurations: configuration)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let repository = SwiftDataSettingsRepository(modelContext: container.mainContext, userDefaults: defaults)

        try repository.updateShowPoseOverlay(true)
        try repository.updateMirrorPoseOverlay(true)
        try repository.updatePoseStabilizationEnabled(false)
        try repository.updateShowPoseArmDebugOverlay(true)

        let settings = try repository.load()
        XCTAssertTrue(settings.showPoseOverlay)
        XCTAssertTrue(settings.mirrorPoseOverlay)
        XCTAssertFalse(settings.poseStabilizationEnabled)
        XCTAssertTrue(settings.showPoseArmDebugOverlay)
    }

    func test_seedsFromLegacyUserDefaultsKeys() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AppSettings.self, configurations: configuration)

        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "runner.debug.showPoseOverlay")
        defaults.set(true, forKey: "runner.debug.mirrorPoseOverlay")
        defaults.set(false, forKey: "runner.debug.poseStabilizationEnabled")
        defaults.set(true, forKey: "runner.debug.showPoseArmDebugOverlay")

        let repository = SwiftDataSettingsRepository(modelContext: container.mainContext, userDefaults: defaults)

        let settings = try repository.load()
        XCTAssertTrue(settings.showPoseOverlay)
        XCTAssertTrue(settings.mirrorPoseOverlay)
        XCTAssertFalse(settings.poseStabilizationEnabled)
        XCTAssertTrue(settings.showPoseArmDebugOverlay)
    }
}
