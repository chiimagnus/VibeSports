import AppKit
import SwiftUI

struct KeyboardInputCaptureView: NSViewRepresentable {
    var onKeyDown: (KeyboardDebugInputState.Key) -> Void
    var onKeyUp: (KeyboardDebugInputState.Key) -> Void

    func makeNSView(context: Context) -> KeyboardCaptureNSView {
        let view = KeyboardCaptureNSView()
        view.onKeyDown = onKeyDown
        view.onKeyUp = onKeyUp
        return view
    }

    func updateNSView(_ nsView: KeyboardCaptureNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
        nsView.onKeyUp = onKeyUp
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class KeyboardCaptureNSView: NSView {
    var onKeyDown: ((KeyboardDebugInputState.Key) -> Void)?
    var onKeyUp: ((KeyboardDebugInputState.Key) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard let key = Self.key(from: event) else {
            super.keyDown(with: event)
            return
        }
        onKeyDown?(key)
    }

    override func keyUp(with event: NSEvent) {
        guard let key = Self.key(from: event) else {
            super.keyUp(with: event)
            return
        }
        onKeyUp?(key)
    }

    private static func key(from event: NSEvent) -> KeyboardDebugInputState.Key? {
        guard let text = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        guard let character = text.first else { return nil }
        switch character {
        case "w":
            return .w
        case "a":
            return .a
        case "s":
            return .s
        case "d":
            return .d
        default:
            return nil
        }
    }
}
