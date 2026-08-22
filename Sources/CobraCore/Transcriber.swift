import Foundation

/// What a backend is doing while it gets itself ready. First launch may have to
/// fetch a model over the network, which is far too slow to hide behind a
/// spinner with no explanation.
public enum TranscriberPreparation: Sendable, Equatable {
    case downloading(fraction: Double)
    case loading
    case ready
}

/// Turns 16 kHz mono Float32 samples into text.
///
/// Everything downstream depends only on this protocol, so the CoreML backend
/// can be swapped for Apple's `SpeechAnalyzer` on macOS 26 without touching the
/// engine or the UI.
public protocol Transcriber: Sendable {
    /// Loads whatever the backend needs. Must finish before `transcribe`.
    func prepare(progress: @escaping @Sendable (TranscriberPreparation) -> Void) async throws

    func transcribe(samples: [Float]) async throws -> String
}
