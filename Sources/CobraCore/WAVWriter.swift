import Foundation

/// Writes 16-bit PCM WAV files. Whisper accepts these directly, and hand-rolling
/// the 44-byte header avoids negotiating formats with AVAudioFile.
enum WAVWriter {
    static func write(samples: [Float], sampleRate: Int, to url: URL) throws {
        let channels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = samples.count * bitsPerSample / 8

        var data = Data(capacity: 44 + dataSize)

        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))                  // PCM subchunk size
        append(UInt16(1))                   // PCM format tag
        append(UInt16(channels))
        append(UInt32(sampleRate))
        append(UInt32(byteRate))
        append(UInt16(blockAlign))
        append(UInt16(bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            append(Int16(clamped * Float(Int16.max)))
        }

        try data.write(to: url, options: .atomic)
    }
}
