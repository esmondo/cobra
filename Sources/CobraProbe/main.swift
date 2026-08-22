import AVFoundation
import CobraCore
import Foundation

/// Command-line harness for the transcription layer.
///
/// Exists so a backend can be swapped and measured without launching the menu
/// bar app or granting Accessibility — and so competing backends can be
/// compared on the same audio.
///
///     swift run CobraProbe path/to/audio.wav

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: CobraProbe <audio-file>\n".utf8))
    exit(2)
}

let url = URL(fileURLWithPath: arguments[1])

/// Reads any audio file AVFoundation understands and converts it to the
/// 16 kHz mono Float32 the transcriber expects.
func loadSamples(from url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    guard let converter = AVAudioConverter(from: file.processingFormat, to: target) else {
        throw NSError(domain: "CobraProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "no converter"])
    }

    let capacity = AVAudioFrameCount(Double(file.length) * target.sampleRate / file.processingFormat.sampleRate) + 4096
    guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
        throw NSError(domain: "CobraProbe", code: 2, userInfo: [NSLocalizedDescriptionKey: "no buffer"])
    }

    var finished = false
    var error: NSError?
    converter.convert(to: output, error: &error) { packets, status in
        guard !finished,
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: packets) else {
            status.pointee = .endOfStream
            return nil
        }
        do {
            try file.read(into: input, frameCount: packets)
        } catch {
            status.pointee = .endOfStream
            return nil
        }
        if input.frameLength == 0 {
            finished = true
            status.pointee = .endOfStream
            return nil
        }
        status.pointee = .haveData
        return input
    }
    if let error { throw error }

    guard let channel = output.floatChannelData?[0] else { return [] }
    return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
}

let streamMode = arguments.contains("--stream")
let samples = try loadSamples(from: url)
let seconds = Double(samples.count) / 16_000
print("audio: \(String(format: "%.2f", seconds))s, \(samples.count) samples")

let transcriber = ParakeetTranscriber()

var loadStart = Date()
try await transcriber.prepare { progress in
    if case .downloading(let fraction) = progress {
        FileHandle.standardError.write(Data("\rdownloading \(Int(fraction * 100))%".utf8))
    }
}
print("model ready in \(String(format: "%.2f", -loadStart.timeIntervalSinceNow))s")

// Two passes: the first includes CoreML's lazy first-inference setup, the
// second is what a real dictation press actually costs.
for pass in 1...2 {
    let start = Date()
    let text = try await transcriber.transcribe(samples: samples)
    let elapsed = -start.timeIntervalSinceNow
    let realtime = seconds / elapsed
    print("pass \(pass): \(String(format: "%.3f", elapsed))s  (\(String(format: "%.0f", realtime))x realtime)")
    if pass == 2 { print("text: \(text)") }
}


// --stream measures how quickly partial text comes back, which is the number
// that decides whether live transcription feels responsive. Audio is fed in
// 100 ms slices to imitate a microphone rather than handing over the whole
// utterance at once, which would collapse the latency being measured.
if streamMode {
    let streaming = StreamingTranscriber()
    try await streaming.prepare { _ in }

    let start = Date()
    var firstUpdate: TimeInterval?
    try await streaming.begin { text in
        let elapsed = -start.timeIntervalSinceNow
        if firstUpdate == nil { firstUpdate = elapsed }
        print(String(format: "  %6.2fs  partial(%d): %@", elapsed, text.count, text))
    }

    let slice = 1_600  // 100 ms at 16 kHz
    for offset in stride(from: 0, to: samples.count, by: slice) {
        streaming.feed(Array(samples[offset..<min(offset + slice, samples.count)]))
        try await Task.sleep(for: .milliseconds(100))
    }

    let final = try await streaming.finish(samples: samples)
    print(String(format: "first partial: %@", firstUpdate.map { String(format: "%.2fs", $0) } ?? "NEVER"))
    print(String(format: "total: %.2fs for %.2fs of audio", -start.timeIntervalSinceNow, seconds))
    print("final: \(final)")
    exit(0)
}
