import Foundation
import SwiftUI

/// Watches GitHub Releases for a newer version.
///
/// Deliberately does not download or install anything. Cobra is signed with a
/// self-signed certificate, so an app fetched from the internet is quarantined
/// and refused by Gatekeeper; silently replacing the running app with one the
/// user cannot open would be worse than telling them a release exists.
@MainActor
public final class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()

    public struct Release: Equatable, Sendable {
        public let version: String
        public let url: URL
        public let notes: String
    }

    /// Unauthenticated GitHub API, which allows 60 requests an hour per address
    /// — far more than a six-hourly check needs.
    private static let endpoint = URL(string: "https://api.github.com/repos/esmondo/cobra/releases/latest")!
    private static let interval: TimeInterval = 6 * 60 * 60
    private static let enabledKey = "cobra.updates.enabled"

    @Published public private(set) var available: Release?
    @Published public private(set) var lastChecked: Date?

    /// Update checks contact GitHub, which reveals this machine's address and
    /// roughly when Cobra runs. That is worth being able to decline.
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { start() } else { stop() }
        }
    }

    private var timer: Timer?

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    public var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    public func start() {
        guard isEnabled, timer == nil else { return }
        Task { await check() }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.check() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        available = nil
    }

    public func check() async {
        guard isEnabled else { return }
        defer { lastChecked = Date() }

        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let page = object["html_url"] as? String,
              let url = URL(string: page)
        else { return }

        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Self.isNewer(latest, than: currentVersion) else {
            available = nil
            return
        }

        available = Release(
            version: latest,
            url: url,
            notes: (object["body"] as? String) ?? ""
        )
    }

    /// Numeric component comparison, so 0.10.0 sorts above 0.9.0 — which a
    /// string comparison would get backwards.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }
}
