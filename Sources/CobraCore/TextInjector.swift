import AppKit
import ApplicationServices
import CoreGraphics

/// Puts text into whatever text field currently has focus, in any app.
///
/// Two strategies, tried in order:
///
/// 1. Accessibility — set the focused element's selected text. Clean, leaves the
///    pasteboard alone, and respects the caret. Native Cocoa apps support it;
///    many Electron and custom-drawn editors do not.
/// 2. Pasteboard + synthetic Command-V. Works essentially everywhere, at the
///    cost of briefly clobbering the clipboard.
public enum TextInjector {
    /// Command-V needs the keycode for `v` on the ANSI layout.
    private static let vKeyCode: CGKeyCode = 9

    /// How long to let the target app read the pasteboard before restoring it.
    private static let pasteboardRestoreDelay: TimeInterval = 0.25

    public enum Method: String, Sendable {
        case accessibility
        case pasteboard
    }

    @discardableResult
    public static func inject(_ text: String) -> Method {
        guard !text.isEmpty else { return .accessibility }

        if injectViaAccessibility(text) {
            return .accessibility
        }
        injectViaPasteboard(text)
        return .pasteboard
    }

    private static func injectViaAccessibility(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return false }

        let element = focused as! AXUIElement

        // Only attempt this where the element actually advertises editable text;
        // otherwise a "success" can silently drop the insert.
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }

        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    private static func injectViaPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Restoring only the plain-string flavor loses richer clipboard content.
        // Acceptable for now; a full multi-type snapshot belongs in v1.
        guard let saved else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteboardRestoreDelay) {
            pasteboard.clearContents()
            pasteboard.setString(saved, forType: .string)
        }
    }
}
