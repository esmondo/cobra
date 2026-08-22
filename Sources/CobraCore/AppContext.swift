import AppKit
import ApplicationServices

/// What the user is looking at when they start dictating. The formatter uses
/// this to pick a tone — a Slack message and a commit body want different prose
/// out of the same sentence.
public struct AppContext: Sendable, Equatable {
    public let bundleID: String
    public let appName: String
    public let windowTitle: String?
    public let processIdentifier: pid_t

    public init(bundleID: String, appName: String, windowTitle: String?, processIdentifier: pid_t = 0) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.processIdentifier = processIdentifier
    }

    public static let unknown = AppContext(bundleID: "", appName: "Unknown", windowTitle: nil, processIdentifier: 0)

    public static func current() -> AppContext {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .unknown }
        return AppContext(
            bundleID: app.bundleIdentifier ?? "",
            appName: app.localizedName ?? "Unknown",
            windowTitle: focusedWindowTitle(pid: app.processIdentifier),
            processIdentifier: app.processIdentifier
        )
    }

    /// Injection is safe only while the application and focused window that
    /// received the dictation are still in front. The PID distinguishes two
    /// running copies of one app; the title distinguishes its windows.
    public func matchesInjectionTarget(_ other: AppContext) -> Bool {
        guard processIdentifier > 0,
              !bundleID.isEmpty,
              processIdentifier == other.processIdentifier,
              bundleID == other.bundleID
        else { return false }

        return windowTitle == other.windowTitle
    }

    private static func focusedWindowTitle(pid: pid_t) -> String? {
        let element = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window else { return nil }

        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success
        else { return nil }
        return title as? String
    }
}

/// Coarse buckets that map many bundle IDs onto a handful of writing styles.
public enum ToneProfile: String, Sendable, CaseIterable {
    case chat
    case email
    case code
    case document

    public init(context: AppContext) {
        switch context.bundleID {
        case "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.apple.MobileSMS",
             "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram":
            self = .chat
        case "com.apple.mail", "com.google.Chrome", "com.superhuman.electron", "com.readdle.smartemail-Mac":
            self = .email
        case "com.microsoft.VSCode", "com.apple.Terminal", "com.googlecode.iterm2",
             "dev.warp.Warp-Stable", "com.todesktop.230313mzl4w4u92":
            self = .code
        default:
            self = .document
        }
    }

    public var instruction: String {
        switch self {
        case .chat: return "Casual and short. Contractions are fine. No greeting or sign-off."
        case .email: return "Clear and professional, but not stiff. Full sentences."
        case .code: return "Terse and technical. Preserve identifiers and command names exactly."
        case .document: return "Clean prose with normal punctuation."
        }
    }
}
