import Combine
import Foundation

@MainActor
final class DebugToolsStore: ObservableObject {
    @Published var runnerTuning: RunnerSceneRenderer.Tuning = .default
    @Published private(set) var isRunnerAttached: Bool = false

    private weak var runnerSceneRenderer: RunnerSceneRenderer?
    private var cancellables: Set<AnyCancellable> = []

    func attach(sceneRenderer: RunnerSceneRenderer) {
        runnerSceneRenderer = sceneRenderer
        isRunnerAttached = true
        runnerTuning = sceneRenderer.tuning

        cancellables.removeAll()

        $runnerTuning
            .removeDuplicates()
            .sink { [weak self] tuning in
                self?.runnerSceneRenderer?.tuning = tuning
            }
            .store(in: &cancellables)
    }

    func detach(sceneRenderer: RunnerSceneRenderer) {
        guard runnerSceneRenderer === sceneRenderer else { return }
        runnerSceneRenderer = nil
        isRunnerAttached = false
        cancellables.removeAll()
    }
}

