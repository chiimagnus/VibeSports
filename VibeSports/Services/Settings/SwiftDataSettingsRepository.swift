import Foundation
import SwiftData

@MainActor
final class SwiftDataSettingsRepository: SettingsRepository {
    private enum LegacyKeys {
        static let showPoseOverlay = "runner.debug.showPoseOverlay"
        static let mirrorPoseOverlay = "runner.debug.mirrorPoseOverlay"
    }

    private let modelContext: ModelContext
    private let userDefaults: UserDefaults

    init(modelContext: ModelContext, userDefaults: UserDefaults = .standard) {
        self.modelContext = modelContext
        self.userDefaults = userDefaults
        seedIfNeeded()
    }

    func load() throws -> SettingsSnapshot {
        let settings = try fetchOrCreate()
        return SettingsSnapshot(
            showPoseOverlay: settings.showPoseOverlay,
            mirrorPoseOverlay: settings.mirrorPoseOverlay
        )
    }

    func updateShowPoseOverlay(_ isEnabled: Bool) throws {
        let settings = try fetchOrCreate()
        settings.showPoseOverlay = isEnabled
        try modelContext.save()
    }

    func updateMirrorPoseOverlay(_ isEnabled: Bool) throws {
        let settings = try fetchOrCreate()
        settings.mirrorPoseOverlay = isEnabled
        try modelContext.save()
    }

    private func fetchOrCreate() throws -> AppSettings {
        let all = try modelContext.fetch(FetchDescriptor<AppSettings>())
        if let existing = all.first {
            return existing
        }

        let created = AppSettings()
        modelContext.insert(created)
        try modelContext.save()
        return created
    }

    private func seedIfNeeded() {
        do {
            let count = try modelContext.fetchCount(FetchDescriptor<AppSettings>())
            guard count == 0 else { return }

            let seeded = AppSettings(
                showPoseOverlay: legacyBool(forKey: LegacyKeys.showPoseOverlay) ?? false,
                mirrorPoseOverlay: legacyBool(forKey: LegacyKeys.mirrorPoseOverlay) ?? false
            )
            modelContext.insert(seeded)
            try modelContext.save()
        } catch {
            // Avoid crashing on best-effort migration; callers can still load() and create defaults.
        }
    }

    private func legacyBool(forKey key: String) -> Bool? {
        guard let object = userDefaults.object(forKey: key) else { return nil }
        if let number = object as? NSNumber {
            return number.boolValue
        }
        if let value = object as? Bool {
            return value
        }
        return nil
    }
}
