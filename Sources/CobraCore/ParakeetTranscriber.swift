import FluidAudio
import Foundation

/// Parakeet TDT 0.6B v3 running on CoreML.
///
/// Chosen over whisper.cpp because it runs in-process on the Neural Engine
/// rather than as a subprocess on the GPU: no HTTP hop, no child process to
/// supervise, lower power, and no contention with whatever else wants the GPU.
public actor ParakeetTranscriber: Transcriber {
    public enum Failure: LocalizedError {
        case notPrepared

        public var errorDescription: String? {
            switch self {
            case .notPrepared: return "The speech model has not finished loading yet."
            }
        }
    }

    private var manager: AsrManager?
    private let language: Language

    /// - Parameter language: Hint for v3's script-aware token filtering. Without
    ///   it the decoder will happily emit tokens from the wrong script, which is
    ///   accuracy given away for nothing.
    public init(language: Language = .english) {
        self.language = language
    }

    public func prepare(progress: @escaping @Sendable (TranscriberPreparation) -> Void) async throws {
        guard manager == nil else {
            progress(.ready)
            return
        }

        // Roughly 600 MB on first launch, cached under ~/.cache/fluidaudio
        // afterwards. Subsequent launches only pay CoreML compilation.
        let models = try await AsrModels.downloadAndLoad(version: .v3) { update in
            switch update.phase {
            case .downloading:
                progress(.downloading(fraction: update.fractionCompleted))
            default:
                progress(.loading)
            }
        }

        manager = AsrManager(config: .default, models: models)
        progress(.ready)
    }

    public func transcribe(samples: [Float]) async throws -> String {
        guard let manager else { throw Failure.notPrepared }

        // Each push-to-talk press is an independent utterance, so the decoder
        // starts fresh rather than carrying state across presses.
        var state = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &state, language: language)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
