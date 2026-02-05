import Combine
import Foundation

@MainActor
final class RunnerGameHomeViewModel: ObservableObject {
    @Published var userWeightKg: Double = 60
    @Published var isPresentingSession = false

    private let settingsRepository: any SettingsRepository

    init(settingsRepository: any SettingsRepository) {
        self.settingsRepository = settingsRepository
    }

    func load() {
        do {
            let settings = try settingsRepository.load()
            userWeightKg = settings.userWeightKg
        } catch {
            userWeightKg = 60
        }
    }

    func updateUserWeightKg(_ weightKg: Double) {
        let clamped = max(0, weightKg)
        userWeightKg = clamped
        do {
            try settingsRepository.updateUserWeightKg(clamped)
        } catch {
            // Best-effort persistence; UI still updates.
        }
    }

    func startSessionTapped() {
        isPresentingSession = true
    }
}

