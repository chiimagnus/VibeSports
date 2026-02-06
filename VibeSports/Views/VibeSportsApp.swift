import Foundation
import SwiftUI
import SwiftData

@main
@MainActor
struct VibeSportsApp: App {
    private let modelContainer: ModelContainer
    private let dependencies: AppDependencies
    @StateObject private var debugTools = DebugToolsStore()

    init() {
        do {
            let storeURL = try Self.makeSettingsStoreURL()
            let configuration = ModelConfiguration(url: storeURL)

            do {
                modelContainer = try ModelContainer(for: AppSettings.self, configurations: configuration)
            } catch {
                // Best-effort recovery for schema changes: drop the settings store and recreate.
                try? FileManager.default.removeItem(at: storeURL)
                modelContainer = try ModelContainer(for: AppSettings.self, configurations: configuration)
            }
            dependencies = AppDependencies.live(modelContext: modelContainer.mainContext)
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    private static func makeSettingsStoreURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("VibeSports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("AppSettings-v2.store")
    }

    var body: some Scene {
        WindowGroup {
            RunnerGameView(dependencies: dependencies)
                .environmentObject(debugTools)
        }
        .modelContainer(modelContainer)
        .commands {
            DebugCommands()
        }

#if DEBUG
        Window("Runner Animations", id: "runner-animations") {
            RunnerAnimationDebugView()
                .environmentObject(debugTools)
        }

        Window("Runner Tuning", id: "runner-tuning") {
            RunnerTuningDebugView()
                .environmentObject(debugTools)
        }
#endif
    }
}
