import AVFoundation
import AppKit
import Foundation
import os
import SwiftUI

/// Wires capture, live transcription, cleanup and injection into one loop, and
/// owns the state the UI renders.
@MainActor
public final class DictationEngine: ObservableObject {
    public enum State: Equatable {
        case preparing(TranscriberPreparation)
        case idle
        /// The user switched the microphone off. Distinct from a missing
        /// permission: nothing is wrong, Cobra is simply not listening.
        case microphoneOff
        case recording
        case transcribing
        case notice(String)
        case needsPermission(String)
        case failed(String)

        public var isActive: Bool {
            self == .recording || self == .transcribing
        }
    }

    public enum Permission: Sendable {
        case microphone
        case accessibility

        /// Deep link into the exact Privacy pane rather than the settings root.
        public var settingsURL: URL {
            switch self {
            case .microphone:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
            case .accessibility:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            }
        }
    }

    /// Number of level samples the HUD's meter draws.
    public static let meterResolution = 24

    /// Roughly 30 fps, enough for the meter to feel live without waking the main
    /// actor more often than the display refreshes.
    private static let meterInterval = Duration.milliseconds(33)

    /// The AppDelegate drives the lifecycle while the menu bar scene observes
    /// state, so both need to reach the same instance.
    public static let shared = DictationEngine()

    private static let log = Logger(subsystem: "ai.cobra.mac", category: "engine")

    @Published public private(set) var state: State = .preparing(.loading) {
        didSet {
            guard state != oldValue else { return }
            Self.log.notice("state \(String(describing: oldValue), privacy: .public) -> \(String(describing: self.state), privacy: .public)")
        }
    }
    @Published public private(set) var lastTranscript: String = ""
    @Published public private(set) var isHandsFree = false
    /// Live transcript, updated while the user is still speaking.
    @Published public private(set) var partialText: String = ""
    /// Recent input levels, oldest first. Drives the HUD meter.
    @Published public private(set) var levels: [Float] = Array(repeating: 0, count: DictationEngine.meterResolution)
    /// Which permission is blocking startup, if any. Drives the settings link.
    @Published public private(set) var missing: Permission?
    /// Whether Cobra holds the microphone open. Off means the audio engine is
    /// stopped outright, so macOS drops its recording indicator and dictation
    /// is unavailable until it is switched back on.
    @Published public private(set) var isMicrophoneEnabled: Bool = DictationEngine.storedMicrophonePreference

    private static let microphoneDefaultsKey = "cobra.microphoneEnabled"

    /// Defaults to on for a first run, where the key is absent.
    private static var storedMicrophonePreference: Bool {
        UserDefaults.standard.object(forKey: microphoneDefaultsKey) as? Bool ?? true
    }

    private let recorder = AudioRecorder()
    private let streaming: StreamingTranscriber
    private let formatter: TextFormatter
    private var hotkeys: HotkeyMonitor?
    private var meterTask: Task<Void, Never>?
    private var injectionTarget: TextInjector.Target?

    public init(
        streaming: StreamingTranscriber = StreamingTranscriber(),
        formatter: TextFormatter = RuleFormatter()
    ) {
        self.streaming = streaming
        self.formatter = formatter
    }

    /// Requests permissions, loads the speech model, and arms the hotkeys.
    ///
    /// Blocks on each permission rather than bailing out, so granting access in
    /// System Settings resumes startup instead of requiring a relaunch.
    public func start() async {
        guard await requestMicrophoneAccess() else {
            missing = .microphone
            state = .needsPermission("Cobra needs the microphone to hear you.")
            return
        }

        let monitor = HotkeyMonitor { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }

        if !monitor.start() {
            missing = .accessibility
            state = .needsPermission("Cobra needs Accessibility to see the fn key and type into other apps.")
            HotkeyMonitor.promptForAccessibility()
            await waitForAccessibility(arming: monitor)
        }
        missing = nil
        hotkeys = monitor

        do {
            try await streaming.prepare { [weak self] progress in
                Task { @MainActor in
                    guard let self, case .preparing = self.state else { return }
                    self.state = .preparing(progress)
                }
            }

            // Audio flows continuously from here: the pre-roll needs it, and so
            // does live transcription.
            recorder.onCapturedChunk = { [streaming] chunk in
                streaming.feed(chunk)
            }
            if isMicrophoneEnabled {
                try recorder.prepare()
            }
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        state = isMicrophoneEnabled ? .idle : .microphoneOff
    }

    /// Turns the microphone on or off.
    ///
    /// Off genuinely stops the audio engine rather than muting downstream, so
    /// the macOS recording indicator goes out and the claim that Cobra is not
    /// listening is one the system corroborates.
    public func setMicrophoneEnabled(_ enabled: Bool) {
        guard enabled != isMicrophoneEnabled else { return }
        isMicrophoneEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.microphoneDefaultsKey)

        // Only touch the engine once startup has got far enough to own it;
        // otherwise start() will honour the new preference when it gets there.
        switch state {
        case .preparing, .needsPermission, .failed:
            return
        default:
            break
        }

        if enabled {
            do {
                try recorder.prepare()
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
            }
        } else {
            if state == .recording || isHandsFree {
                isHandsFree = false
                stopMetering()
                recorder.cancelCapture()
                partialText = ""
                Task { await streaming.cancel() }
            }
            recorder.teardown()
            state = .microphoneOff
        }
    }

    public func shutdown() {
        meterTask?.cancel()
        hotkeys?.stop()
        recorder.teardown()
    }

    /// Opens the Privacy pane for whatever is currently blocking startup.
    public func openSettingsForMissingPermission() {
        guard let missing else { return }
        NSWorkspace.shared.open(missing.settingsURL)
    }

    private func handle(_ event: HotkeyEvent) {
        Self.log.notice("hotkey \(String(describing: event), privacy: .public) state=\(String(describing: self.state), privacy: .public) mic=\(self.isMicrophoneEnabled, privacy: .public)")
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
        guard isMicrophoneEnabled, state == .idle else { return }

        partialText = ""
        lastTranscript = ""
        injectionTarget = TextInjector.captureTarget()
        state = .recording
        startMetering()

        Task {
            do {
                // The session must exist before capture starts, or the first
                // chunks have nowhere to go. The pre-roll covers this gap.
                try await streaming.begin { text in
                    Task { @MainActor [weak self] in self?.partialText = text }
                }
                let preRoll = recorder.beginCapture()
                streaming.feed(preRoll)
            } catch {
                stopMetering()
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func finishRecording() {
        stopMetering()

        let target = injectionTarget
        injectionTarget = nil
        let context = target?.context ?? .unknown

        let samples: [Float]
        do {
            samples = try recorder.endCapture()
        } catch {
            // A too-short tap is not worth surfacing as an error, but the
            // streaming session still has to be torn down.
            Task { await streaming.cancel() }
            partialText = ""
            state = .idle
            return
        }

        state = .transcribing
        Task {
            do {
                // The streaming transcript drove the HUD; the inserted text
                // comes from a full-context pass over the same audio.
                let raw = try await streaming.finish(samples: samples)
                let cleaned = await formatter.format(raw, context: context)
                partialText = ""
                guard !cleaned.isEmpty else {
                    state = .idle
                    return
                }
                guard let target else {
                    lastTranscript = cleaned
                    showNotice("Focus changed · transcript saved", for: .seconds(5))
                    return
                }

                switch TextInjector.inject(cleaned, into: target) {
                case .accessibility:
                    lastTranscript = ""
                    state = .idle
                case .pasteboard:
                    lastTranscript = ""
                    showNotice("Pasted through clipboard", for: .seconds(2))
                case .focusChanged:
                    lastTranscript = cleaned
                    showNotice("Focus changed · transcript saved", for: .seconds(5))
                case .pasteboardUnavailable:
                    lastTranscript = cleaned
                    showNotice("Clipboard too complex · transcript saved", for: .seconds(5))
                case .secureField:
                    lastTranscript = cleaned
                    showNotice("Secure field · transcript saved", for: .seconds(5))
                }
            } catch {
                partialText = ""
                state = .failed(error.localizedDescription)
            }
        }
    }

    public func clearSavedTranscript() {
        lastTranscript = ""
    }

    private func showNotice(_ message: String, for duration: Duration) {
        state = .notice(message)
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, self.state == .notice(message) else { return }
            self.state = .idle
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

    /// Retries arming the tap until it succeeds.
    ///
    /// There is no notification when Accessibility is granted, so this polls.
    /// It retries `start()` rather than re-reading `AXIsProcessTrusted`, whose
    /// cached value can stay false for the life of the process and would leave
    /// the app asking for a permission the user has already given.
    private func waitForAccessibility(arming monitor: HotkeyMonitor) async {
        while !monitor.start() {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
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
