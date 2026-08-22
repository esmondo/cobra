# Cobra

Push-to-talk dictation for macOS. Hold a key, talk, and cleaned-up text appears
in whatever app you were already typing in.

Speech never leaves the machine: transcription runs locally on the Apple Silicon
GPU via whisper.cpp.

## Status

v0 skeleton — the full loop works on macOS. iOS is not started (see Roadmap).

## Requirements

- Apple Silicon Mac, macOS 14+
- `brew install whisper-cpp ffmpeg`
- A Whisper model at `~/.cobra/models/ggml-small.en-q5_1.bin`:

```sh
mkdir -p ~/.cobra/models && curl -L -o ~/.cobra/models/ggml-small.en-q5_1.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-q5_1.bin
```

## Build and run

```sh
./Scripts/bundle.sh
open build/Cobra.app
```

On first launch macOS asks for **Microphone** and **Accessibility**. Both are
required: Accessibility is what lets Cobra see the fn key and type into other
apps. Grant them, then relaunch.

Run `Scripts/make-cert.sh` once to create a stable signing identity — otherwise
macOS treats every rebuild as a new program and asks again.

## Controls

| Key | Action |
| --- | --- |
| Hold **fn** | Record while held, insert on release |
| Double-tap **right Shift** | Toggle hands-free recording |

## How it works

```
fn down ──▶ AudioRecorder ──▶ 16 kHz mono WAV
                                   │
                                   ▼
                         whisper-server (resident)
                                   │
                                   ▼
                    TextFormatter (+ AppContext tone)
                                   │
                                   ▼
              TextInjector: Accessibility, else paste
```

`whisper-server` runs as a child process for the app's lifetime. Shelling out to
`whisper-cli` per utterance would repay Metal shader setup and model load every
time — about 9 s cold on an M2. Keeping the server resident puts a warm
transcription at roughly 0.4 s for a 4 s utterance.

## Layout

| Path | Role |
| --- | --- |
| `Sources/CobraCore/AudioRecorder.swift` | Mic capture, resample to 16 kHz mono |
| `Sources/CobraCore/HotkeyMonitor.swift` | CGEventTap for modifier-only hotkeys |
| `Sources/CobraCore/Transcriber.swift` | `Transcriber` protocol + whisper-server backend |
| `Sources/CobraCore/TextFormatter.swift` | Transcript cleanup |
| `Sources/CobraCore/AppContext.swift` | Frontmost app and tone profile |
| `Sources/CobraCore/TextInjector.swift` | Insert text into the focused field |
| `Sources/CobraCore/DictationEngine.swift` | State machine tying it together |
| `Sources/CobraMac/CobraApp.swift` | Menu bar UI |

`Transcriber` and `TextFormatter` are protocols so the engine, the UI, and a
future iOS target never depend on which backend is in use.

## Roadmap

1. **Silero VAD** — endpoint hands-free mode, trim leading and trailing silence.
2. **Smarter formatter** — the current `RuleFormatter` only strips unambiguous
   fillers. Real rewriting needs a model. Apple's `FoundationModels` framework
   (on-device, free) is the target, but it needs the macOS 26 SDK; the installed
   Command Line Tools ship 15.5, so this is blocked on installing Xcode 26.
3. **WhisperKit** — replace the whisper-server subprocess with in-process CoreML
   so the work runs on the Neural Engine instead of the GPU, and so the same
   code compiles for iOS.
4. **Streaming partials** — show text as it is spoken instead of after release.
5. **iOS** — a custom keyboard extension is the only way to reach every app.
   Extensions are capped near 60 MB of memory, so Whisper cannot run inside one;
   audio has to hand off to the host app or to a server.
6. **Full pasteboard preservation** — restore every flavor, not just plain text.

## Known limitations

- Pasteboard fallback restores only the plain-text flavor.
- Hands-free mode records until toggled off; there is no silence detection yet.
- English only (`small.en`).
