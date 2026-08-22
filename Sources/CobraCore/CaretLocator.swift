import AppKit
import ApplicationServices

/// Finds where the text caret is on screen, so the HUD can appear next to what
/// the user is typing instead of in a fixed corner.
public enum CaretLocator {
    /// Caret rect in Cocoa screen coordinates (bottom-left origin), or nil when
    /// the focused app does not expose one.
    ///
    /// Many apps — Electron editors especially — implement neither the selected
    /// range nor the bounds-for-range attribute, so callers need a fallback.
    public static func caretRect() -> CGRect? {
        let system = AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        let element = focused as! AXUIElement

        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else { return nil }

        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &bounds
        ) == .success, let bounds else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else { return nil }
        guard rect.width.isFinite, rect.height.isFinite, rect != .zero else { return nil }

        return flippedToCocoa(rect)
    }

    /// Accessibility reports rects with a top-left origin on the primary
    /// display; NSWindow expects bottom-left. Flip across the primary screen's
    /// height, which is what AX measures against even on multi-display setups.
    private static func flippedToCocoa(_ rect: CGRect) -> CGRect? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        return CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
