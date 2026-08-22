import AppKit
import CobraCore
import SwiftUI

@main
struct CobraApp: App {
    @StateObject private var engine = DictationEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(engine: engine)
        } label: {
            // Startup hangs off the label, not the menu content: with
            // `.menuBarExtraStyle(.menu)` the content closure is not evaluated
            // until the user opens the menu, but the label renders at launch.
            Image(systemName: engine.state.symbolName)
                .symbolRenderingMode(.hierarchical)
                .task { await engine.start() }
        }
        .menuBarExtraStyle(.menu)
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
    var symbolName: String {
        switch self {
        case .starting: return "hourglass"
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .needsPermission: return "lock.trianglebadge.exclamationmark"
        case .failed: return "exclamationmark.triangle"
        }
    }

    var summary: String {
        switch self {
        case .starting: return "Starting speech engine…"
        case .idle: return "Ready"
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .needsPermission(let message): return message
        case .failed(let message): return "Error: \(message)"
        }
    }
}
