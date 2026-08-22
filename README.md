# Cobra

Push-to-talk dictation for macOS. Hold a key, talk, and cleaned-up text appears
in whatever app you were already typing in.

Speech never leaves the machine — transcription runs on the Neural Engine.

## Status

v0.2 — the full loop works. Parakeet TDT 0.6B v3 on CoreML, branded HUD.

## Requirements

- Apple Silicon Mac, macOS 14+
- ~500 MB of disk for the speech model, downloaded on first launch

## Build and run

```sh
./Scripts/bundle.sh
open build/Cobra.app
```

First launch downloads the model (a few minutes) and asks for **Microphone**
and **Accessibility**. Both are required: Accessibility is what lets Cobra see
the fn key and type into other apps. Grant them, then relaunch.

Run `Scripts/make-cert.sh` once to create a stable signing identity — otherwise
macOS treats every rebuild as a new program and asks again.

## Controls

| Key | Action |
| --- | --- |
| Hold **fn** | Record while held, insert on release |
| Double-tap **right Shift** | Toggle hands-free recording |

## How it works

```
fn down ──▶ AudioRecorder ──▶ 16 kHz mono Float32 samples
                                   │
                                   ▼
                    Parakeet TDT v3 (CoreML, ANE)
                                   │
                                   ▼
                    TextFormatter (+ AppContext tone)
                                   │
                                   ▼
              TextInjector: Accessibility, else paste
```

Measured on an M2 (8 GB), 4.4 s of speech:

| | Latency | Realtime factor | Peak RSS |
| --- | --- | --- | --- |
| Parakeet TDT v3 (CoreML) | 0.114 s | 39× | 75 MB |
| whisper.cpp `small.en-q5_1` (previous) | 0.417 s | 11× | — |

The encoder runs on the Neural Engine, the decoder on CPU. Model weights live
in the ANE rather than the process, which is why a 0.6 B model costs 75 MB of
RSS and 461 MB on disk.

## Benchmarking

`CobraProbe` runs the transcription layer without the GUI or any permissions,
so backends can be compared on identical audio:

```sh
swift run CobraProbe path/to/audio.wav
```

## Layout

| Path | Role |
| --- | --- |
| `Sources/CobraCore/AudioRecorder.swift` | Mic capture, resample to 16 kHz mono |
| `Sources/CobraCore/HotkeyMonitor.swift` | CGEventTap for modifier-only hotkeys |
| `Sources/CobraCore/Transcriber.swift` | Backend-agnostic protocol |
| `Sources/CobraCore/ParakeetTranscriber.swift` | CoreML backend |
| `Sources/CobraCore/TextFormatter.swift` | Transcript cleanup |
| `Sources/CobraCore/AppContext.swift` | Frontmost app and tone profile |
| `Sources/CobraCore/CaretLocator.swift` | Caret position for HUD placement |
| `Sources/CobraCore/TextInjector.swift` | Insert text into the focused field |
| `Sources/CobraCore/DictationEngine.swift` | State machine tying it together |
| `Sources/CobraMac/Theme.swift` | Palette, metrics, type |
| `Sources/CobraMac/RecordingHUD.swift` | The floating pill |
| `Sources/CobraMac/HUDController.swift` | Non-activating panel that hosts it |
| `Sources/CobraMac/CobraApp.swift` | Menu bar UI |
| `Sources/CobraProbe/main.swift` | Benchmark harness |

## Brand

Matte black surfaces, one acid-green accent, faint scanlines.

| Token | Value |
| --- | --- |
| Background | `#0B0B0D` |
| Surface | `#141417` |
| Border | `#2A2A30` |
| Text | `#E8E8EA` |
| Accent (venom) | `#7CFF4F` |
| Danger | `#FF4F5E` |

The HUD commits to this palette rather than following the system appearance: it
floats over other people's apps, and a light HUD would glare over a dark editor.

## Roadmap

1. **Silero VAD** — endpoint hands-free mode, trim leading and trailing silence.
   Already available through FluidAudio's `VadManager`.
2. **Smarter formatter** — `RuleFormatter` only strips unambiguous fillers. Real
   rewriting needs a model. Apple's `FoundationModels` is the target, but it
   needs the macOS 26 SDK and the installed Command Line Tools ship 15.5.
3. **SpeechAnalyzer backend** — macOS 26 only; zero app memory and streaming
   partials. Same blocker. `CobraProbe` exists to A/B it against Parakeet.
4. **Settings window** — hotkey binding, per-app tone overrides, custom dictionary.
5. **Launch at login** via `SMAppService`, signing and notarization.

## Known limitations

- Pasteboard fallback restores only the plain-text flavor.
- Hands-free mode records until toggled off; there is no silence detection yet.
- The HUD falls back to the bottom of the screen in apps that expose no caret.
