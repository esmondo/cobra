import AppKit
import Combine
import CobraCore
import SwiftUI

@main
struct CobraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var engine = DictationEngine.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(engine: engine)
        } label: {
            // Deliberately bare. NSStatusItem sizes itself from this view, and
            // hanging async work off it (a .task that starts the engine) let it
            // measure as zero-width and never recover — the icon simply never
            // appeared. Lifecycle belongs in the AppDelegate.
            // The cobra mark while things are healthy; SF Symbols carry the
            // exceptional states, where a recognisable warning beats branding.
            Group {
                if let symbol = engine.state.alertSymbol {
                    Image(systemName: symbol)
                } else {
                    Image(nsImage: engine.state.isWorking ? CobraMark.active : CobraMark.template)
                }
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hud: HUDController?
    private var observation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let engine = DictationEngine.shared
        let hud = HUDController(engine: engine)
        self.hud = hud

        observation = engine.$state
            .receive(on: RunLoop.main)
            .sink { state in
                hud.setVisible(state.showsHUD, interactive: state.isActionable)
            }

        Task { await engine.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DictationEngine.shared.shutdown()
    }
}

private struct MenuContent: View {
    @ObservedObject var engine: DictationEngine

    var body: some View {
        Text(engine.state.summary)

        if engine.missing != nil {
            Button("Open System Settings…") {
                engine.openSettingsForMissingPermission()
            }
        }

        if !engine.lastTranscript.isEmpty {
            Divider()
            Text("Saved transcript available")
            Button("Copy saved transcript") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(engine.lastTranscript, forType: .string)
                engine.clearSavedTranscript()
            }
            Button("Discard saved transcript") {
                engine.clearSavedTranscript()
            }
        }

        Divider()
        Toggle("Microphone", isOn: Binding(
            get: { engine.isMicrophoneEnabled },
            set: { engine.setMicrophoneEnabled($0) }
        ))

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

extension DictationEngine.State {
    /// The HUD is for moments the user needs feedback on. Idle is not one of
    /// them — a permanently visible pill would just be clutter.
    var showsHUD: Bool {
        switch self {
        case .idle: return false
        case .preparing(.ready): return false
        // A deliberate off switch is not a problem to report; the menu bar
        // already shows it, and a permanent pill on screen would be nagging.
        case .microphoneOff: return false
        default: return true
        }
    }

    /// States where clicking the pill should do something.
    var isActionable: Bool {
        if case .needsPermission = self { return true }
        return false
    }

    /// Non-nil only for states the user has to act on, where a familiar system
    /// symbol communicates faster than a brand mark.
    var alertSymbol: String? {
        switch self {
        case .microphoneOff: return "mic.slash"
        case .needsPermission: return "lock.trianglebadge.exclamationmark"
        case .failed: return "exclamationmark.triangle"
        case .preparing(.downloading): return "arrow.down.circle"
        default: return nil
        }
    }

    /// Venom while Cobra is working; otherwise the template mark, which lets
    /// the menu bar tint it like every other status item.
    var isWorking: Bool {
        switch self {
        case .recording, .transcribing: return true
        default: return false
        }
    }

    var summary: String {
        switch self {
        case .preparing(.downloading(let fraction)): return "Downloading speech model… \(Int(fraction * 100))%"
        case .preparing: return "Loading speech model…"
        case .idle: return "Ready"
        case .microphoneOff: return "Microphone off"
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .notice(let message): return message
        case .needsPermission(let message): return message
        case .failed(let message): return "Error: \(message)"
        }
    }
}
