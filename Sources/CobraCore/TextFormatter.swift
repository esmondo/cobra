import Foundation

/// Cleans up a raw transcript before it is typed into the focused app.
///
/// This is the layer that separates dictation from transcription: verbatim
/// speech reads badly, and the value is in the rewrite.
public protocol TextFormatter: Sendable {
    func format(_ raw: String, context: AppContext) async -> String
}

/// Deterministic cleanup with no model behind it. Fast, private, and free —
/// good enough for the skeleton, and the fallback whenever a smarter formatter
/// is unavailable or times out.
public struct RuleFormatter: TextFormatter {
    /// Whisper emits non-speech annotations in brackets when it hears noise.
    private static let annotation = try! NSRegularExpression(pattern: #"[\(\[][^\)\]]{0,40}[\)\]]"#)

    /// Only fillers that are almost never meaningful words in their own right.
    /// "like" and "so" are deliberately absent — stripping them corrupts real sentences.
    private static let fillers: Set<String> = ["um", "uh", "erm", "uhh", "umm", "hmm", "mhm"]

    public init() {}

    public func format(_ raw: String, context: AppContext) async -> String {
        let range = NSRange(raw.startIndex..., in: raw)
        var text = Self.annotation.stringByReplacingMatches(in: raw, range: range, withTemplate: "")

        text = text
            .split(separator: " ", omittingEmptySubsequences: true)
            .filter { word in
                let bare = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                return !Self.fillers.contains(bare)
            }
            .joined(separator: " ")

        text = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
