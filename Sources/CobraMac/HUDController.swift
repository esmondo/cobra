import AppKit
import CobraCore
import SwiftUI

/// Hosts the recording HUD in a floating panel.
///
/// The panel must never take focus: Cobra types into whatever app the user was
/// already in, so stealing key status would break the very thing the HUD is
/// announcing. That is what `.nonactivatingPanel` plus `becomesKeyOnlyIfNeeded`
/// buy, and why the view ignores mouse events entirely.
@MainActor
final class HUDController {
    private let panel: NSPanel
    private let hostingView: NSHostingView<RecordingHUD>

    init(engine: DictationEngine) {
        hostingView = NSHostingView(rootView: RecordingHUD(engine: engine))

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false          // The SwiftUI capsule draws its own.
        // Toggled per state: the pill is inert while dictating so it never
        // steals a click, but must be clickable when it reports a problem the
        // user has to act on.
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .utilityWindow
    }

    func setVisible(_ visible: Bool, interactive: Bool = false) {
        guard visible else {
            panel.orderOut(nil)
            return
        }
        panel.ignoresMouseEvents = !interactive
        panel.setContentSize(hostingView.fittingSize)
        position()
        panel.orderFrontRegardless()
    }

    /// Places the pill just under the caret, falling back to the bottom of the
    /// active screen when the focused app exposes no caret — which is common in
    /// Electron apps and anything drawing its own text view.
    private func position() {
        let size = panel.frame.size
        let screen = NSScreen.main ?? NSScreen.screens[0]

        var origin: CGPoint
        if let caret = CaretLocator.caretRect() {
            origin = CGPoint(
                x: caret.midX - size.width / 2,
                y: caret.minY - size.height - Theme.Metrics.caretGap
            )
        } else {
            origin = CGPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.visibleFrame.minY + 80
            )
        }

        // Keep the whole pill on screen even when the caret sits at an edge.
        let bounds = screen.visibleFrame
        origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - size.width - 8)
        origin.y = min(max(origin.y, bounds.minY + 8), bounds.maxY - size.height - 8)

        panel.setFrameOrigin(origin)
    }
}
