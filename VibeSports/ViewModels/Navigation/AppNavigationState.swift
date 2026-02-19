import Combine
import Foundation

@MainActor
final class AppNavigationState: ObservableObject {
    @Published var selectedExerciseKind: ExerciseKind = .running
}
