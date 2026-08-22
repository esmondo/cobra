import AVFoundation
import FluidAudio
import Foundation
import os

/// Live transcription over a sliding window.
///
/// Uses the same Parakeet v3 weights as the batch path, so switching costs no
/// extra download. Audio is pushed in as it is captured and partial text comes
/// back before the user releases the key, which is what makes the HUD feel
/// responsive rather than merely fast.
public final class StreamingTranscriber: @unchecked Sendable {
    public enum Failure: LocalizedError {
        case notPrepared

        public var errorDescription: String? {
            switch self {
            case .notPrepared: return "The speech model has not finished loading yet."
            }
        }
    }

    private static let log = Logger(subsystem: "ai.cobra.mac", category: "streaming")

    private let language: Language
    private var models: AsrModels?

    /// Guards the continuation only. `yield` is itself thread-safe, but the
    /// optional around it is written from the main actor and read from the
    /// audio thread.
    private let lock = NSLock()
    private var continuation: AsyncStream<[Float]>.Continuation?

    private var manager: SlidingWindowAsrManager?
    /// Batch decoder over the same weights, used for the text that is actually
    /// inserted. Kept alive so the final pass costs no model loading.
    private var batch: AsrManager?
    private var pump: Task<Void, Never>?
    private var updates: Task<Void, Never>?

    /// Tuned for feedback latency, not for accuracy.
    ///
    /// The stock 11 s chunk only produces text once the chunk closes, measured
    /// at 12.65 s into a 11.77 s utterance — that is, after the user has
    /// finished speaking, which is no use as live feedback. A 2 s chunk brings
    /// the first partial to 2.68 s.
    ///
    /// Short windows cost real accuracy: the same clip degrades "path" to
    /// "pack" and "dictation" to "decades" at chunk seams. That is acceptable
    /// here only because these partials are never inserted — `finish` re-runs
    /// the complete utterance through the batch decoder, which has the whole
    /// recording as context.
    private static let streamingConfig = SlidingWindowAsrConfig(
        chunkSeconds: 2.0,
        hypothesisChunkSeconds: 0.5,
        leftContextSeconds: 2.0,
        rightContextSeconds: 0.5,
        minContextForConfirmation: 1.0,
        confirmationThreshold: 0.85
    )

    public init(language: Language = .english) {
        self.language = language
    }

    /// Downloads and loads the model. Roughly 460 MB on first launch, cached
    /// afterwards under Application Support.
    public func prepare(progress: @escaping @Sendable (TranscriberPreparation) -> Void) async throws {
        guard models == nil else {
            progress(.ready)
            return
        }
        let loaded = try await AsrModels.downloadAndLoad(version: .v3) { update in
            switch update.phase {
            case .downloading:
                progress(.downloading(fraction: update.fractionCompleted))
            default:
                progress(.loading)
            }
        }
        models = loaded
        batch = AsrManager(config: .default, models: loaded)
        progress(.ready)
    }

    /// Opens a session. `onPartial` fires on the main actor as text firms up.
    public func begin(onPartial: @escaping @Sendable (String) -> Void) async throws {
        guard let models else { throw Failure.notPrepared }

        // A fresh manager per utterance keeps decoder state from leaking across
        // presses; the weights themselves are shared, so this is cheap.
        let manager = SlidingWindowAsrManager(config: Self.streamingConfig.applying(language: language))
        try await manager.loadModels(models)
        try await manager.startStreaming()
        self.manager = manager

        let (stream, continuation) = AsyncStream<[Float]>.makeStream()
        setContinuation(continuation)

        // Confirmed text accumulates; the volatile tail is replaced each update.
        Self.log.notice("session begun")
        updates = Task {
            var confirmed = ""
            for await update in await manager.transcriptionUpdates {
                Self.log.notice("update confirmed=\(update.isConfirmed, privacy: .public) len=\(update.text.count, privacy: .public)")
                // Updates arrive as bare fragments with no separator, so
                // joining them naively produces run-ons like "packpath".
                if update.isConfirmed {
                    confirmed = Self.join(confirmed, update.text)
                    onPartial(confirmed)
                } else {
                    onPartial(Self.join(confirmed, update.text))
                }
            }
        }

        pump = Task {
            var fed = 0
            for await chunk in stream {
                guard let buffer = Self.makeBuffer(chunk) else { continue }
                fed += chunk.count
                await manager.streamAudio(buffer)
            }
            Self.log.notice("fed \(fed, privacy: .public) samples")
        }
    }

    /// Pushes captured audio. Safe to call from the audio thread.
    public func feed(_ chunk: [Float]) {
        currentContinuation()?.yield(chunk)
    }

    private func setContinuation(_ value: AsyncStream<[Float]>.Continuation?) {
        lock.lock()
        defer { lock.unlock() }
        continuation = value
    }

    private func currentContinuation() -> AsyncStream<[Float]>.Continuation? {
        lock.lock()
        defer { lock.unlock() }
        return continuation
    }

    /// Ends the input stream and clears it in one atomic step.
    private func closeContinuation() {
        lock.lock()
        let existing = continuation
        continuation = nil
        lock.unlock()
        existing?.finish()
    }

    /// Closes the session and transcribes the complete utterance.
    ///
    /// The streaming transcript is deliberately discarded. Its short windows
    /// are what make partials fast, and they are also what makes it wrong at
    /// seams; one batch pass over the whole recording sees full context and
    /// costs about 0.15 s for 12 s of audio on an M2.
    public func finish(samples: [Float]) async throws -> String {
        closeContinuation()

        await pump?.value          // Drain queued audio before asking to finish.
        if let manager { _ = try? await manager.finish() }
        teardown()

        guard let batch else { throw Failure.notPrepared }
        var state = try TdtDecoderState()
        let result = try await batch.transcribe(samples, decoderState: &state, language: language)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Joins transcript fragments, inserting a space only where both sides
    /// need one.
    private static func join(_ existing: String, _ addition: String) -> String {
        guard !existing.isEmpty else { return addition }
        guard !addition.isEmpty else { return existing }
        let needsSpace = !existing.hasSuffix(" ") && !addition.hasPrefix(" ")
        return existing + (needsSpace ? " " : "") + addition
    }

    public func cancel() async {
        closeContinuation()
        pump?.cancel()
        if let manager { await manager.cancel() }
        teardown()
    }

    private func teardown() {
        updates?.cancel()
        updates = nil
        pump = nil
        manager = nil
    }

    private static func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
