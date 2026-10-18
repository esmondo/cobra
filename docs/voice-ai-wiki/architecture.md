# Voice AI architecture

## The basic pipeline

```text
Microphone
   |
   v
Capture -> resample -> VAD/endpointing -> audio buffer
   |
   +--> STT/ASR ------------------------------+
   |                                           |
   |                                      text transcript
   |                                           |
   |                              LLM / policy / tools
   |                                           |
   |                                      response text
   |                                           |
   +-------------------------------------- TTS
                                               |
                                               v
                                      audio stream -> speaker
```

The cascaded architecture remains the default because every boundary is observable. It supports transcript correction, moderation, tool calls, retries, voice changes, and independent vendor replacement.

## Three architecture families

### Cascaded voice agent

`STT -> LLM -> TTS`.

Use this when correctness, auditability, structured actions, and component-level control matter most. Its disadvantages are accumulated latency, error propagation, and loss of some acoustic information such as tone or overlap.

### Native speech-to-speech

`audio in -> audio-aware model -> audio out`.

The model can preserve conversational cues more naturally and avoid a visible text boundary. It is harder to inspect, evaluate, moderate, and replace. GPT-4o Realtime, Gemini native audio systems, Qwen2.5-Omni, GLM-4-Voice, and Step-Audio belong to this broad family.

### Full duplex

The model listens and speaks at the same time. A real full-duplex system needs interruption handling, overlapping speech, backchannels, turn-taking, and synchronized input/output streams. Streaming TTS alone is not full duplex.

Moshi is the clearest open reference. Its paper reports theoretical latency of 160 ms and about 200 ms in practice, while the repository includes PyTorch, MLX, and Rust paths. Commercial examples include GPT-4o Realtime and Gemini Live.

## Feature architecture inside an AI product

```text
UI / hotkey / phone / browser
              |
        session controller
              |
   +----------+----------+
   |                     |
audio transport       policy layer
 WebRTC/WebSocket      auth, consent,
                       tools, moderation
   |                     |
   +----------+----------+
              |
       voice runtime
   +----------+----------+
   |          |          |
  VAD        ASR       TTS / S2S
   |          |          |
   +------ dialogue state
              |
       LLM and tool loop
              |
      events, transcript,
      metrics, persistence
```

Keep these concerns separate:

- **Capture:** microphone permissions, device choice, sample rate, echo cancellation.
- **Endpointing:** voice activity detection, silence timeout, barge-in detection.
- **Transport:** chunking, jitter, reconnection, backpressure, codec choice.
- **Inference:** ASR, LLM, TTS, native-audio, or duplex model.
- **Dialogue state:** partial transcript, committed transcript, response state, interruption state.
- **Policy:** tool authorization, PII handling, moderation, consent, voice identity rules.
- **Presentation:** captions, waveform, partial text, speaking indicator, error recovery.
- **Observability:** time to first token, time to first audio, end-to-end latency, WER, interruption latency, cost.

## Cobra mapping

| Voice layer | Cobra implementation | Next likely seam |
|---|---|---|
| Capture | `AudioRecorder` | VAD and endpointing |
| Hotkey / session | `HotkeyMonitor`, `DictationEngine` | streaming session state |
| ASR | `Transcriber`, `ParakeetTranscriber` | partial transcripts, WhisperKit/SpeechAnalyzer backend |
| Rewrite | `TextFormatter`, `RuleFormatter` | local model formatter |
| Context | `AppContext`, `ToneProfile` | richer field and selection context |
| Output | `TextInjector` | full pasteboard flavor preservation |
| UI | `CobraMac` | partials, confidence, latency, cancellation |

## Latency budget

For a push-to-talk dictation product, optimize the path differently from a conversational agent:

```text
press/release -> audio flush -> decode -> cleanup -> insertion
```

For a conversational agent, the critical metric is first audible response:

```text
user speech end or barge-in -> endpoint -> first response token -> first audio frame
```

Do not optimize only model inference. Device wake-up, audio conversion, network round trips, queueing, and TTS buffering often dominate.
