import AVFoundation
import Foundation
import SwiftUI

/// Wires capture, transcription, cleanup and injection into one loop, and owns
/// the state the UI renders.
@MainActor
public final class DictationEngine: ObservableObject {
    public enum State: Equatable {
        case preparing(TranscriberPreparation)
        case idle
        case recording
        case transcribing
        case needsPermission(String)
        case failed(String)

        public var isActive: Bool {
            self == .recording || self == .transcribing
        }
    }

    /// Number of level samples the HUD's meter draws.
    public static let meterResolution = 24

    /// Roughly 30 fps, which is enough for the meter to feel live without
    /// waking the main actor more often than the display refreshes.
    private static let meterInterval = Duration.milliseconds(33)

    @Published public private(set) var state: State = .preparing(.loading)
    @Published public private(set) var lastTranscript: String = ""
    @Published public private(set) var isHandsFree = false
    /// Recent input levels, oldest first. Drives the HUD meter.
    @Published public private(set) var levels: [Float] = Array(repeating: 0, count: DictationEngine.meterResolution)

    private let recorder = AudioRecorder()
    private let transcriber: any Transcriber
    private let formatter: TextFormatter
    private var hotkeys: HotkeyMonitor?
    private var meterTask: Task<Void, Never>?

    public init(
        transcriber: any Transcriber = ParakeetTranscriber(),
        formatter: TextFormatter = RuleFormatter()
    ) {
        self.transcriber = transcriber
        self.formatter = formatter
    }

    /// Requests permissions, loads the speech model, and arms the hotkeys.
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
            try await transcriber.prepare { [weak self] progress in
                Task { @MainActor in
                    guard let self, case .preparing = self.state else { return }
                    self.state = .preparing(progress)
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        state = .idle
    }

    public func shutdown() {
        meterTask?.cancel()
        hotkeys?.stop()
        recorder.cancel()
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
            startMetering()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func finishRecording() {
        stopMetering()

        // Capture the frontmost app before transcription, because the user may
        // click elsewhere while the model is still working.
        let context = AppContext.current()

        let samples: [Float]
        do {
            samples = try recorder.stop()
        } catch {
            state = .idle  // A too-short tap is not worth surfacing as an error.
            return
        }

        state = .transcribing
        Task {
            do {
                let raw = try await transcriber.transcribe(samples: samples)
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

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                var next = self.levels
                next.removeFirst()
                next.append(self.recorder.level)
                self.levels = next
                try? await Task.sleep(for: Self.meterInterval)
            }
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
        levels = Array(repeating: 0, count: Self.meterResolution)
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}
