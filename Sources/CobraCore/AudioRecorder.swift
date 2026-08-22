import AVFoundation
import Foundation

/// Captures microphone audio and resamples it to the 16 kHz mono Float32 format
/// Whisper expects. One instance handles one utterance at a time: samples are
/// buffered in memory while recording, then flushed to a temporary WAV file.
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

    /// Whisper is trained on 16 kHz mono audio; anything else has to be resampled.
    private static let targetSampleRate = 16_000.0

    /// Utterances below this length are almost always an accidental hotkey tap.
    private static let minimumDuration = 0.25

    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioRecorder.targetSampleRate,
        channels: 1,
        interleaved: false
    )!

    private let lock = NSLock()
    private var samples: [Float] = []
    private var isRunning = false

    public init() {}

    /// Seconds of audio captured so far.
    public var duration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Double(samples.count) / Self.targetSampleRate
    }

    /// Peak amplitude of the most recent capture window, for level metering.
    public private(set) var level: Float = 0

    public func start() throws {
        guard !isRunning else { return }

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

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

    /// Stops capture and returns the utterance as 16 kHz mono Float32 samples,
    /// which is exactly what the transcriber consumes — no file round-trip.
    public func stop() throws -> [Float] {
        teardown()

        lock.lock()
        let captured = samples
        samples.removeAll()
        lock.unlock()

        guard Double(captured.count) / Self.targetSampleRate >= Self.minimumDuration else {
            throw RecorderError.tooShort
        }
        return captured
    }

    /// Stops capture and discards everything recorded.
    public func cancel() {
        teardown()
        lock.lock()
        samples.removeAll()
        lock.unlock()
    }

    private func teardown() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        level = 0
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

        lock.lock()
        samples.append(contentsOf: frames)
        lock.unlock()
    }
}
