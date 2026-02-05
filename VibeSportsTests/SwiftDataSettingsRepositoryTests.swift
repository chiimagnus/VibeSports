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
    }

    func test_updatesPersist() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AppSettings.self, configurations: configuration)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let repository = SwiftDataSettingsRepository(modelContext: container.mainContext, userDefaults: defaults)

        try repository.updateShowPoseOverlay(true)
        try repository.updateMirrorPoseOverlay(true)

        let settings = try repository.load()
        XCTAssertTrue(settings.showPoseOverlay)
        XCTAssertTrue(settings.mirrorPoseOverlay)
    }

    func test_seedsFromLegacyUserDefaultsKeys() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AppSettings.self, configurations: configuration)

        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "runner.debug.showPoseOverlay")
        defaults.set(true, forKey: "runner.debug.mirrorPoseOverlay")

        let repository = SwiftDataSettingsRepository(modelContext: container.mainContext, userDefaults: defaults)

        let settings = try repository.load()
        XCTAssertTrue(settings.showPoseOverlay)
        XCTAssertTrue(settings.mirrorPoseOverlay)
    }
}
