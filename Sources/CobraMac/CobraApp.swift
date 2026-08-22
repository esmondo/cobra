import AppKit
import CobraCore
import SwiftUI

@main
struct CobraApp: App {
    @StateObject private var engine = DictationEngine()
    @State private var hud: HUDController?

    var body: some Scene {
        MenuBarExtra {
            MenuContent(engine: engine)
        } label: {
            // Startup hangs off the label, not the menu content: with
            // `.menuBarExtraStyle(.menu)` the content closure is not evaluated
            // until the user opens the menu, but the label renders at launch.
            MenuBarGlyph(state: engine.state)
                .task {
                    hud = HUDController(engine: engine)
                    await engine.start()
                }
                .onChange(of: engine.state) { _, state in
                    hud?.setVisible(state.showsHUD)
                }
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarGlyph: View {
    let state: DictationEngine.State

    var body: some View {
        Image(systemName: state.symbolName)
            .symbolRenderingMode(state.isVenom ? .palette : .hierarchical)
            .foregroundStyle(state.isVenom ? Theme.Palette.venom : Color.primary)
    }
}

private struct MenuContent: View {
    @ObservedObject var engine: DictationEngine

    var body: some View {
        Text(engine.state.summary)

        if !engine.lastTranscript.isEmpty {
            Divider()
            Text("Last: \(engine.lastTranscript.prefix(60))")
        }

        Divider()
        Text("Hold fn to dictate")
        Text(engine.isHandsFree ? "Hands-free: on" : "Double-tap right Shift for hands-free")

        Divider()
        Button("Quit Cobra") {
            engine.shutdown()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

private extension DictationEngine.State {
    /// The HUD is for moments the user needs feedback on. Idle is not one of
    /// them — a permanently visible pill would just be clutter.
    var showsHUD: Bool {
        switch self {
        case .idle: return false
        case .preparing(.ready): return false
        default: return true
        }
    }

    /// Accent the menu bar icon only while Cobra is actually doing something.
    var isVenom: Bool {
        self == .recording || self == .transcribing
    }

    var symbolName: String {
        switch self {
        case .preparing: return "arrow.down.circle"
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .needsPermission: return "lock.trianglebadge.exclamationmark"
        case .failed: return "exclamationmark.triangle"
        }
    }

    var summary: String {
        switch self {
        case .preparing(.downloading(let fraction)): return "Downloading speech model… \(Int(fraction * 100))%"
        case .preparing: return "Loading speech model…"
        case .idle: return "Ready"
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .needsPermission(let message): return message
        case .failed(let message): return "Error: \(message)"
        }
    }
}
