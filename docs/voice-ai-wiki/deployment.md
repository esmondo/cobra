# Deployment guide

## Decision matrix

| Requirement | Prefer |
|---|---|
| Maximum privacy | Local or edge cascade |
| Fastest path to a polished agent | Hosted realtime audio API |
| Inspectable transcripts and actions | Cascaded architecture |
| Natural interruption and overlap | Native speech-to-speech or duplex |
| Offline dictation | Local ASR plus local formatter |
| Lowest operating cost at scale | Self-hosted small models, after capacity testing |
| Best voice cloning | Hosted premium voice layer or licensed open clone model |
| Mandarin and dialect coverage | Chinese open ecosystem, especially CosyVoice/FunASR/Step-Audio |

## Local desktop

```text
Mic -> native audio capture -> local ASR -> local formatter -> app insertion
```

Advantages: privacy, no network dependency, predictable cost, low data governance burden. Disadvantages: model download, RAM/VRAM limits, device variability, slower updates.

Cobra uses this pattern. Its current design intentionally keeps `Transcriber` and `TextFormatter` as protocols so the backend can change without rewriting the engine or UI.

## Mobile and edge

Use quantization, streaming inference, and short context. Avoid putting a large model inside a constrained keyboard extension. A practical pattern is:

```text
mobile capture -> host app or edge service -> partial transcript -> insertion
```

Measure thermal throttling and battery impact, not just a desktop benchmark. VibeASR.cpp is an example of a speech runtime explicitly optimized for CPU deployment.

## Cloud cascade

```text
browser/phone -> WebRTC gateway -> VAD -> STT -> LLM/tools -> TTS -> client
```

This is the safest production default when the product needs audit logs, tool authorization, moderation, fallback providers, and independent upgrades.

## Cloud native audio / duplex

Use a realtime transport, session-level state, cancellation, and explicit audio events. The client must be able to distinguish:

- input audio started, stopped, or interrupted;
- partial and committed transcript;
- assistant response started, updated, cancelled, or finished;
- tool call started and completed;
- output audio buffered, played, or discarded.

Without these events, a voice UI feels broken even when the model is good.

## Reliability patterns

- Keep a cascaded fallback for native-audio failure.
- Make every response cancellable.
- Bound silence and response timeouts.
- Preserve the last committed transcript separately from partial text.
- Retry network requests only when the audio session is still valid.
- Record timing metadata without retaining raw audio by default.
- Version prompts, models, voices, and decoding parameters.
- Test cold start and warm-session latency separately.

## Licensing checklist

For every model, record:

1. code license;
2. weight license;
3. training-data restrictions;
4. commercial-use terms;
5. voice-cloning consent requirements;
6. watermarking requirements;
7. hosted API data-retention policy;
8. attribution requirements;
9. redistribution restrictions;
10. whether the license applies to every model variant.

Never infer that a repository's Apache or MIT code license automatically covers its weights or generated voices.
