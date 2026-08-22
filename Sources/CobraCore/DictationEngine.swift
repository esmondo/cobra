import AVFoundation
import Foundation
import SwiftUI

/// Wires capture, transcription, cleanup and injection into one loop, and owns
/// the state the UI renders.
@MainActor
public final class DictationEngine: ObservableObject {
    public enum State: Equatable {
        case starting
        case idle
        case recording
        case transcribing
        case needsPermission(String)
        case failed(String)

        public var isBusy: Bool {
            self == .recording || self == .transcribing
        }
    }

    @Published public private(set) var state: State = .starting
    @Published public private(set) var lastTranscript: String = ""
    @Published public private(set) var isHandsFree = false

    private let recorder = AudioRecorder()
    private let transcriber: WhisperServerTranscriber
    private let formatter: TextFormatter
    private var hotkeys: HotkeyMonitor?

    public init(
        transcriber: WhisperServerTranscriber = WhisperServerTranscriber(),
        formatter: TextFormatter = RuleFormatter()
    ) {
        self.transcriber = transcriber
        self.formatter = formatter
    }

    /// Requests permissions, boots the speech server, and arms the hotkeys.
    public func start() async {
        guard await requestMicrophoneAccess() else {
            state = .needsPermission("Microphone access is required. Grant it in System Settings › Privacy & Security › Microphone.")
            return
        }

        let monitor = HotkeyMonitor { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        guard monitor.start() else {
            state = .needsPermission("Accessibility access is required to see the fn key and to type into other apps. Grant it in System Settings › Privacy & Security › Accessibility, then relaunch Cobra.")
            return
        }
        hotkeys = monitor

        do {
            try await transcriber.start()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        state = .idle
    }

    public func shutdown() {
        hotkeys?.stop()
        recorder.cancel()
        transcriber.stop()
    }

    private func handle(_ event: HotkeyEvent) {
        switch event {
        case .pushToTalkBegan:
            guard !isHandsFree else { return }
            beginRecording()

        case .pushToTalkEnded:
            guard !isHandsFree, state == .recording else { return }
            finishRecording()

        case .handsFreeToggled:
            if isHandsFree {
                isHandsFree = false
                if state == .recording { finishRecording() }
            } else {
                isHandsFree = true
                beginRecording()
            }
        }
    }

    private func beginRecording() {
        guard state == .idle else { return }
        do {
            try recorder.start()
            state = .recording
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func finishRecording() {
        // Capture the frontmost app before transcription, because the user may
        // click elsewhere while Whisper is still working.
        let context = AppContext.current()

        let wavURL: URL
        do {
            wavURL = try recorder.stop()
        } catch {
            state = .idle  // A too-short tap is not worth surfacing as an error.
            return
        }

        state = .transcribing
        Task {
            defer { try? FileManager.default.removeItem(at: wavURL) }
            do {
                let raw = try await transcriber.transcribe(wavURL: wavURL)
                let cleaned = await formatter.format(raw, context: context)
                guard !cleaned.isEmpty else {
                    state = .idle
                    return
                }
                lastTranscript = cleaned
                TextInjector.inject(cleaned)
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}
