import AVFoundation
import FluidAudio
import Foundation

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

    private let language: Language
    private var models: AsrModels?

    /// Guards the continuation only. `yield` is itself thread-safe, but the
    /// optional around it is written from the main actor and read from the
    /// audio thread.
    private let lock = NSLock()
    private var continuation: AsyncStream<[Float]>.Continuation?

    private var manager: SlidingWindowAsrManager?
    private var pump: Task<Void, Never>?
    private var updates: Task<Void, Never>?

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
        models = try await AsrModels.downloadAndLoad(version: .v3) { update in
            switch update.phase {
            case .downloading:
                progress(.downloading(fraction: update.fractionCompleted))
            default:
                progress(.loading)
            }
        }
        progress(.ready)
    }

    /// Opens a session. `onPartial` fires on the main actor as text firms up.
    public func begin(onPartial: @escaping @Sendable (String) -> Void) async throws {
        guard let models else { throw Failure.notPrepared }

        // A fresh manager per utterance keeps decoder state from leaking across
        // presses; the weights themselves are shared, so this is cheap.
        let manager = SlidingWindowAsrManager(config: .default.applying(language: language))
        try await manager.loadModels(models)
        try await manager.startStreaming()
        self.manager = manager

        let (stream, continuation) = AsyncStream<[Float]>.makeStream()
        setContinuation(continuation)

        // Confirmed text accumulates; the volatile tail is replaced each update.
        updates = Task {
            var confirmed = ""
            for await update in await manager.transcriptionUpdates {
                if update.isConfirmed {
                    confirmed += update.text
                    onPartial(confirmed)
                } else {
                    onPartial(confirmed + update.text)
                }
            }
        }

        pump = Task {
            for await chunk in stream {
                guard let buffer = Self.makeBuffer(chunk) else { continue }
                await manager.streamAudio(buffer)
            }
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

    /// Closes the session and returns the final transcript.
    public func finish() async throws -> String {
        closeContinuation()

        await pump?.value          // Drain queued audio before asking to finish.
        defer { teardown() }

        guard let manager else { return "" }
        let text = try await manager.finish()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
