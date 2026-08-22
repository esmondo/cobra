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
    /// Pointer tracking cadence. Polled rather than driven by a global mouse
    /// monitor: the panel has to keep up during drags and across spaces, where
    /// event delivery to a background observer is not guaranteed.
    private static let followInterval: TimeInterval = 1.0 / 60.0

    private let panel: NSPanel
    private let hostingView: NSHostingView<RecordingHUD>
    private var followTimer: Timer?
    private var lastPointer: CGPoint?

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
            stopFollowing()
            panel.orderOut(nil)
            return
        }
        panel.ignoresMouseEvents = !interactive
        panel.setContentSize(hostingView.fittingSize)
        position()
        panel.orderFrontRegardless()

        if HUDPreferences.shared.followsPointer {
            startFollowing()
        }
    }

    private func startFollowing() {
        guard followTimer == nil else { return }
        let timer = Timer(timeInterval: Self.followInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followPointer() }
        }
        // Common modes, or the pill freezes while a menu is open or a window
        // is being dragged.
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private func stopFollowing() {
        followTimer?.invalidate()
        followTimer = nil
        lastPointer = nil
    }

    private func followPointer() {
        let pointer = NSEvent.mouseLocation
        // Repositioning a window 60 times a second regardless of whether the
        // pointer moved is wasted work; most frames it is stationary.
        if let last = lastPointer, abs(last.x - pointer.x) < 0.5, abs(last.y - pointer.y) < 0.5 {
            return
        }
        lastPointer = pointer
        position()
    }

    /// Places the pill just under the caret, falling back to the bottom of the
    /// active screen when the focused app exposes no caret — which is common in
    /// Electron apps and anything drawing its own text view.
    private func position() {
        let size = panel.frame.size
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        var origin: CGPoint
        if HUDPreferences.shared.followsPointer {
            // Level with the cursor and to its right. The pill is centred
            // within the panel, so halving the frame height puts the pill's
            // midline on the pointer rather than its top edge.
            origin = CGPoint(
                x: pointer.x + Theme.Metrics.caretGap,
                y: pointer.y - size.height / 2
            )
        } else if let caret = CaretLocator.caretRect() {
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
