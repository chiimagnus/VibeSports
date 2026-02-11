import AppKit
import SwiftUI

struct KeyboardInputCaptureView: NSViewRepresentable {
    var onKeyDown: (KeyboardDebugInputState.Key) -> Void
    var onKeyUp: (KeyboardDebugInputState.Key) -> Void
    var onBoostModifierChanged: (Bool) -> Void

    func makeNSView(context: Context) -> KeyboardCaptureNSView {
        let view = KeyboardCaptureNSView()
        view.onKeyDown = onKeyDown
        view.onKeyUp = onKeyUp
        view.onBoostModifierChanged = onBoostModifierChanged
        return view
    }

    func updateNSView(_ nsView: KeyboardCaptureNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
        nsView.onKeyUp = onKeyUp
        nsView.onBoostModifierChanged = onBoostModifierChanged
    }

    static func dismantleNSView(_ nsView: KeyboardCaptureNSView, coordinator: ()) {
        nsView.teardownMonitors()
    }
}

final class KeyboardCaptureNSView: NSView {
    var onKeyDown: ((KeyboardDebugInputState.Key) -> Void)?
    var onKeyUp: ((KeyboardDebugInputState.Key) -> Void)?
    var onBoostModifierChanged: ((Bool) -> Void)?

    private weak var monitoredWindow: NSWindow?
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var flagsChangedMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitorsIfNeeded()
    }

    override func removeFromSuperview() {
        super.removeFromSuperview()
        teardownMonitors()
    }

    func teardownMonitors() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let keyUpMonitor {
            NSEvent.removeMonitor(keyUpMonitor)
            self.keyUpMonitor = nil
        }
        if let flagsChangedMonitor {
            NSEvent.removeMonitor(flagsChangedMonitor)
            self.flagsChangedMonitor = nil
        }
        monitoredWindow = nil
    }

    private func installMonitorsIfNeeded() {
        guard let window else { return }
        if monitoredWindow === window { return }

        teardownMonitors()
        monitoredWindow = window

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.shouldHandle(event: event) else { return event }
            self.onBoostModifierChanged?(event.modifierFlags.contains(.shift))
            guard let key = Self.key(from: event) else { return event }
            self.onKeyDown?(key)
            // Swallow handled WASD events to avoid system alert sound from responder fallback.
            return nil
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            guard self.shouldHandle(event: event) else { return event }
            self.onBoostModifierChanged?(event.modifierFlags.contains(.shift))
            guard let key = Self.key(from: event) else { return event }
            self.onKeyUp?(key)
            return nil
        }

        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            guard self.shouldObserveWindow(event: event) else { return event }
            self.onBoostModifierChanged?(event.modifierFlags.contains(.shift))
            return event
        }
    }

    private func shouldHandle(event: NSEvent) -> Bool {
        guard shouldObserveWindow(event: event) else {
            return false
        }
        if event.modifierFlags.contains(.command)
            || event.modifierFlags.contains(.option)
            || event.modifierFlags.contains(.control)
            || event.modifierFlags.contains(.function) {
            return false
        }
        return true
    }

    private func shouldObserveWindow(event: NSEvent) -> Bool {
        guard let monitoredWindow else { return false }
        guard event.window === monitoredWindow, monitoredWindow.isKeyWindow else {
            return false
        }
        if let firstResponder = monitoredWindow.firstResponder as? NSTextView,
           firstResponder.isFieldEditor {
            return false
        }
        return true
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
