# Contributing

## Requirements

- Apple Silicon Mac, macOS 14 or later
- Swift 6.0+ (the Command Line Tools are enough; full Xcode is not required)
- ~500 MB of disk for the speech model, downloaded on first launch

## Build and run

```sh
./Scripts/make-cert.sh    # once — creates a stable signing identity
./Scripts/bundle.sh       # builds, generates the icon, signs, packages; signing prompts
open build/Cobra.app
```

Run `make-cert.sh` before your first build. Without a stable signing identity
every rebuild is a different program to macOS, and it will drop your Microphone
and Accessibility grants each time. See [SECURITY.md](SECURITY.md).

## Working on transcription

`CobraProbe` exercises the speech layer with no GUI and no permissions, which
makes it the fastest way to test an engine change:

```sh
swift run CobraProbe path/to/audio.wav
```

It reports model load time, per-pass latency and realtime factor. Quote both
passes when reporting numbers — the first includes CoreML's lazy setup and the
second is what a real dictation press costs.

## Changing the icon

Edit `Scripts/cobra.pixels`, then rebuild. The map is the single source of truth
for both the `.icns` and the menu bar glyph; `Scripts/make-icon.py` regenerates
`Sources/CobraMac/CobraPixels.swift`, which should never be edited by hand.

## Conventions

- Comments explain *why*, not what. If a line needs a comment to say what it
  does, rewrite the line.
- Document non-obvious platform behaviour where it bites, not in a wiki. The
  reason `Canvas` cannot be used in the menu bar belongs next to the code that
  works around it.
- Performance claims name the hardware and the measurement.
- Match the surrounding style rather than introducing a new one.

## Pull requests

State what you changed and how you verified it. If you touched the audio or
transcription path, include `CobraProbe` numbers before and after. If you
touched permissions or signing, say which macOS version you tested on — this is
the area most likely to behave differently across releases.
