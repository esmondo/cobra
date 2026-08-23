# Cobra

Push-to-talk dictation for macOS. Hold a key, talk, release — cleaned-up text
lands in whatever text field has focus.

Speech never leaves the machine. Transcription runs on the Neural Engine.

> **Status:** working skeleton. The full loop runs: hotkey, capture, live
> transcription, injection. The LLM cleanup tier is the next substantial piece
> and is blocked on the macOS 26 SDK.

## Requirements

- Apple Silicon Mac, macOS 14 or later
- ~500 MB of disk for the speech model, downloaded on first launch
- Swift 6.0+ — the Command Line Tools suffice, full Xcode is not needed

## Install

From the directory where you want to keep Cobra, run:

```sh
git clone https://github.com/esmondo/cobra.git && cd cobra && ./Scripts/make-cert.sh && ./Scripts/bundle.sh && open build/Cobra.app
```

Or, from an existing checkout:

```sh
./Scripts/make-cert.sh    # once — stable signing identity
./Scripts/bundle.sh
open build/Cobra.app
```

Run `make-cert.sh` first. It takes a second and saves a lot of irritation: an
ad-hoc signature changes on every build, macOS then treats each rebuild as a
different program, and your permissions are silently dropped. macOS asks for
confirmation when a build uses the signing key.

## Permissions

Both are required and neither can be requested silently.

| Permission | Needed for |
| --- | --- |
| **Microphone** | Audio capture. Prompted on first launch. |
| **Accessibility** | Seeing the fn key, and typing into other apps. |

Cobra waits rather than giving up — grant Accessibility in System Settings and
startup resumes on its own, no relaunch. If a grant looks enabled but Cobra
still reports it missing, the stored entry is stale; see
[SECURITY.md](SECURITY.md).

## Use

| Key | Action |
| --- | --- |
| Hold **fn** | Record while held, insert on release |
| **fn + H** | Start hands-free recording |
| **fn** | Stop hands-free recording |

Words appear in the floating pill while you speak. The pill follows your text
caret where the app exposes one, and sits at the bottom of the screen where it
does not.

## How it works

```
fn down ─▶ AudioRecorder ─▶ 16 kHz mono, plus 0.4 s of pre-roll
                                    │
                                    ▼
                   Parakeet TDT v3 · CoreML · sliding window
                                    │
                    partial text ◀──┴──▶ final transcript
                          │                     │
                          ▼                     ▼
                        HUD              TextFormatter (+ app tone)
                                                │
                                                ▼
                              TextInjector: Accessibility, else paste
```

The microphone runs continuously while Cobra is open. That is what makes the
pre-roll possible: `AVAudioEngine.start()` is not instantaneous and people begin
speaking as they press, so a start-on-demand recorder loses the first syllable.
The cost is that macOS shows its microphone indicator the whole time. Nothing is
written to disk.

### Performance

Measured on an M2 (8 GB), 4.4 s of speech:

| Engine | Latency | Realtime | Peak RSS |
| --- | --- | --- | --- |
| Parakeet TDT v3 (CoreML) | 0.114 s | 39× | 75 MB |
| whisper.cpp `small.en-q5_1` (replaced) | 0.417 s | 11× | — |

Model weights sit in the Neural Engine rather than the process, which is why a
0.6 B model costs 75 MB of RSS against 461 MB on disk.

Reproduce with the probe, which needs no GUI and no permissions:

```sh
swift run CobraProbe path/to/audio.wav
```

## Languages

English by default. Parakeet v3 covers 25 European languages and **no Asian
languages** — there is no Indonesian, Japanese, Chinese or Korean support, and
no configuration reaches them. That needs a different model; WhisperKit
`large-v3-turbo` is the intended route.

## Layout

| Path | Role |
| --- | --- |
| `Sources/CobraCore/AudioRecorder.swift` | Capture, resampling, pre-roll |
| `Sources/CobraCore/HotkeyMonitor.swift` | `CGEventTap` for modifier-only keys |
| `Sources/CobraCore/StreamingTranscriber.swift` | Live transcription |
| `Sources/CobraCore/ParakeetTranscriber.swift` | Batch backend, used by the probe |
| `Sources/CobraCore/Transcriber.swift` | Backend-agnostic protocol |
| `Sources/CobraCore/TextFormatter.swift` | Transcript cleanup |
| `Sources/CobraCore/AppContext.swift` | Frontmost app, tone profile |
| `Sources/CobraCore/CaretLocator.swift` | Caret position for the HUD |
| `Sources/CobraCore/TextInjector.swift` | Accessibility insert, paste fallback |
| `Sources/CobraCore/DictationEngine.swift` | State machine over the above |
| `Sources/CobraMac/` | Menu bar, HUD, theme, mark |
| `Sources/CobraProbe/` | Benchmark harness |
| `Scripts/cobra.pixels` | The logo, as a pixel map |

## Brand

Matte black, one acid-green accent, faint scanlines.

| Token | Value |
| --- | --- |
| Background | `#0B0B0D` |
| Surface | `#141417` |
| Border | `#2A2A30` |
| Text | `#E8E8EA` |
| Accent (venom) | `#7CFF4F` |
| Danger | `#FF4F5E` |

The HUD commits to this palette instead of following the system appearance: it
floats over other people's apps, and a light pill glares over a dark editor.

Edit `Scripts/cobra.pixels` to change the logo. That map generates both the app
icon and the menu bar glyph, so the two cannot drift apart.

## Releases

Tagging a commit `v*` builds Cobra on CI and publishes a GitHub Release with a
zipped app. Installed copies check that endpoint every six hours and surface
**Update available** in the menu, linking to the release page. Cobra never
installs an update itself — see below for why.

```sh
git tag v0.3.0 && git push origin v0.3.0
```

Builds are **not notarised**, so macOS quarantines the download and blocks the
first launch. Users have to clear the flag by hand:

```sh
xattr -dr com.apple.quarantine /Applications/Cobra.app
```

Fixing that properly needs a Developer ID certificate and notarisation, which
requires a paid Apple Developer account. Until then Cobra is practical to share
with people willing to run one command, and not with anyone else.

## Roadmap

1. **Documentation** — see [docs/DOCUMENTATION-PLAN.md](docs/DOCUMENTATION-PLAN.md).
2. **LLM cleanup tier** — the current formatter only strips unambiguous fillers.
   Real rewriting is what separates dictation from transcription. Apple's
   `FoundationModels` is the target; it needs the macOS 26 SDK.
3. **Correction dictionary** — names and jargon, via vocabulary boosting, which
   the streaming backend supports.
4. **Configurable hotkeys** — currently hardcoded, which collides with other
   dictation apps.
5. **`SpeechAnalyzer` backend** — macOS 26; zero app memory. `CobraProbe` exists
   to A/B it against Parakeet.
6. **Tests** — target-identity checks are covered; audio, streaming and UI
   integration coverage are still needed.
7. **Settings window**, launch at login, notarised distribution.

## Known limitations

- Automated coverage is currently limited to target-identity checks.
- Hotkeys are not configurable.
- Apps with custom controls may not identify secure text fields to Accessibility.
- The pasteboard fallback briefly exposes dictated text to local clipboard readers.
- Hands-free mode records until toggled off; there is no silence detection.
- English and European languages only.

## License

MIT — see [LICENSE](LICENSE). Third-party software and model attributions are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
