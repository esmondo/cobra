# Voice AI Wiki

This wiki is a practical map of modern voice AI: speech recognition, speech synthesis, conversational speech models, native speech-to-speech, full duplex interaction, and the architecture required to ship these capabilities inside an AI product or as a standalone voice application.

It is also the design reference for Cobra, the local macOS push-to-talk dictation app in this repository.

## Start here

- [Architecture](architecture.md): the basic voice-AI pipeline and the tradeoff between cascaded, native-audio, and full-duplex systems.
- [Model landscape](model-landscape.md): frontier, open, Chinese, lightweight, CSM, and duplex models.
- [Deployment guide](deployment.md): local, edge, cloud, and hybrid deployment patterns.
- [Evaluation](evaluation.md): a test plan for latency, accuracy, voice quality, interruption, cost, and safety.
- [Safety and glossary](safety-and-glossary.md): consent, impersonation, watermarking, and key terminology.
- [2026 atlas delta](2026-atlas-delta.md): additions from the supplied Voice Model Atlas, with verification status.

## Scope and evidence

The model landscape is a point-in-time survey. A model's benchmark score, GitHub stars, or social-media popularity is not proof of production suitability. Verify the model card, license, weights, runtime, and task-specific performance before adopting it.

Primary references include the [OpenAI Realtime model documentation](https://developers.openai.com/api/docs/models/gpt-4o-realtime-preview), [Moshi](https://github.com/kyutai-labs/moshi), [Sesame CSM](https://github.com/SesameAILabs/csm), [CosyVoice](https://github.com/QwenAudio/CosyVoice), [GLM-4-Voice](https://github.com/THUDM/GLM-4-Voice), [Step-Audio](https://github.com/stepfun-ai/Step-Audio), [VibeVoice](https://github.com/microsoft/VibeVoice), and [Chatterbox](https://github.com/resemble-ai/chatterbox).

## Cobra today

```text
hotkey -> AudioRecorder -> Transcriber -> TextFormatter -> TextInjector
                                  \-> AppContext tone profile
```

Cobra currently records locally, resamples to 16 kHz mono, transcribes with an in-process Parakeet/CoreML backend, applies deterministic cleanup, and inserts text through Accessibility or pasteboard fallback. The relevant implementation lives under `Sources/CobraCore`.
