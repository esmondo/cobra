# Documentation plan

The next implementation pass, chosen because it needs no Xcode 26 and no disk
space — the two things currently blocking the `FoundationModels` formatter and
the `SpeechAnalyzer` backend.

## Why this, now

Cobra's interesting decisions are invisible in the code. Why the microphone runs
continuously, why the HUD refuses focus, why an ad-hoc signature breaks
permissions — each was expensive to work out and none is obvious from reading a
function. Documentation is where that work is banked. It is also the difference
between a repository someone can run and one someone can contribute to.

Every page below has an owner file and an acceptance test: a question a reader
should be able to answer afterwards. A page that does not answer its question is
not done.

## Structure

```
README.md                     what it is, install, use          [exists]
SECURITY.md                   permissions and known risks       [exists]
CONTRIBUTING.md               how to build, test, submit        [exists]
docs/
  architecture.md             the pipeline, and why each seam   [ ]
  permissions.md              TCC, signing, the ad-hoc trap     [ ]
  transcription.md            engines, benchmarks, swapping     [ ]
  audio.md                    capture, pre-roll, metering       [ ]
  injection.md                AX, pasteboard, failure modes     [ ]
  hud.md                      non-activating panel, caret       [ ]
  branding.md                 pixel map, icon generation        [ ]
  decisions/                  ADRs for choices with live tradeoffs
    0001-parakeet-over-whisper.md      [ ]
    0002-continuous-microphone.md      [ ]
    0003-self-signed-certificate.md    [ ]
    0004-streaming-over-batch.md       [ ]
```

## Pages

### `architecture.md`
The pipeline end to end: hotkey, capture, streaming transcription, formatting,
injection. One diagram, then a section per stage naming the type that owns it.
Explains why `Transcriber` and `TextFormatter` are protocols — so a reader
understands where to plug in `SpeechAnalyzer` without being told.

*Answers:* where do I add a new speech engine, and what must it guarantee?

### `permissions.md`
Microphone and Accessibility: what each unlocks, why neither can be requested
silently, and the recovery path when a grant wedges. Documents the ad-hoc
signing trap in full, since the symptom is actively misleading — the toggle
reads as enabled while the app is untrusted, and flipping it changes nothing
because the stale row is the problem.

*Answers:* Cobra says it needs Accessibility but I already granted it. Now what?

### `transcription.md`
Parakeet TDT v3, why it displaced whisper.cpp, and the measured numbers with the
hardware they came from. How to run `CobraProbe`, how to read its output, and
what a new backend must implement. Records that Parakeet covers 25 European
languages and no Asian ones, so the limitation is discoverable before someone
files a bug about Indonesian.

*Answers:* how fast is it here, and how do I compare a different engine?

### `audio.md`
Capture format and why 16 kHz mono, the resampling path, the pre-roll ring
buffer and the clipped-syllable bug it fixes, and how the level meter is fed.

*Answers:* why is the microphone always on?

### `injection.md`
The two strategies, why Accessibility is preferred, which apps fall through to
the pasteboard, exact target binding, and the remaining pasteboard trade-offs.
Should be honest that this is the least reliable stage.

*Answers:* my text went somewhere unexpected — is that known?

### `hud.md`
Why the panel is non-activating, how caret tracking works through
`kAXBoundsForRangeParameterizedAttribute`, and why it falls back to the screen
edge. Notes the fixed-width live transcript and the jitter it prevents.

*Answers:* why does the pill sit at the bottom of my screen in this app?

### `branding.md`
The pixel map as single source of truth, how `make-icon.py` renders both the
`.icns` and the Swift glyph, and why the menu bar mark is an `NSImage` rather
than a SwiftUI `Canvas` — `NSStatusItem` measures its label and `Canvas` has no
intrinsic size, so the icon silently vanishes.

*Answers:* how do I change the logo?

### `decisions/`
Short ADRs, one page each: context, decision, consequences, and what would
justify revisiting. Reserved for choices with a live trade-off — the continuous
microphone and the self-signed certificate both have real costs a future reader
deserves to weigh rather than inherit.

## Sequence

1. `architecture.md` — everything else refers back to it
2. `permissions.md` — highest support burden
3. `transcription.md` and `audio.md` — the substance
4. `injection.md` and `hud.md`
5. `branding.md`
6. ADRs last, once the prose has settled

## Standards

- Every claim about performance names the hardware and the measurement.
- Every known-broken thing is written down, not omitted.
- Code references use `path:line` so they stay clickable.
- No page describes behaviour that does not exist yet; roadmap items live in the
  README and are marked as such.

## Not in scope

API reference generated from doc comments — the public surface is small and
still moving. Revisit if `CobraCore` is ever consumed outside this repository.
