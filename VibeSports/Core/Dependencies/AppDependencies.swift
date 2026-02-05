import Foundation

struct AppDependencies {
    var clock: Clock

    static func live() -> AppDependencies {
        AppDependencies(clock: SystemClock())
    }
}

