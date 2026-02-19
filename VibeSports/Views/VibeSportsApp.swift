import Foundation
import SwiftUI
import SwiftData

@main
@MainActor
struct VibeSportsApp: App {
    private let modelContainer: ModelContainer
    private let dependencies: AppDependencies
    @StateObject private var debugTools = DebugToolsStore()
    @StateObject private var runnerCommands = RunnerCommandCenter()
    @StateObject private var navState = AppNavigationState()

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
        WindowGroup(id: "home") {
            HomeView(dependencies: dependencies)
                .environmentObject(navState)
        }
        .modelContainer(modelContainer)

        WindowGroup(id: "exercise") {
            ExerciseWindowView(dependencies: dependencies)
                .environmentObject(debugTools)
                .environmentObject(runnerCommands)
                .environmentObject(navState)
        }
        .modelContainer(modelContainer)
        
        Settings {
            RunnerSettingsView()
                .environmentObject(debugTools)
                .environmentObject(runnerCommands)
        }
    }
}
