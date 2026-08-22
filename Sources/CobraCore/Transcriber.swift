import Foundation

/// Turns a 16 kHz mono WAV file into text.
///
/// Everything downstream depends only on this protocol, so the whisper.cpp
/// server backing v0 can be swapped for an in-process CoreML engine later
/// without touching the engine, the UI, or the iOS target.
public protocol Transcriber: Sendable {
    func transcribe(wavURL: URL) async throws -> String
}

public enum TranscriberError: LocalizedError {
    case binaryNotFound(String)
    case modelNotFound(String)
    case serverFailedToStart(String)
    case requestFailed(String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let path): return "whisper-server not found at \(path). Install it with `brew install whisper-cpp`."
        case .modelNotFound(let path): return "Whisper model not found at \(path)."
        case .serverFailedToStart(let reason): return "whisper-server did not come up: \(reason)"
        case .requestFailed(let reason): return "Transcription request failed: \(reason)"
        case .badResponse: return "whisper-server returned a response that could not be parsed."
        }
    }
}

/// Runs whisper.cpp as a long-lived local HTTP server.
///
/// Shelling out to `whisper-cli` per utterance would repay Metal shader setup
/// and model load every single time — measured at roughly nine seconds cold on
/// an M2. Keeping one server resident moves that cost to app launch.
public final class WhisperServerTranscriber: Transcriber, @unchecked Sendable {
    public struct Configuration: Sendable {
        public var binaryPath: String
        public var modelPath: String
        public var port: Int
        public var threads: Int
        /// Biases the decoder toward words it would otherwise mangle.
        public var initialPrompt: String

        public init(
            binaryPath: String = "/opt/homebrew/bin/whisper-server",
            modelPath: String = NSString(string: "~/.cobra/models/ggml-small.en-q5_1.bin").expandingTildeInPath,
            port: Int = 8899,
            threads: Int = 6,
            initialPrompt: String = ""
        ) {
            self.binaryPath = binaryPath
            self.modelPath = modelPath
            self.port = port
            self.threads = threads
            self.initialPrompt = initialPrompt
        }
    }

    private let configuration: Configuration
    private var process: Process?
    private let session: URLSession

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        self.session = URLSession(configuration: config)
    }

    private var endpoint: URL {
        URL(string: "http://127.0.0.1:\(configuration.port)/inference")!
    }

    /// Launches the server and waits for it to accept requests.
    public func start() async throws {
        guard process == nil else { return }

        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: configuration.binaryPath) else {
            throw TranscriberError.binaryNotFound(configuration.binaryPath)
        }
        guard fileManager.fileExists(atPath: configuration.modelPath) else {
            throw TranscriberError.modelNotFound(configuration.modelPath)
        }

        var arguments = [
            "--model", configuration.modelPath,
            "--host", "127.0.0.1",
            "--port", String(configuration.port),
            "--threads", String(configuration.threads),
            "--no-timestamps",
            "--language", "en",
        ]
        if !configuration.initialPrompt.isEmpty {
            arguments += ["--prompt", configuration.initialPrompt]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.binaryPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw TranscriberError.serverFailedToStart(error.localizedDescription)
        }
        self.process = process

        try await waitUntilReady()
    }

    public func stop() {
        process?.terminate()
        process = nil
    }

    /// Polls the server until it answers, so the first dictation does not race
    /// model loading.
    private func waitUntilReady(timeout: TimeInterval = 90) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError = "timed out"

        while Date() < deadline {
            if let process, !process.isRunning {
                throw TranscriberError.serverFailedToStart("process exited with status \(process.terminationStatus)")
            }
            do {
                var request = URLRequest(url: URL(string: "http://127.0.0.1:\(configuration.port)/")!)
                request.timeoutInterval = 2
                _ = try await session.data(for: request)
                return  // Any HTTP answer means the listener is up.
            } catch {
                lastError = error.localizedDescription
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        throw TranscriberError.serverFailedToStart(lastError)
    }

    public func transcribe(wavURL: URL) async throws -> String {
        let boundary = "cobra.\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try multipartBody(wavURL: wavURL, boundary: boundary)

        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            throw TranscriberError.requestFailed(error.localizedDescription)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String else {
            throw TranscriberError.badResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func multipartBody(wavURL: URL, boundary: String) throws -> Data {
        var body = Data()

        func addField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(try Data(contentsOf: wavURL))
        body.append(Data("\r\n".utf8))

        addField("response_format", "json")
        addField("temperature", "0.0")

        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    deinit { stop() }
}
