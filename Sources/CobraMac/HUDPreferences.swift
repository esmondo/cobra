import Foundation

/// Where the recording pill appears. Presentation only, so it lives here rather
/// than on the engine.
@MainActor
final class HUDPreferences: ObservableObject {
    static let shared = HUDPreferences()

    private static let followsPointerKey = "cobra.hud.followsPointer"

    /// Follow the mouse pointer rather than the text caret.
    ///
    /// Defaults to on: caret tracking needs the focused app to publish
    /// `kAXBoundsForRangeParameterizedAttribute`, which most do not, so the
    /// caret mode lands at the bottom of the screen more often than beside the
    /// text — far from wherever the user is looking.
    @Published var followsPointer: Bool {
        didSet { UserDefaults.standard.set(followsPointer, forKey: Self.followsPointerKey) }
    }

    private init() {
        followsPointer = UserDefaults.standard.object(forKey: Self.followsPointerKey) as? Bool ?? true
    }
}
