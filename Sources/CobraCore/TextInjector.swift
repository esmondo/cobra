import AppKit
import os
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
    public final class Target: @unchecked Sendable {
        public let context: AppContext
        fileprivate let element: AXUIElement

        fileprivate init(context: AppContext, element: AXUIElement) {
            self.context = context
            self.element = element
        }
    }

    /// Command-V needs the keycode for `v` on the ANSI layout.
    private static let vKeyCode: CGKeyCode = 9

    /// How long to let the target app read the pasteboard before restoring it.
    private static let pasteboardRestoreDelay: TimeInterval = 0.25

    /// Hints understood by well-behaved clipboard managers. They do not make
    /// the general pasteboard private, so SECURITY.md still discloses the risk.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let maximumPasteboardSnapshotBytes = 16 * 1024 * 1024
    private static let maximumPasteboardItems = 32
    private static let maximumPasteboardTypes = 128

    public enum Method: String, Sendable {
        case accessibility
        case pasteboard
        case focusChanged
        case pasteboardUnavailable
        case secureField
    }

    /// Captures the exact focused Accessibility element. The second lookup
    /// rejects a focus transition that occurs while the target is assembled.
    public static func captureTarget() -> Target? {
        guard let element = focusedElement() else { return nil }
        let context = AppContext.current()
        guard context.processIdentifier > 0,
              !context.bundleID.isEmpty,
              let confirmed = focusedElement(),
              CFEqual(element, confirmed)
        else { return nil }
        return Target(context: context, element: element)
    }

    @discardableResult
    public static func inject(_ text: String, into target: Target) -> Method {
        guard !text.isEmpty else { return .accessibility }

        // Resolve the element that holds focus now rather than insisting on the
        // one captured when recording began. Some apps rebuild their
        // accessibility tree between queries, so the captured reference can
        // stop comparing equal even though focus never moved. Within a
        // confirmed-identical process the live element is also the better
        // target: it is where the caret actually is.
        guard let element = currentElement(for: target) else { return .focusChanged }
        guard !isSecureTextField(element) else { return .secureField }

        if injectViaAccessibility(text, into: element) {
            return .accessibility
        }
        guard currentElement(for: target) != nil else { return .focusChanged }
        guard injectViaPasteboard(text, target: target) else {
            return currentElement(for: target) != nil ? .pasteboardUnavailable : .focusChanged
        }
        return .pasteboard
    }

    /// The focused element, but only while the same application still owns
    /// focus. Returns nil once focus has left the process that was recorded
    /// into, which is the case this guard exists to catch.
    private static func currentElement(for target: Target) -> AXUIElement? {
        let now = AppContext.current()
        guard target.context.matchesInjectionTarget(now) else {
            log.notice("""
                focus left process: pid \(target.context.processIdentifier, privacy: .public)\
                ->\(now.processIdentifier, privacy: .public) \
                bundle \(target.context.bundleID, privacy: .public)->\(now.bundleID, privacy: .public)
                """)
            return nil
        }
        return focusedElement()
    }

    private static let log = Logger(subsystem: "ai.cobra.mac", category: "inject")

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }

        return (focused as! AXUIElement)
    }

    /// Whether the focused element is a password field.
    ///
    /// Only an explicit `AXSecureTextField` subrole counts. Treating an
    /// unreadable subrole as secure sounds like the safe default, but plenty of
    /// ordinary fields — Electron editors, custom text views — publish no
    /// subrole at all, so failing closed suppressed injection nearly
    /// everywhere. Secure fields do advertise the subrole, which is what makes
    /// the positive test sufficient.
    private static func isSecureTextField(_ element: AXUIElement) -> Bool {
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
              let subrole = subrole as? String
        else { return false }
        return subrole == "AXSecureTextField"
    }

    private static func injectViaAccessibility(_ text: String, into element: AXUIElement) -> Bool {
        // Only attempt this where the element actually advertises editable text;
        // otherwise a "success" can silently drop the insert.
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }

        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    private static func injectViaPasteboard(_ text: String, target: Target) -> Bool {
        let pasteboard = NSPasteboard.general
        guard let saved = snapshot(pasteboard) else { return false }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: concealedType)
        pasteboard.setData(Data(), forType: transientType)
        let injectedChangeCount = pasteboard.changeCount

        guard currentElement(for: target) != nil else {
            if pasteboard.changeCount == injectedChangeCount {
                restore(saved, to: pasteboard)
            }
            return false
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + pasteboardRestoreDelay) {
            // Do not overwrite a copy the user made while Cobra's paste was in
            // flight. Reading the pasteboard does not increment changeCount.
            guard pasteboard.changeCount == injectedChangeCount else { return }
            restore(saved, to: pasteboard)
        }
        return true
    }

    private struct PasteboardItemSnapshot {
        let values: [(type: String, data: Data)]
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [PasteboardItemSnapshot]? {
        let items = pasteboard.pasteboardItems ?? []
        guard items.count <= maximumPasteboardItems else { return nil }

        var totalBytes = 0
        var totalTypes = 0
        var snapshots: [PasteboardItemSnapshot] = []
        for item in items {
            var values: [(type: String, data: Data)] = []
            for type in item.types {
                totalTypes += 1
                guard totalTypes <= maximumPasteboardTypes,
                      let data = item.data(forType: type)
                else { return nil }
                totalBytes += data.count
                guard totalBytes <= maximumPasteboardSnapshotBytes else { return nil }
                values.append((type.rawValue, data))
            }
            snapshots.append(PasteboardItemSnapshot(values: values))
        }
        return snapshots
    }

    private static func restore(_ saved: [PasteboardItemSnapshot], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = saved.map { snapshot in
            let item = NSPasteboardItem()
            for value in snapshot.values {
                item.setData(value.data, forType: NSPasteboard.PasteboardType(value.type))
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
