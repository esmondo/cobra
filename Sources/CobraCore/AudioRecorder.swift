import AVFoundation
import Foundation

/// Captures microphone audio and resamples it to the 16 kHz mono Float32 format
/// the speech models expect.
///
/// The engine runs continuously once `prepare()` is called rather than starting
/// on each keypress. Two things need that: `AVAudioEngine.start()` is not
/// instantaneous and people begin speaking as they press the key, so a
/// start-on-demand recorder loses the first syllable; and live partial
/// transcription needs audio flowing before the utterance is over.
///
/// The cost is that macOS shows the microphone-in-use indicator for as long as
/// Cobra is running. Nothing is written to disk, and audio outside an utterance
/// lives only in a 0.4 s rolling buffer that is continuously overwritten.
public final class AudioRecorder: @unchecked Sendable {
    public enum RecorderError: LocalizedError {
        case converterUnavailable
        case engineStartFailed(String)
        case tooShort

        public var errorDescription: String? {
            switch self {
            case .converterUnavailable: return "Could not build an audio converter for the input device."
            case .engineStartFailed(let reason): return "Audio engine failed to start: \(reason)"
            case .tooShort: return "Recording was too short to transcribe."
            }
        }
    }

    /// The speech models are trained on 16 kHz mono audio.
    private static let targetSampleRate = 16_000.0

    /// Utterances below this length are almost always an accidental hotkey tap.
    private static let minimumDuration = 0.25

    /// How much audio from before the keypress is prepended to each utterance.
    private static let preRollDuration = 0.4

    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioRecorder.targetSampleRate,
        channels: 1,
        interleaved: false
    )!

    private let lock = NSLock()
    private var samples: [Float] = []
    /// Rolling window of the most recent audio, kept whenever the engine runs.
    private var preRoll: [Float] = []
    private var isCapturing = false
    private var isRunning = false

    /// Called with each newly converted block while capturing, for live
    /// transcription. Invoked on the audio thread — do not block.
    public var onCapturedChunk: (@Sendable ([Float]) -> Void)?

    public init() {}

    /// Peak amplitude of the most recent capture window, for level metering.
    public private(set) var level: Float = 0

    public var duration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Double(samples.count) / Self.targetSampleRate
    }

    private var preRollCapacity: Int { Int(Self.preRollDuration * Self.targetSampleRate) }

    /// Starts the audio engine. Safe to call more than once.
    public func prepare() throws {
        guard !isRunning else { return }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.converterUnavailable
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer, using: converter)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecorderError.engineStartFailed(error.localizedDescription)
        }
        isRunning = true
    }

    /// Begins an utterance and returns the pre-roll it was seeded with, so a
    /// streaming consumer can be fed the same audio the batch buffer holds.
    @discardableResult
    public func beginCapture() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        samples = preRoll
        isCapturing = true
        return preRoll
    }

    /// Ends the utterance and returns its samples.
    public func endCapture() throws -> [Float] {
        lock.lock()
        let captured = samples
        samples.removeAll()
        isCapturing = false
        lock.unlock()

        level = 0
        guard Double(captured.count) / Self.targetSampleRate >= Self.minimumDuration else {
            throw RecorderError.tooShort
        }
        return captured
    }

    /// Ends the utterance and throws its audio away.
    public func cancelCapture() {
        lock.lock()
        samples.removeAll()
        isCapturing = false
        lock.unlock()
        level = 0
    }

    /// Stops the engine entirely. Used at shutdown.
    public func teardown() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        cancelCapture()
    }

    private func append(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter) {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        // The converter pulls input through this block; hand it the buffer once,
        // then report that the stream is drained so it flushes what it has.
        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        guard conversionError == nil,
              output.frameLength > 0,
              let channel = output.floatChannelData?[0] else { return }

        let frames = UnsafeBufferPointer(start: channel, count: Int(output.frameLength))

        var peak: Float = 0
        for sample in frames { peak = max(peak, abs(sample)) }
        level = peak

        let chunk = Array(frames)

        lock.lock()
        if isCapturing {
            samples.append(contentsOf: chunk)
        }
        preRoll.append(contentsOf: chunk)
        if preRoll.count > preRollCapacity {
            preRoll.removeFirst(preRoll.count - preRollCapacity)
        }
        let capturing = isCapturing
        lock.unlock()

        if capturing { onCapturedChunk?(chunk) }
    }
}
