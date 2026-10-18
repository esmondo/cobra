# Evaluation

## Test set

Build a fixed set of 30–60 minutes containing:

- Indonesian, English, and code-switching;
- names, companies, URLs, dates, currencies, and technical terms;
- different microphones, accents, speaking rates, and noise levels;
- one-speaker and overlapping two-speaker audio;
- interruptions while the assistant is speaking;
- emotional and style-controlled prompts;
- long-form narration and multi-turn dialogue.

Keep a private golden transcript and annotate entities, speaker turns, endpoint boundaries, and acceptable paraphrases.

## Metrics

### ASR

- Word error rate, with separate entity error rate.
- Character error rate for Chinese.
- Diarization error rate where speakers matter.
- Timestamp drift.
- First partial transcript latency.
- Final transcript latency.

### TTS

- Time to first audio.
- Real-time factor and throughput.
- Speaker similarity.
- Pronunciation accuracy.
- Prosody and emotion control.
- Long-form speaker consistency.
- Artifact rate and interruption recovery.

### Native speech-to-speech and duplex

- End-to-end time to first audible response.
- Barge-in detection latency.
- Time to stop output after interruption.
- Overlap and backchannel quality.
- Turn-taking errors.
- Response grounding and tool-call correctness.
- Transcript fidelity after audio output.

### Product

- Completion rate.
- Abandonment rate.
- Recovery rate after network or model failure.
- Cost per conversation minute.
- CPU/GPU/RAM and battery usage.
- Permission failure rate.
- User preference for voice and interaction mode.

## Benchmark discipline

Compare models under the same:

- audio files and prompts;
- reference voice;
- sampling rate and codec;
- hardware;
- quantization;
- context length;
- temperature and decoding settings;
- concurrency;
- warm or cold start condition.

Do not treat LibriSpeech alone as a production benchmark. It does not capture code-switching, noisy devices, domain vocabulary, overlap, or interruption behavior.

## Suggested acceptance gates

```text
ASR: entity error rate is acceptable on the product vocabulary
Latency: first useful output meets the UX target on target hardware
Duplex: interruption stops output reliably within the chosen threshold
TTS: no repeated mispronunciation of critical names or terms
Reliability: session recovery works without duplicate actions
Privacy: raw audio retention and provider access are explicit
License: code, weights, and voices are commercially compatible
```
