# Security

Cobra holds permissions that deserve scrutiny: it watches global key events,
keeps a microphone open, and types into other applications. This document
states exactly what it does with each, so the claims can be checked against the
code rather than taken on trust.

## What Cobra can and cannot see

**The event tap cannot read your keystrokes.** `HotkeyMonitor` creates its tap
with `options: .listenOnly` and an event mask of `flagsChanged` alone. That mask
excludes `keyDown` and `keyUp`, so character keys never reach Cobra — only
modifier state transitions. It is also listen-only, meaning it cannot alter or
swallow events. See `Sources/CobraCore/HotkeyMonitor.swift`.

**The microphone is open for as long as Cobra runs.** This is a deliberate
trade-off, not an oversight: capturing the 0.4 s of audio *before* you press the
key is the only way to avoid losing the first syllable, and that requires
already listening. macOS shows its microphone indicator the whole time, which is
the honest signal that this is happening.

Audio is never written to disk and never leaves the machine. Outside an
utterance it lives only in a 0.4 s ring buffer that is continuously overwritten
(`AudioRecorder.preRoll`).

**Transcription is fully local.** Parakeet runs in-process on CoreML. There is
no transcription API, no telemetry, and no analytics.

## Network access

Exactly one network operation exists: the first launch downloads the speech
model from Hugging Face over HTTPS, into
`~/Library/Application Support/FluidAudio/Models`. Nothing is uploaded, ever.

The download is protected by TLS but the model files are not independently
checksummed by Cobra. Pinning a digest is tracked in the roadmap.

## Known risks

These are real and not yet fixed. They are listed rather than hidden.

**Text can land in the wrong window.** Cobra reads the frontmost app when you
release the key, but injects into whatever holds focus when transcription
finishes. Switching apps in that window — typically 100–200 ms — delivers your
text to the new one. Dictating into a chat app and immediately switching windows
can therefore leak that text somewhere you did not intend.

**The pasteboard is used as a fallback.** When Accessibility insertion is
unavailable (common in Electron apps), Cobra writes to the general pasteboard,
synthesises Command-V, and restores the previous contents after 250 ms. During
that window your dictated text is readable by any app that watches the
pasteboard, and only the plain-text flavour is restored — richer clipboard
content is lost.

**Secure input fields.** Cobra does not detect password fields. Do not dictate
credentials.

## Code signing

`Scripts/make-cert.sh` generates a self-signed `Cobra Dev` certificate so the
app has a stable identity across rebuilds. The certificate is **not** added to
the system trust store, and does not need to be — `codesign` accepts it, and
TCC keys on the leaf hash. The private key is stored in your login keychain.
The transient PKCS#12 password is not a secret; the file is created in a
temporary directory and deleted immediately.

This certificate attests to nothing about the code's origin. It exists solely to
give TCC a stable requirement to key against. Do not distribute builds signed
with it as though they were notarised.

## Reporting

Open an issue. There is no private disclosure channel; this is a personal
project, not a service.
