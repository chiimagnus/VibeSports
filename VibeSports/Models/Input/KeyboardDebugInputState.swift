struct KeyboardDebugInputState: Sendable, Equatable {
    enum Key: Hashable, Sendable {
        case w
        case a
        case s
        case d
    }

    private var pressedKeys: Set<Key> = []

    mutating func keyDown(_ key: Key) {
        pressedKeys.insert(key)
    }

    mutating func keyUp(_ key: Key) {
        pressedKeys.remove(key)
    }

    mutating func reset() {
        pressedKeys.removeAll(keepingCapacity: true)
    }

    var turnInput: Double {
        let left = pressedKeys.contains(.a)
        let right = pressedKeys.contains(.d)
        switch (left, right) {
        case (true, false):
            return 1
        case (false, true):
            return -1
        default:
            return 0
        }
    }

    var forwardInput: Double {
        let forward = pressedKeys.contains(.w)
        let backward = pressedKeys.contains(.s)
        switch (forward, backward) {
        case (true, false):
            return 1
        case (false, true):
            return -1
        default:
            return 0
        }
    }

    var controlInput: RunnerControlInput {
        RunnerControlInput(
            turnInput: turnInput,
            forwardInput: forwardInput
        )
    }
}
