import AppKit
import CoreGraphics
import Foundation

public enum HotkeyEvent: Sendable {
    /// The push-to-talk key went down.
    case pushToTalkBegan
    /// The push-to-talk key came back up.
    case pushToTalkEnded
    /// The hands-free key was double-tapped.
    case handsFreeToggled
}

/// Watches for the global dictation hotkeys.
///
/// Both triggers are modifier-only keys, which `RegisterEventHotKey` cannot
/// observe — only a CGEventTap on `.flagsChanged` sees them. That tap requires
/// the Accessibility permission, so `start()` fails until the user grants it.
public final class HotkeyMonitor {
    /// Globe/fn. Held down to dictate.
    private static let fnKeyCode: Int64 = 63
    /// Right Shift. Double-tapped to toggle hands-free mode.
    private static let rightShiftKeyCode: Int64 = 60
    /// Two taps further apart than this are treated as unrelated.
    private static let doubleTapWindow: TimeInterval = 0.4

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnIsDown = false
    private var lastRightShiftPress: TimeInterval = 0
    private let handler: @Sendable (HotkeyEvent) -> Void

    public init(handler: @escaping @Sendable (HotkeyEvent) -> Void) {
        self.handler = handler
    }

    /// Whether this process already holds the Accessibility permission.
    /// Pass `prompt: true` to surface the system dialog when it does not.
    public static func hasAccessibilityPermission(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Shows the system Accessibility dialog once. Calling this repeatedly
    /// reopens the dialog every time, so it belongs at a deliberate moment
    /// rather than inside a polling loop.
    public static func promptForAccessibility() {
        _ = hasAccessibilityPermission(prompt: true)
    }

    /// Arms the event tap. Returns false when Accessibility has not been
    /// granted.
    ///
    /// Deliberately does not consult `AXIsProcessTrusted` first. That value is
    /// cached per process and frequently keeps reporting false for the rest of
    /// the process's lifetime after a grant, which strands the app in a state
    /// only a relaunch can clear. Whether the tap can be created is the ground
    /// truth for what this type actually needs, so ask that instead.
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        return true
    }

    public func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        fnIsDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that blocks for too long; re-arm it rather
        // than silently losing every hotkey from that point on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        switch keyCode {
        case Self.fnKeyCode:
            let isDown = flags.contains(.maskSecondaryFn)
            if isDown != fnIsDown {
                fnIsDown = isDown
                handler(isDown ? .pushToTalkBegan : .pushToTalkEnded)
            }

        case Self.rightShiftKeyCode:
            // Only the press edge counts, so one tap is one event, not two.
            guard flags.contains(.maskShift) else { break }
            let now = Date.timeIntervalSinceReferenceDate
            if now - lastRightShiftPress < Self.doubleTapWindow {
                lastRightShiftPress = 0
                handler(.handsFreeToggled)
            } else {
                lastRightShiftPress = now
            }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    deinit { stop() }
}
